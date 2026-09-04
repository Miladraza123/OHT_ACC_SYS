-- ============================================================
--  06 — Weighted-average perpetual costing engine
--
--  Har item ka avg_cost aur stock_qty poori transaction history se
--  dobara ginta hai. Purchase par loading/cartage/cutting charges
--  landed cost mein shamil hote hain (value ke hisaab se baante jate hain).
--  Sale par us waqt ka average cost voucher_lines.cost_amount mein likha jata hai.
--  Return par ASAL sale ke per-unit cost par maal wapas aata hai, naye
--  average par nahi — taake us waqt ka COGS bilkul theek reverse ho.
--
--  Period Lock lagi ho to item_cost_snapshot se shuru karta hai
--  (poori history dobara ginne ki zaroorat nahi rehti).
-- ============================================================

create or replace function public.recompute_item_cost(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  it            record;
  snap          record;
  ln            record;
  run_qty       numeric;
  run_cost      numeric;
  cutoff        date;
  extra         numeric;
  voucher_total numeric;
  landed_rate   numeric;
  new_qty       numeric;
begin
  select * into it from items where id = p_item_id;
  if not found then return; end if;

  select locked_before into cutoff from period_lock where id = 1;
  select * into snap from item_cost_snapshot where item_id = p_item_id;

  if snap.item_id is not null and cutoff is not null and snap.as_of_date = cutoff then
    run_qty  := snap.stock_qty;
    run_cost := snap.avg_cost;
  else
    run_qty  := coalesce(it.opening_qty, 0);
    run_cost := coalesce(it.opening_rate, 0);
    cutoff   := null;
  end if;

  for ln in
    (
      select vl.id as line_id, vl.qty, vl.rate, v.vtype, v.vdate, v.id as voucher_id,
             v.loading_amt, v.cartage_amt, v.cutting_amt,
             v.loading_on, v.cartage_on, v.cutting_on,
             null::numeric as ret_cost
        from voucher_lines vl
        join vouchers v on v.id = vl.voucher_id
       where vl.item_id = p_item_id
         and v.deleted_at is null
         and (cutoff is null or v.vdate >= cutoff)
    )
    union all
    (
      select srl.id as line_id, srl.qty, srl.rate, 'return'::text as vtype,
             sr.rdate as vdate, sr.id as voucher_id,
             0::numeric as loading_amt, 0::numeric as cartage_amt, 0::numeric as cutting_amt,
             false as loading_on, false as cartage_on, false as cutting_on,
             srl.cost_amount as ret_cost
        from sales_return_lines srl
        join sales_returns sr on sr.id = srl.return_id
       where srl.item_id = p_item_id
         and sr.deleted_at is null
         and (cutoff is null or sr.rdate >= cutoff)
    )
    order by vdate asc, line_id asc
  loop

    if ln.vtype = 'purchase' then
      select coalesce(sum(qty * rate), 0) into voucher_total
        from voucher_lines where voucher_id = ln.voucher_id;

      extra := (case when ln.loading_on then ln.loading_amt else 0 end)
             + (case when ln.cartage_on then ln.cartage_amt else 0 end)
             + (case when ln.cutting_on then ln.cutting_amt else 0 end);

      if voucher_total > 0 and ln.qty > 0 then
        landed_rate := ln.rate + (extra * (ln.qty * ln.rate) / voucher_total) / ln.qty;
      else
        landed_rate := ln.rate;
      end if;

      new_qty := run_qty + ln.qty;
      if new_qty > 0 then
        run_cost := round(((run_qty * run_cost) + (ln.qty * landed_rate)) / new_qty, 4);
      end if;
      run_qty := new_qty;

    elsif ln.vtype = 'sale' then
      update voucher_lines set cost_amount = round(ln.qty * run_cost, 2) where id = ln.line_id;
      run_qty := run_qty - ln.qty;

    elsif ln.vtype = 'return' then
      -- maal wapas godam mein, asal sale ke waqt ke per-unit cost par
      new_qty := run_qty + ln.qty;
      if new_qty > 0 and ln.qty > 0 then
        run_cost := round(((run_qty * run_cost) + ln.ret_cost) / new_qty, 4);
      end if;
      run_qty := new_qty;
    end if;

  end loop;

  -- System apna hisaab likh raha hai — permission check aur audit log
  -- se guzarne ki zaroorat nahi. Flag foran wapas band bhi kar dete hain,
  -- warna baqi poori transaction mein permission checks bypass ho jate.
  perform set_config('app.system_write', 'true', true);
  update items set avg_cost = round(run_cost, 4), stock_qty = run_qty where id = p_item_id;
  perform set_config('app.system_write', 'false', true);
end;
$function$;

-- ---------- Sab items ka cost dobara ginna + Period Lock snapshot ----------

create or replace function public.recompute_all_item_costs(lock_date date)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare it_id uuid;
begin
  delete from item_cost_snapshot where true;

  for it_id in select id from items loop
    perform recompute_item_cost(it_id);
  end loop;

  if lock_date is not null then
    insert into item_cost_snapshot (item_id, as_of_date, avg_cost, stock_qty)
      select id, lock_date, avg_cost, stock_qty from items;
  end if;
end;
$function$;

-- ============================================================
--  Costing triggers: Sale / Purchase
--
--  Bill ki koi line badle ya bill ka header badle to us item ka
--  avg_cost aur stock_qty dobara ginn liya jata hai.
--
--  RECURSION SE HIFAZAT: recompute_item_cost khud voucher_lines par
--  cost_amount likhta hai. Us likhai se yeh trigger dobara chalega —
--  is liye jab sirf cost_amount (ya koi aur cost par asar na daalne
--  wala field) badla ho to trigger foran wapas ho jata hai.
--  Cost par asar sirf teen cheezein daalti hain: item_id, qty, rate.
-- ============================================================

create or replace function public.trg_recompute_cost_on_line()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if TG_OP = 'DELETE' then
    if OLD.item_id is not null then perform recompute_item_cost(OLD.item_id); end if;
    return OLD;

  elsif TG_OP = 'UPDATE' then
    -- sirf cost_amount/amount/warehouse waghera badla → cost par asar nahi
    if NEW.item_id is not distinct from OLD.item_id
       and NEW.qty  is not distinct from OLD.qty
       and NEW.rate is not distinct from OLD.rate then
      return NEW;
    end if;
    if NEW.item_id is not null then perform recompute_item_cost(NEW.item_id); end if;
    if OLD.item_id is distinct from NEW.item_id and OLD.item_id is not null then
      perform recompute_item_cost(OLD.item_id);
    end if;
    return NEW;

  else
    if NEW.item_id is not null then perform recompute_item_cost(NEW.item_id); end if;
    return NEW;
  end if;
end;
$function$;

-- Bill ka header badalne par: tareekh (tarteeb badalti hai), vtype,
-- soft delete/restore (bill hisaab mein shamil hoga ya nahi), aur
-- loading/cartage/cutting charges (landed cost badalta hai).
create or replace function public.trg_recompute_cost_on_voucher()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare it uuid;
begin
  if NEW.vdate       is not distinct from OLD.vdate
     and NEW.vtype       is not distinct from OLD.vtype
     and NEW.deleted_at  is not distinct from OLD.deleted_at
     and NEW.loading_on  is not distinct from OLD.loading_on
     and NEW.loading_amt is not distinct from OLD.loading_amt
     and NEW.cartage_on  is not distinct from OLD.cartage_on
     and NEW.cartage_amt is not distinct from OLD.cartage_amt
     and NEW.cutting_on  is not distinct from OLD.cutting_on
     and NEW.cutting_amt is not distinct from OLD.cutting_amt then
    return NEW;
  end if;

  for it in
    select distinct item_id from voucher_lines
     where voucher_id = NEW.id and item_id is not null
  loop
    perform recompute_item_cost(it);
  end loop;

  return NEW;
end;
$function$;

-- ============================================================
--  Sales Return: qty validation aur cost stamping
-- ============================================================

-- Kitna maal is sale-line ka abhi bhi return ho sakta hai
create or replace function public.returnable_qty(p_sale_line_id uuid)
returns numeric
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  sold_qty     numeric;
  returned_qty numeric;
begin
  select qty into sold_qty from voucher_lines where id = p_sale_line_id;
  if sold_qty is null then return 0; end if;

  select coalesce(sum(srl.qty), 0) into returned_qty
    from sales_return_lines srl
    join sales_returns sr on sr.id = srl.return_id
   where srl.sale_line_id = p_sale_line_id
     and sr.deleted_at is null;

  return sold_qty - returned_qty;
end;
$function$;

-- Over-return rokna
create or replace function public.trg_check_returnable_qty()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare avail numeric;
begin
  if NEW.sale_line_id is null then
    raise exception 'Return line ko original sale-line se juda hona zaroori hai';
  end if;

  avail := returnable_qty(NEW.sale_line_id);

  -- agar ye line pehle se maujood hai (edit ho rahi hai) to uski apni purani qty wapas add kar do
  if TG_OP = 'UPDATE' then avail := avail + OLD.qty; end if;

  if NEW.qty > avail then
    raise exception 'Sirf % tak hi return ho sakta hai (baaki pehle hi wapas ho chuka)', avail;
  end if;

  return NEW;
end;
$function$;

-- Return line par asal sale ka per-unit cost chapak dena
create or replace function public.stamp_return_line_cost()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare per_unit numeric;
begin
  select case when qty > 0 then cost_amount / qty else 0 end into per_unit
    from voucher_lines where id = NEW.sale_line_id;

  NEW.cost_amount := round(coalesce(per_unit, 0) * NEW.qty, 2);
  return NEW;
end;
$function$;

-- Return ka header badalne par (tareekh ya soft delete/restore) us
-- return ke tamam items ka cost dobara ginna
create or replace function public.trg_recompute_cost_on_return()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare it uuid;
begin
  if NEW.rdate is not distinct from OLD.rdate
     and NEW.deleted_at is not distinct from OLD.deleted_at then
    return NEW;
  end if;

  for it in
    select distinct item_id from sales_return_lines
     where return_id = NEW.id and item_id is not null
  loop
    perform recompute_item_cost(it);
  end loop;

  return NEW;
end;
$function$;

-- Return line badalne par us item ka cost dobara ginna
create or replace function public.trg_recompute_cost_on_return_line()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if TG_OP = 'DELETE' then
    perform recompute_item_cost(OLD.item_id);
    return OLD;

  elsif TG_OP = 'UPDATE' then
    -- sirf cost_amount badla ho to dobara mat gino — warna infinite recursion
    if NEW.item_id     is not distinct from OLD.item_id
       and NEW.qty     is not distinct from OLD.qty
       and NEW.cost_amount is not distinct from OLD.cost_amount then
      return NEW;
    end if;
    perform recompute_item_cost(NEW.item_id);
    if OLD.item_id is distinct from NEW.item_id then
      perform recompute_item_cost(OLD.item_id);
    end if;
    return NEW;

  else
    perform recompute_item_cost(NEW.item_id);
    return NEW;
  end if;
end;
$function$;
