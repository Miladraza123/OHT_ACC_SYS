-- ============================================================
--  22 — Costing engine mein Conversion ka integration
--
--  YEH FILE 06_costing_engine.sql WALE recompute_item_cost() KO BADALTI HAI.
--  Naya engine nahi bana — usi engine ki timeline mein do naye
--  waqiat add kiye gaye hain:
--
--    conv_out  → source item se maal nikla.  Bilkul 'sale' ki tarah
--                chalta hai: us waqt ke weighted average par
--                cost_amount stamp hota hai aur stock ghatta hai.
--
--    conv_in   → output item mein maal aaya. Bilkul 'purchase' ki tarah
--                chalta hai, magar rate market rate nahi — source se
--                transfer hui cost hai (cost_amount / qty).
--
--  Yehi pattern Sales Return mein pehle se chal raha hai
--  (stamp_return_line_cost → ret_cost), is liye engine ka
--  tareeqa nahi badla, sirf usi tareeqe par do naye waqiat aaye.
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
             0::numeric, 0::numeric, 0::numeric,
             false, false, false,
             srl.cost_amount as ret_cost
        from sales_return_lines srl
        join sales_returns sr on sr.id = srl.return_id
       where srl.item_id = p_item_id
         and sr.deleted_at is null
         and (cutoff is null or sr.rdate >= cutoff)
    )
    union all
    (
      -- Conversion: source item se maal nikla
      select ci.id as line_id, ci.qty, 0::numeric as rate, 'conv_out'::text as vtype,
             sc.cdate as vdate, sc.id as voucher_id,
             0::numeric, 0::numeric, 0::numeric,
             false, false, false,
             null::numeric as ret_cost
        from stock_conversion_inputs ci
        join stock_conversions sc on sc.id = ci.conversion_id
       where ci.item_id = p_item_id
         and sc.deleted_at is null and sc.status <> 'cancelled'
         and (cutoff is null or sc.cdate >= cutoff)
    )
    union all
    (
      -- Conversion: output item mein maal aaya (transfer hui cost par)
      select co.id as line_id, co.qty,
             (case when co.qty > 0 then co.cost_amount / co.qty else 0 end) as rate,
             'conv_in'::text as vtype,
             sc.cdate as vdate, sc.id as voucher_id,
             0::numeric, 0::numeric, 0::numeric,
             false, false, false,
             null::numeric as ret_cost
        from stock_conversion_outputs co
        join stock_conversions sc on sc.id = co.conversion_id
       where co.item_id = p_item_id
         and sc.deleted_at is null and sc.status <> 'cancelled'
         and (cutoff is null or sc.cdate >= cutoff)
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
      new_qty := run_qty + ln.qty;
      if new_qty > 0 and ln.qty > 0 then
        run_cost := round(((run_qty * run_cost) + ln.ret_cost) / new_qty, 4);
      end if;
      run_qty := new_qty;

    elsif ln.vtype = 'conv_out' then
      -- sale ki tarah: us waqt ki cost bahar nikalti hai
      update stock_conversion_inputs set cost_amount = round(ln.qty * run_cost, 2)
       where id = ln.line_id;
      run_qty := run_qty - ln.qty;

    elsif ln.vtype = 'conv_in' then
      -- purchase ki tarah: source se aayi hui cost andar aati hai
      new_qty := run_qty + ln.qty;
      if new_qty > 0 then
        run_cost := round(((run_qty * run_cost) + (ln.qty * ln.rate)) / new_qty, 4);
      end if;
      run_qty := new_qty;
    end if;

  end loop;

  perform set_config('app.system_write', 'true', true);
  update items set avg_cost = round(run_cost, 4), stock_qty = run_qty where id = p_item_id;
  perform set_config('app.system_write', 'false', true);
end;
$function$;

-- ============================================================
--  Cost allocation: input ki cost output par baantna
--
--  Default usool (jo aap ne manzoor kiya): output weight ke tanasub se.
--  Wastage ki surat mein output ka kul weight input se kam hota hai,
--  is liye per-KG cost khud-ba-khud barh jati hai — yehi durust hai,
--  kyunki poori cost bache hue maal par aati hai.
--
--  Rounding ka bacha hua paisa aakhri line par daal diya jata hai,
--  taake transfer hui kul cost bilkul barabar rahe.
-- ============================================================

create or replace function public.allocate_conversion_cost(p_conversion_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  sc          record;
  total_cost  numeric;
  total_qty   numeric;
  running     numeric := 0;
  last_id     uuid;
  o           record;
  share       numeric;
begin
  select * into sc from stock_conversions where id = p_conversion_id;
  if not found then return; end if;

  select coalesce(sum(cost_amount), 0) into total_cost
    from stock_conversion_inputs where conversion_id = p_conversion_id;
  total_cost := total_cost + coalesce(sc.conversion_cost, 0);

  select coalesce(sum(qty), 0) into total_qty
    from stock_conversion_outputs where conversion_id = p_conversion_id;

  if total_qty <= 0 then return; end if;

  select id into last_id from stock_conversion_outputs
   where conversion_id = p_conversion_id order by line_no desc, id desc limit 1;

  perform set_config('app.system_write', 'true', true);

  for o in select id, qty from stock_conversion_outputs
            where conversion_id = p_conversion_id and id <> last_id
            order by line_no, id
  loop
    share := round(total_cost * o.qty / total_qty, 2);
    running := running + share;
    update stock_conversion_outputs set cost_amount = share where id = o.id;
  end loop;

  -- aakhri line: bacha hua sab kuch, taake jama bilkul barabar ho
  update stock_conversion_outputs set cost_amount = round(total_cost - running, 2)
   where id = last_id;

  perform set_config('app.system_write', 'false', true);
end;
$function$;

-- ============================================================
--  Poore conversion ka hisaab — theek tarteeb mein
--
--  Tarteeb ahem hai: pehle source ka cost pata chale, phir wo cost
--  output par baante, phir output items ka average dobara gine.
--  Agar output aage kisi doosre conversion ka source hai to yeh
--  silsila aage bhi chalta hai (5 darje tak — chakkar se bachne ke liye).
-- ============================================================

create or replace function public.recalc_conversion(p_conversion_id uuid, p_depth integer default 0)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  it   uuid;
  nxt  uuid;
begin
  if p_depth > 5 then return; end if;   -- chakkar se hifazat

  -- 1. source items ka hisaab — is se input lines par cost_amount lag jata hai
  for it in select distinct item_id from stock_conversion_inputs where conversion_id = p_conversion_id
  loop
    perform recompute_item_cost(it);
  end loop;

  -- 2. wo cost output lines par baanto
  perform allocate_conversion_cost(p_conversion_id);

  -- 3. output items ka hisaab — ab inhein nayi cost mil chuki hai
  for it in select distinct item_id from stock_conversion_outputs where conversion_id = p_conversion_id
  loop
    perform recompute_item_cost(it);

    -- 4. agar yeh output kisi aur conversion ka source hai, wo bhi theek karo
    for nxt in
      select distinct ci.conversion_id
        from stock_conversion_inputs ci
        join stock_conversions s2 on s2.id = ci.conversion_id
       where ci.item_id = it
         and ci.conversion_id <> p_conversion_id
         and s2.deleted_at is null and s2.status <> 'cancelled'
    loop
      perform recalc_conversion(nxt, p_depth + 1);
    end loop;
  end loop;

  -- 5. jin own coils se maal nikla, un ka balance bhi theek karo
  for it in select distinct coil_id from stock_conversion_inputs
             where conversion_id = p_conversion_id and coil_id is not null
  loop
    perform recalc_coil_balances(it);
  end loop;
end;
$function$;

-- ============================================================
--  Sab items ka cost dobara ginna — conversions samet
--
--  Conversion mein output ka cost source par munhasir hai, is liye
--  ek chakkar kaafi nahi. Teen chakkar chalate hain: har chakkar mein
--  pehle sab items, phir sab conversions ki allocation. Teen darje tak
--  ki conversion chains (coil → strip → sheet) is se poori ho jati hain.
-- ============================================================

create or replace function public.recompute_all_item_costs(lock_date date)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  it_id uuid;
  cv_id uuid;
  pass  integer;
begin
  delete from item_cost_snapshot where true;

  for pass in 1..3 loop
    for it_id in select id from items loop
      perform recompute_item_cost(it_id);
    end loop;

    for cv_id in select id from stock_conversions
                  where deleted_at is null and status <> 'cancelled' order by cdate, id
    loop
      perform allocate_conversion_cost(cv_id);
    end loop;
  end loop;

  -- aakhri chakkar: allocation ke baad averages dobara
  for it_id in select id from items loop
    perform recompute_item_cost(it_id);
  end loop;

  if lock_date is not null then
    insert into item_cost_snapshot (item_id, as_of_date, avg_cost, stock_qty)
      select id, lock_date, avg_cost, stock_qty from items;
  end if;
end;
$function$;
