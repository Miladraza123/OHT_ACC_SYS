-- ============================================================
--  35 — Accounting engine ki durustiyan (8 October 2026)
--
--  Deep test report ke yeh masle is file mein theek hote hain:
--
--    H2   Trial Balance sales return ko nahi ginta tha
--    M10  Ledger row mein ek kharab party id poora Trial Balance tor deti thi
--    H3   Period lock: tareekh aage kar ke band bill badla ja sakta tha
--    H4   Server browser ke bheje hue totals par aankh band kar ke yaqeen karta tha
--    H5   Manfi stock ke baad average cost bigar jati thi
--    H6   Stock Adjustment stock aur cost par koi asar nahi daalti thi
--    L    Delete hui sale par return ban sakta tha
--    N1   (naya mila) Period lock ka item_cost_snapshot lock-date ka nahi,
--         AAJ ka stock likhta tha — is liye lock ke baad ka har bill
--         agli costing mein do dafa ginta tha (stock 60 ki jagah 20).
--
--  01..34 ke BAAD chalayein. Har cheez "create or replace" / "drop trigger
--  if exists" hai — dobara chalane se koi nuqsan nahi. Fresh install aur
--  live dono par chalti hai.
--
--  ─── PURANA DATA: is file ke aakhir mein EK DAFA costing dobara chalti hai ───
--
--  Naya costing formula (H5/H6/N1) purane bills par bhi lagna chahiye, is
--  liye file ke aakhir mein (HISSA 8) sab items ka avg_cost/stock_qty aur har
--  sale line ka cost_amount (COGS) dobara gina jata hai, aur period lock lagi
--  ho to item_cost_snapshot sahi (lock-date wala) dobara banta hai.
--  Yeh sirf costing ke columns badalta hai: items.avg_cost, items.stock_qty,
--  voucher_lines.cost_amount, stock_conversion_*.cost_amount, item_cost_snapshot.
--  Jin items ka stock kabhi manfi nahi hua, aur jin par stock adjustment nahi,
--  un ke number bilkul wahi rehte hain.
--
--  Bills ke header totals (sub_total/grand_total) purane data mein NAHI
--  badle jate — sirf naye/badle hue bills par server ka hisaab lagta hai.
--  Aakhir mein NOTICE batata hai kitne purane bills ke totals lines se mel
--  nahi khate, taake owner khud dekh le.
--
--  ─── LIVE PAR CHALANE SE PEHLE ───
--  * Period lock lagi ho to bhi chalegi; locked bills ka COGS bhi naye
--    formula se dobara banta hai (sirf un items ka jin ka stock manfi gaya tha).
--  * Kuch hazar items ke liye Supabase SQL editor mein aaram se chalti hai
--    (statement_timeout neeche band kiya gaya hai).
-- ============================================================

set statement_timeout = 0;


-- ============================================================
--  HISSA 1 — Trial Balance (H2 + M10)
--
--  MASLA H2: Sale 1000, return 300 → Party Ledger 700 dikhata tha magar
--  Trial Balance 1000. Har us customer ka balance zyada tha jis ne kabhi
--  maal wapas kiya.
--  HAL: Masters ke Party Ledger (accountBalanceAsOf) wala hi formula —
--  har na-delete hui sales return ka grand_total us ki party ke balance se
--  minus. Ab TB = Party Ledger.
--
--  MASLA M10: daily ledger ki row[6]/row[7] seedha ::uuid cast hoti thin.
--  Import se ek bhi ghalat value aa jaye to poora TB sab ke liye error deta.
--  HAL: sirf sahi UUID shakal wali value cast hoti hai, baqi chhor di jati hai.
-- ============================================================

create or replace function public.trial_balance()
returns table(party_id uuid, party_name text, balance numeric, side text)
language plpgsql
stable
set search_path = public
as $function$
begin
  return query
  with opening as (
    select p.id as pid,
           (case when p.opening_side = 'dr' then 1 else -1 end) * clean_num(p.opening) as amt
      from parties p
     where p.deleted_at is null
  ),
  bills as (
    select v.party_id as pid,
           sum(
             (case when v.vtype = 'sale' then  1 else -1 end) * clean_num(v.grand_total)
           + (case when v.vtype = 'sale' then -1 else  1 end) * clean_num(v.paid)
           ) as amt
      from vouchers v
     where v.deleted_at is null and v.party_id is not null
     group by v.party_id
  ),
  services as (   -- Service Invoice: sale ki tarah — receivable barhta hai
    select si.party_id as pid,
           sum(clean_num(si.grand_total) - clean_num(si.paid)) as amt
      from service_invoices si
     where si.deleted_at is null and si.status <> 'cancelled' and si.party_id is not null
     group by si.party_id
  ),
  sale_returns as (   -- Sales Return: receivable ghatta hai (Party Ledger jaisa)
    select sr.party_id as pid,
           -1 * sum(clean_num(sr.grand_total)) as amt
      from sales_returns sr
     where sr.deleted_at is null and sr.party_id is not null
     group by sr.party_id
  ),
  ledger_rows as (    -- sirf sahi UUID wali party ids — ghalat value poora TB na tore
    select (case when row_data ->> 6 ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 then (row_data ->> 6)::uuid end) as credit_pid,
           (case when row_data ->> 7 ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 then (row_data ->> 7)::uuid end) as debit_pid,
           row_data
      from sheets s, jsonb_array_elements(s.rows) as row_data
     where s.deleted_at is null and jsonb_typeof(row_data) = 'array'
  ),
  cash_credit as (   -- row[6] = credit party (paisa aaya) → balance ghatta hai
    select credit_pid as pid, sum(clean_num(row_data ->> 2)) * -1 as amt
      from ledger_rows where credit_pid is not null
     group by credit_pid
  ),
  cash_debit as (    -- row[7] = debit party (paisa gaya) → balance barhta hai
    select debit_pid as pid, sum(clean_num(row_data ->> 0)) as amt
      from ledger_rows where debit_pid is not null
     group by debit_pid
  ),
  combined as (
    select pid, amt from opening
    union all select pid, amt from bills
    union all select pid, amt from services
    union all select pid, amt from sale_returns
    union all select pid, amt from cash_credit
    union all select pid, amt from cash_debit
  ),
  totals as (
    select pid, round(sum(amt), 2) as net
      from combined
     where pid is not null
     group by pid
  )
  select p.id, p.name, abs(t.net), (case when t.net >= 0 then 'dr' else 'cr' end)
    from totals t
    join parties p on p.id = t.pid
   where p.deleted_at is null and t.net <> 0
   order by p.name;
end;
$function$;


-- ============================================================
--  HISSA 2 — Period Lock (H3)
--
--  MASLA: trigger sirf NAYI tareekh dekhta tha. Band (locked) bill ki
--  tareekh aage kar ke usi save mein raqam 500 → 99,999 ho jati thi.
--  Daily ledger sheet ka bhi yehi haal tha.
--  HAL: UPDATE par PURANI ya NAYI — koi bhi tareekh lock ke andar ho to
--  rok. DELETE par purani tareekh. Soft-delete/restore ki ijazat pehle ki
--  tarah baqi hai.
--
--  Sirf do lock triggers the (vouchers, sheets). Lekin band bill ko us
--  ki LINES badal kar bhi badla ja sakta tha, aur Sales Return / Stock
--  Adjustment par lock tha hi nahi — jabke yeh dono party balance aur
--  stock/cost ko badalte hain. Is liye yahi usool in par bhi:
--    voucher_lines, sales_returns, sales_return_lines, stock_adjustments.
--  (Costing ka apna cost_amount likhna lock se nahi rukta.)
-- ============================================================

create or replace function public.check_period_lock_vouchers()
returns trigger
language plpgsql
set search_path = public
as $function$
declare
  lock_date  date;
  check_date date;
begin
  select locked_before into lock_date from period_lock where id = 1;
  if lock_date is null then
    return coalesce(NEW, OLD);   -- koi lock set hi nahi — sab normal
  end if;

  if TG_OP = 'UPDATE' then
    -- purani YA nayi tareekh — jo bhi lock ke andar ho
    check_date := least(OLD.vdate, NEW.vdate);
    if check_date < lock_date then
      if to_jsonb(NEW) - 'deleted_at' - 'updated_at' = to_jsonb(OLD) - 'deleted_at' - 'updated_at' then
        return NEW;   -- sirf soft-delete/restore tha, ijazat hai
      end if;
      raise exception 'Yeh bill % se pehle ka hai, jo band ho chuka hai (locked before %). Change nahi ho sakta.',
        check_date, lock_date;
    end if;
    return NEW;
  end if;

  check_date := case when TG_OP = 'DELETE' then OLD.vdate else NEW.vdate end;
  if check_date < lock_date then
    raise exception 'Yeh tareekh (%) band ho chuki hai (locked before %). Naya bill nahi ban sakta ya permanently delete nahi ho sakta.',
      check_date, lock_date;
  end if;

  return coalesce(NEW, OLD);
end;
$function$;

create or replace function public.check_period_lock_sheets()
returns trigger
language plpgsql
set search_path = public
as $function$
declare
  lock_date  date;
  check_date date;
begin
  select locked_before into lock_date from period_lock where id = 1;
  if lock_date is null then
    return coalesce(NEW, OLD);
  end if;

  if TG_OP = 'UPDATE' then
    check_date := least(OLD.sheet_date, NEW.sheet_date);
    if check_date < lock_date then
      if to_jsonb(NEW) - 'deleted_at' - 'version' = to_jsonb(OLD) - 'deleted_at' - 'version' then
        return NEW;
      end if;
      raise exception 'Yeh din (%) band ho chuka hai (locked before %). Change nahi ho sakta.',
        check_date, lock_date;
    end if;
    return NEW;
  end if;

  check_date := case when TG_OP = 'DELETE' then OLD.sheet_date else NEW.sheet_date end;
  if check_date < lock_date then
    raise exception 'Yeh tareekh (%) band ho chuki hai (locked before %).',
      check_date, lock_date;
  end if;

  return coalesce(NEW, OLD);
end;
$function$;

-- Sales Return header — bill jaisa hi usool (rdate)
create or replace function public.check_period_lock_sales_returns()
returns trigger
language plpgsql
set search_path = public
as $function$
declare
  lock_date  date;
  check_date date;
begin
  select locked_before into lock_date from period_lock where id = 1;
  if lock_date is null then
    return coalesce(NEW, OLD);
  end if;

  if TG_OP = 'UPDATE' then
    check_date := least(OLD.rdate, NEW.rdate);
    if check_date < lock_date then
      if to_jsonb(NEW) - 'deleted_at' - 'updated_at' = to_jsonb(OLD) - 'deleted_at' - 'updated_at' then
        return NEW;   -- sirf soft-delete/restore
      end if;
      raise exception 'Yeh return % se pehle ka hai, jo band ho chuka hai (locked before %). Change nahi ho sakta.',
        check_date, lock_date;
    end if;
    return NEW;
  end if;

  check_date := case when TG_OP = 'DELETE' then OLD.rdate else NEW.rdate end;
  if check_date < lock_date then
    raise exception 'Yeh tareekh (%) band ho chuki hai (locked before %). Return nahi ban sakta ya permanently delete nahi ho sakta.',
      check_date, lock_date;
  end if;

  return coalesce(NEW, OLD);
end;
$function$;

-- Bill / return ki LINES — parent ki tareekh dekhi jati hai.
-- Parent hi delete ho raha ho (cascade) to wo nazar nahi aata → rokna nahi;
-- band parent ka hard delete header ka trigger pehle hi rok deta hai.
create or replace function public.check_period_lock_lines()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  lock_date date;
  d_old     date;
  d_new     date;
begin
  select locked_before into lock_date from period_lock where id = 1;
  if lock_date is null then
    return coalesce(NEW, OLD);
  end if;

  if TG_TABLE_NAME = 'voucher_lines' then
    if TG_OP <> 'INSERT' then select vdate into d_old from vouchers where id = OLD.voucher_id; end if;
    if TG_OP <> 'DELETE' then select vdate into d_new from vouchers where id = NEW.voucher_id; end if;
  else  -- sales_return_lines
    if TG_OP <> 'INSERT' then select rdate into d_old from sales_returns where id = OLD.return_id; end if;
    if TG_OP <> 'DELETE' then select rdate into d_new from sales_returns where id = NEW.return_id; end if;
  end if;

  if d_old < lock_date or d_new < lock_date then
    raise exception 'Yeh bill/return % se pehle ka hai, jo band ho chuka hai (locked before %). Is ki lines change nahi ho saktin.',
      least(d_old, d_new), lock_date;
  end if;

  return coalesce(NEW, OLD);
end;
$function$;

-- Stock Adjustment — ab costing mein ginti hai (H6), is liye lock bhi
create or replace function public.check_period_lock_adjustments()
returns trigger
language plpgsql
set search_path = public
as $function$
declare
  lock_date date;
  d_old     date;
  d_new     date;
begin
  select locked_before into lock_date from period_lock where id = 1;
  if lock_date is null then
    return coalesce(NEW, OLD);
  end if;

  if TG_OP <> 'INSERT' then d_old := OLD.adj_date; end if;
  if TG_OP <> 'DELETE' then d_new := NEW.adj_date; end if;

  if d_old < lock_date or d_new < lock_date then
    raise exception 'Yeh tareekh (%) band ho chuki hai (locked before %). Stock adjustment change nahi ho sakta.',
      least(d_old, d_new), lock_date;
  end if;

  return coalesce(NEW, OLD);
end;
$function$;

drop trigger if exists trg_period_lock_sales_returns on sales_returns;
create trigger trg_period_lock_sales_returns before insert or update or delete on sales_returns
  for each row execute function check_period_lock_sales_returns();

drop trigger if exists trg_period_lock_voucher_lines     on voucher_lines;
drop trigger if exists trg_period_lock_voucher_lines_upd on voucher_lines;
create trigger trg_period_lock_voucher_lines before insert or delete on voucher_lines
  for each row execute function check_period_lock_lines();
-- costing (recompute_item_cost) sirf cost_amount likhta hai — wo lock se na ruke
create trigger trg_period_lock_voucher_lines_upd before update on voucher_lines
  for each row
  when ((to_jsonb(old) - 'cost_amount') is distinct from (to_jsonb(new) - 'cost_amount'))
  execute function check_period_lock_lines();

drop trigger if exists trg_period_lock_return_lines     on sales_return_lines;
drop trigger if exists trg_period_lock_return_lines_upd on sales_return_lines;
create trigger trg_period_lock_return_lines before insert or delete on sales_return_lines
  for each row execute function check_period_lock_lines();
create trigger trg_period_lock_return_lines_upd before update on sales_return_lines
  for each row
  when ((to_jsonb(old) - 'cost_amount') is distinct from (to_jsonb(new) - 'cost_amount'))
  execute function check_period_lock_lines();

drop trigger if exists trg_period_lock_adjustments on stock_adjustments;
create trigger trg_period_lock_adjustments before insert or update or delete on stock_adjustments
  for each row execute function check_period_lock_adjustments();


-- ============================================================
--  HISSA 3 — Totals server par (H4)
--
--  MASLA: browser jo sub_total / tax_total / grand_total bhejta, server
--  wohi likh deta. Ek line 10 ki, grand_total 999,999 — qabool. Discount
--  manfi, paid manfi, tax manfi — sab qabool. Yeh number seedha Trial
--  Balance aur party ledger mein jate hain.
--
--  HAL: header ke totals hamesha LINES se server par bante hain — bilkul
--  client1-billing.html ke lineAmount() / totals() / returnTotals() wala
--  formula, wahi gol karne ka tareeqa (JS Math.round(x*100)/100, float):
--    line amount = round2(coalesce(sale_qty, qty) × rate)
--    sub   = round2(Σ amount)
--    tax   = tax_on ? round2(Σ round2(amount × tax_pct / 100)) : 0
--    disc  = round2(discount)
--    extra = round2(loading + cartage + cutting, sirf jo "on" hon)
--    grand = round2(sub − disc + tax + extra)
--  Sales return: grand = subtotal = round2(Σ round2(qty × rate)), tax nahi.
--  Purchase order mein extra charges ke columns hi nahi — 0.
--  Client ki value alag ho to server wali jeet-ti hai (chup chaap).
--  paid jaisa likha wohi rehta hai — sirf manfi nahi ho sakta.
--
--  Kaise: (1) line likhte waqt amount server banata hai, (2) lines badalne
--  ke baad header ke totals dobara (insert/delete par ek statement mein
--  ek dafa), (3) header insert/update par bhi lines se dobara. Header ka
--  sirf soft-delete/restore totals ko haath nahi lagata (band period ke
--  purane bills soft-delete ho sakte rahein).
--  smart_merge_update totals ko pehle hi nazar-andaz karta hai, is liye
--  conflict check par koi asar nahi. Costing ka cost_amount likhna in
--  triggers ko nahi jagata (WHEN), is liye recursion nahi.
-- ============================================================

-- JS ka round2: Math.round(x * 100) / 100 — float mein, taake 1.005 jaise
-- number par bhi server aur screen ek hi paisa dikhayein
create or replace function public.js_round2(v double precision)
returns numeric
language sql
immutable
set search_path = public
as $function$
  select round((case when x - floor(x) >= 0.5 then floor(x) + 1 else floor(x) end)::numeric / 100, 2)
    from (select coalesce(v, 0) * 100 as x) s;
$function$;

-- lineAmount(): sale_qty khali ho (purani line) to qty
create or replace function public.doc_line_amount(p_qty numeric, p_sale_qty numeric, p_rate numeric)
returns numeric
language sql
immutable
set search_path = public
as $function$
  select js_round2(coalesce(p_sale_qty, p_qty, 0)::float8 * coalesce(p_rate, 0)::float8);
$function$;

-- Ek document ke totals us ki lines se. p_head = header row (to_jsonb).
create or replace function public.doc_totals(
  p_table text, p_id uuid, p_head jsonb,
  out o_sub numeric, out o_tax numeric, out o_grand numeric
)
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  tax_on boolean := coalesce((p_head ->> 'tax_on')::boolean, false);
  disc   numeric;
  extras numeric;
begin
  if p_table = 'vouchers' then
    select coalesce(sum(a), 0), coalesce(sum(js_round2(a::float8 * tax_pct::float8 / 100)), 0)
      into o_sub, o_tax
      from (select doc_line_amount(qty, sale_qty, rate) as a, coalesce(tax_pct, 0) as tax_pct
              from voucher_lines where voucher_id = p_id) x;
  elsif p_table = 'sales_returns' then
    select coalesce(sum(doc_line_amount(qty, sale_qty, rate)), 0), 0
      into o_sub, o_tax
      from sales_return_lines where return_id = p_id;
    o_sub := round(o_sub, 2);
    o_tax := 0;
    o_grand := o_sub;                       -- returnTotals(): sirf items, tax nahi
    return;
  elsif p_table = 'quotations' then
    -- sale_qty column ho ya na ho (H1 ka fix use add kar sakta hai) — dono surat chale
    select coalesce(sum(a), 0), coalesce(sum(js_round2(a::float8 * tax_pct::float8 / 100)), 0)
      into o_sub, o_tax
      from (select doc_line_amount(l.qty, (to_jsonb(l) ->> 'sale_qty')::numeric, l.rate) as a,
                   coalesce(l.tax_pct, 0) as tax_pct
              from quotation_lines l where l.quotation_id = p_id) x;
  elsif p_table = 'purchase_orders' then
    select coalesce(sum(a), 0), coalesce(sum(js_round2(a::float8 * tax_pct::float8 / 100)), 0)
      into o_sub, o_tax
      from (select doc_line_amount(l.qty, (to_jsonb(l) ->> 'sale_qty')::numeric, l.rate) as a,
                   coalesce(l.tax_pct, 0) as tax_pct
              from po_lines l where l.po_id = p_id) x;
  else
    raise exception 'doc_totals: % ke liye nahi', p_table;
  end if;

  o_sub := round(o_sub, 2);
  o_tax := case when tax_on then round(o_tax, 2) else 0 end;
  disc  := js_round2(coalesce((p_head ->> 'discount')::numeric, 0)::float8);
  extras := js_round2(
      (case when coalesce((p_head ->> 'loading_on')::boolean, false)
            then coalesce((p_head ->> 'loading_amt')::numeric, 0) else 0 end)::float8
    + (case when coalesce((p_head ->> 'cartage_on')::boolean, false)
            then coalesce((p_head ->> 'cartage_amt')::numeric, 0) else 0 end)::float8
    + (case when coalesce((p_head ->> 'cutting_on')::boolean, false)
            then coalesce((p_head ->> 'cutting_amt')::numeric, 0) else 0 end)::float8);
  o_grand := js_round2(((o_sub::float8 - disc::float8) + o_tax::float8) + extras::float8);
end;
$function$;

-- Kuch documents ke header totals lines se dobara likhna (sirf jahan farq ho).
-- System ka apna likhna hai — permission check / audit log se nahi guzarta,
-- magar period lock se guzarta hai.
create or replace function public.recalc_doc_totals(p_table text, p_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  prev text := current_setting('app.system_write', true);
begin
  if p_ids is null or cardinality(p_ids) = 0 then return; end if;
  perform set_config('app.system_write', 'true', true);

  if p_table = 'vouchers' then
    update vouchers v set sub_total = t.o_sub, tax_total = t.o_tax, grand_total = t.o_grand
      from vouchers h cross join lateral doc_totals('vouchers', h.id, to_jsonb(h)) t
     where h.id = any(p_ids) and v.id = h.id
       and (v.sub_total, v.tax_total, v.grand_total) is distinct from (t.o_sub, t.o_tax, t.o_grand);
  elsif p_table = 'sales_returns' then
    update sales_returns v set subtotal = t.o_sub, grand_total = t.o_grand
      from sales_returns h cross join lateral doc_totals('sales_returns', h.id, to_jsonb(h)) t
     where h.id = any(p_ids) and v.id = h.id
       and (v.subtotal, v.grand_total) is distinct from (t.o_sub, t.o_grand);
  elsif p_table = 'quotations' then
    update quotations v set subtotal = t.o_sub, tax_total = t.o_tax, grand_total = t.o_grand
      from quotations h cross join lateral doc_totals('quotations', h.id, to_jsonb(h)) t
     where h.id = any(p_ids) and v.id = h.id
       and (v.subtotal, v.tax_total, v.grand_total) is distinct from (t.o_sub, t.o_tax, t.o_grand);
  elsif p_table = 'purchase_orders' then
    update purchase_orders v set subtotal = t.o_sub, tax_total = t.o_tax, grand_total = t.o_grand
      from purchase_orders h cross join lateral doc_totals('purchase_orders', h.id, to_jsonb(h)) t
     where h.id = any(p_ids) and v.id = h.id
       and (v.subtotal, v.tax_total, v.grand_total) is distinct from (t.o_sub, t.o_tax, t.o_grand);
  end if;

  perform set_config('app.system_write', coalesce(nullif(prev, ''), 'false'), true);
exception when others then
  perform set_config('app.system_write', coalesce(nullif(prev, ''), 'false'), true);
  raise;
end;
$function$;

-- Header: validation + totals lines se (BEFORE INSERT/UPDATE)
create or replace function public.trg_doc_header_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  jn  jsonb := to_jsonb(NEW);
  jo  jsonb;
  t   record;
  ign text[] := array['deleted_at', 'updated_at', 'updated_by', 'version'];
begin
  if TG_OP = 'UPDATE' then jo := to_jsonb(OLD); end if;

  -- sirf nayi/badli hui value janchi jati hai — purane rows kisi aur edit par na atkein
  if jn ? 'discount' and (TG_OP = 'INSERT' or (jn -> 'discount') is distinct from (jo -> 'discount'))
     and coalesce((jn ->> 'discount')::numeric, 0) < 0 then
    raise exception 'Discount manfi (minus) nahi ho sakta';
  end if;
  if jn ? 'paid' and (TG_OP = 'INSERT' or (jn -> 'paid') is distinct from (jo -> 'paid'))
     and coalesce((jn ->> 'paid')::numeric, 0) < 0 then
    raise exception 'Paid amount manfi (minus) nahi ho sakta';
  end if;

  -- sirf soft-delete / restore — totals ko haath nahi lagate
  if TG_OP = 'UPDATE' and (jn - ign) = (jo - ign) then
    return NEW;
  end if;

  select * into t from doc_totals(TG_TABLE_NAME, NEW.id, jn);

  if TG_TABLE_NAME = 'vouchers' then
    NEW := jsonb_populate_record(NEW, jsonb_build_object(
             'sub_total', t.o_sub, 'tax_total', t.o_tax, 'grand_total', t.o_grand));
  elsif TG_TABLE_NAME = 'sales_returns' then
    NEW := jsonb_populate_record(NEW, jsonb_build_object(
             'subtotal', t.o_sub, 'grand_total', t.o_grand));
  else
    NEW := jsonb_populate_record(NEW, jsonb_build_object(
             'subtotal', t.o_sub, 'tax_total', t.o_tax, 'grand_total', t.o_grand));
  end if;
  return NEW;
end;
$function$;

-- Line: validation + amount server par (BEFORE INSERT/UPDATE)
create or replace function public.trg_doc_line_amount()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  jn  jsonb := to_jsonb(NEW);
  jo  jsonb;
begin
  if TG_OP = 'UPDATE' then jo := to_jsonb(OLD); end if;

  if (TG_OP = 'INSERT' or NEW.qty is distinct from OLD.qty) and coalesce(NEW.qty, 0) <= 0 then
    raise exception 'Quantity zero se zyada honi chahiye';
  end if;
  if jn ? 'tax_pct' and (TG_OP = 'INSERT' or (jn -> 'tax_pct') is distinct from (jo -> 'tax_pct'))
     and coalesce((jn ->> 'tax_pct')::numeric, 0) not between 0 and 100 then
    raise exception 'Tax %% 0 aur 100 ke darmiyan hona chahiye';
  end if;

  NEW.amount := doc_line_amount(NEW.qty, (jn ->> 'sale_qty')::numeric, NEW.rate);
  return NEW;
end;
$function$;

-- Lines insert/delete ke baad: is statement ke sab documents ek dafa (AFTER STATEMENT)
-- TG_ARGV[0] = header table, TG_ARGV[1] = fk column, transition table = "changed"
create or replace function public.trg_doc_lines_stmt()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare ids uuid[];
begin
  execute format('select array_agg(distinct %I) from changed where %I is not null', TG_ARGV[1], TG_ARGV[1])
    into ids;
  perform recalc_doc_totals(TG_ARGV[0], ids);
  return null;
end;
$function$;

-- Line update ke baad (sirf jab raqam par asar ho — WHEN): naya aur purana document
create or replace function public.trg_doc_lines_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  n_id uuid := (to_jsonb(NEW) ->> TG_ARGV[1])::uuid;
  o_id uuid := (to_jsonb(OLD) ->> TG_ARGV[1])::uuid;
begin
  perform recalc_doc_totals(TG_ARGV[0], array_remove(array[n_id, o_id], null));
  return null;
end;
$function$;

-- Headers. Naam "trg_calc_*" — alphabet mein period lock ("trg_period_*")
-- se PEHLE chalta hai, taake lock aakhri totals dekhe.
drop trigger if exists trg_calc_totals_vouchers on vouchers;
create trigger trg_calc_totals_vouchers before insert or update on vouchers
  for each row execute function trg_doc_header_totals();
drop trigger if exists trg_calc_totals_sales_returns on sales_returns;
create trigger trg_calc_totals_sales_returns before insert or update on sales_returns
  for each row execute function trg_doc_header_totals();
drop trigger if exists trg_calc_totals_quotations on quotations;
create trigger trg_calc_totals_quotations before insert or update on quotations
  for each row execute function trg_doc_header_totals();
drop trigger if exists trg_calc_totals_purchase_orders on purchase_orders;
create trigger trg_calc_totals_purchase_orders before insert or update on purchase_orders
  for each row execute function trg_doc_header_totals();

-- voucher_lines
drop trigger if exists trg_amount_voucher_lines     on voucher_lines;
drop trigger if exists trg_amount_voucher_lines_upd on voucher_lines;
drop trigger if exists trg_totals_voucher_lines_ins on voucher_lines;
drop trigger if exists trg_totals_voucher_lines_del on voucher_lines;
drop trigger if exists trg_totals_voucher_lines_upd on voucher_lines;
create trigger trg_amount_voucher_lines before insert on voucher_lines
  for each row execute function trg_doc_line_amount();
create trigger trg_amount_voucher_lines_upd before update on voucher_lines
  for each row
  when ((old.qty, old.sale_qty, old.rate, old.tax_pct, old.amount)
        is distinct from (new.qty, new.sale_qty, new.rate, new.tax_pct, new.amount))
  execute function trg_doc_line_amount();
create trigger trg_totals_voucher_lines_ins after insert on voucher_lines
  referencing new table as changed
  for each statement execute function trg_doc_lines_stmt('vouchers', 'voucher_id');
create trigger trg_totals_voucher_lines_del after delete on voucher_lines
  referencing old table as changed
  for each statement execute function trg_doc_lines_stmt('vouchers', 'voucher_id');
create trigger trg_totals_voucher_lines_upd after update on voucher_lines
  for each row
  when ((old.voucher_id, old.qty, old.sale_qty, old.rate, old.tax_pct, old.amount)
        is distinct from (new.voucher_id, new.qty, new.sale_qty, new.rate, new.tax_pct, new.amount))
  execute function trg_doc_lines_row('vouchers', 'voucher_id');

-- sales_return_lines
drop trigger if exists trg_amount_return_lines     on sales_return_lines;
drop trigger if exists trg_amount_return_lines_upd on sales_return_lines;
drop trigger if exists trg_totals_return_lines_ins on sales_return_lines;
drop trigger if exists trg_totals_return_lines_del on sales_return_lines;
drop trigger if exists trg_totals_return_lines_upd on sales_return_lines;
create trigger trg_amount_return_lines before insert on sales_return_lines
  for each row execute function trg_doc_line_amount();
create trigger trg_amount_return_lines_upd before update on sales_return_lines
  for each row
  when ((old.qty, old.sale_qty, old.rate, old.amount)
        is distinct from (new.qty, new.sale_qty, new.rate, new.amount))
  execute function trg_doc_line_amount();
create trigger trg_totals_return_lines_ins after insert on sales_return_lines
  referencing new table as changed
  for each statement execute function trg_doc_lines_stmt('sales_returns', 'return_id');
create trigger trg_totals_return_lines_del after delete on sales_return_lines
  referencing old table as changed
  for each statement execute function trg_doc_lines_stmt('sales_returns', 'return_id');
create trigger trg_totals_return_lines_upd after update on sales_return_lines
  for each row
  when ((old.return_id, old.qty, old.sale_qty, old.rate, old.amount)
        is distinct from (new.return_id, new.qty, new.sale_qty, new.rate, new.amount))
  execute function trg_doc_lines_row('sales_returns', 'return_id');

-- quotation_lines / po_lines (kam badalti hain — update par har dafa)
drop trigger if exists trg_amount_quotation_lines   on quotation_lines;
drop trigger if exists trg_totals_quotation_lines_ins on quotation_lines;
drop trigger if exists trg_totals_quotation_lines_del on quotation_lines;
drop trigger if exists trg_totals_quotation_lines_upd on quotation_lines;
create trigger trg_amount_quotation_lines before insert or update on quotation_lines
  for each row execute function trg_doc_line_amount();
create trigger trg_totals_quotation_lines_ins after insert on quotation_lines
  referencing new table as changed
  for each statement execute function trg_doc_lines_stmt('quotations', 'quotation_id');
create trigger trg_totals_quotation_lines_del after delete on quotation_lines
  referencing old table as changed
  for each statement execute function trg_doc_lines_stmt('quotations', 'quotation_id');
create trigger trg_totals_quotation_lines_upd after update on quotation_lines
  for each row execute function trg_doc_lines_row('quotations', 'quotation_id');

drop trigger if exists trg_amount_po_lines     on po_lines;
drop trigger if exists trg_totals_po_lines_ins on po_lines;
drop trigger if exists trg_totals_po_lines_del on po_lines;
drop trigger if exists trg_totals_po_lines_upd on po_lines;
create trigger trg_amount_po_lines before insert or update on po_lines
  for each row execute function trg_doc_line_amount();
create trigger trg_totals_po_lines_ins after insert on po_lines
  referencing new table as changed
  for each statement execute function trg_doc_lines_stmt('purchase_orders', 'po_id');
create trigger trg_totals_po_lines_del after delete on po_lines
  referencing old table as changed
  for each statement execute function trg_doc_lines_stmt('purchase_orders', 'po_id');
create trigger trg_totals_po_lines_upd after update on po_lines
  for each row execute function trg_doc_lines_row('purchase_orders', 'po_id');


-- ============================================================
--  HISSA 4 — Costing engine (H5 + H6 + N1)
--
--  MASLA H5: stock manfi ho (pehle sale, baad mein purchase — business
--  mein jaiz hai) to agli purchase ka average bigar jata tha:
--  (−79 × 0 + 100 × 300) / 21 = 1428.57. Phir har agla COGS ghalat.
--  HAL (standard perpetual average): purchase/return/conversion-in se
--  PEHLE stock ≤ 0 ho to naya average = isi maal ka rate. Kabhi ≤ 0 se
--  taqseem nahi. Manfi stock par sale us waqt ke average par. Manfi
--  stock ki ijazat pehle ki tarah hai — rokte nahi.
--
--  MASLA H6: stock_adjustments costing timeline mein tha hi nahi —
--  adjustment se stock_qty nahi badalta tha (trg_adjust_recompute bekar).
--  HAL: adjustment (+/−) ab timeline mein hai, us waqt ke average par —
--  is liye average nahi badalta, sirf stock.
--
--  Ek hi din ki entries pehle line ki random uuid se tarteeb pati thin,
--  is liye usi din ki sale aur purchase ka COGS kabhi kuch, kabhi kuch.
--  Ab usi din mein bill ke banne ka waqt (created_at), phir line_no.
--  (Sales return usi din ke bills ke baad.)
--
--  MASLA N1: Period lock lagne par item_cost_snapshot mein AAJ ka stock
--  likha jata tha, magar engine usay "lock-date tak ka stock" maan kar
--  lock ke baad ke bills dobara jorta tha → stock 60 ki jagah 20.
--  HAL: snapshot ab hamesha us ki as_of_date se PEHLE tak ka hisaab hai
--  (item_cost_snapshot par trigger) — jo bhi usay likhe.
-- ============================================================

-- Ek item ki poori timeline chalana. p_stop_before diya ho to us tareekh
-- se pehle tak (snapshot ke liye — tab snapshot se shuru nahi hota).
-- p_stamp = sale / conversion-input lines par cost_amount likhna.
create or replace function public.item_cost_walk(
  p_item_id uuid, p_stop_before date, p_stamp boolean,
  out o_qty numeric, out o_cost numeric
)
language plpgsql
security definer
set search_path = public
as $function$
declare
  it            record;
  snap          record;
  ln            record;
  cutoff        date;
  extra         numeric;
  voucher_total numeric;
  landed_rate   numeric;
  in_qty        numeric;
  in_value      numeric;
  out_cost      numeric;
begin
  o_qty := 0; o_cost := 0;
  select * into it from items where id = p_item_id;
  if not found then return; end if;

  cutoff := null;
  if p_stop_before is null then
    select locked_before into cutoff from period_lock where id = 1;
    select * into snap from item_cost_snapshot where item_id = p_item_id;
    if snap.item_id is not null and cutoff is not null and snap.as_of_date = cutoff then
      o_qty  := snap.stock_qty;
      o_cost := snap.avg_cost;
    else
      cutoff := null;
    end if;
  end if;
  if cutoff is null then
    o_qty  := coalesce(it.opening_qty, 0);
    o_cost := coalesce(it.opening_rate, 0);
  end if;

  for ln in
    (
      select vl.id as line_id, vl.qty, vl.rate, v.vtype, v.vdate, v.id as voucher_id,
             v.loading_amt, v.cartage_amt, v.cutting_amt,
             v.loading_on, v.cartage_on, v.cutting_on,
             null::numeric as ret_cost,
             v.created_at as seq_ts, vl.line_no as seq_no
        from voucher_lines vl
        join vouchers v on v.id = vl.voucher_id
       where vl.item_id = p_item_id
         and v.deleted_at is null
         and (cutoff is null or v.vdate >= cutoff)
         and (p_stop_before is null or v.vdate < p_stop_before)
    )
    union all
    (
      select srl.id, srl.qty, srl.rate, 'return'::text, sr.rdate, sr.id,
             0::numeric, 0::numeric, 0::numeric, false, false, false,
             srl.cost_amount,
             'infinity'::timestamptz, srl.line_no
        from sales_return_lines srl
        join sales_returns sr on sr.id = srl.return_id
       where srl.item_id = p_item_id
         and sr.deleted_at is null
         and (cutoff is null or sr.rdate >= cutoff)
         and (p_stop_before is null or sr.rdate < p_stop_before)
    )
    union all
    (
      -- Conversion: source item se maal nikla
      select ci.id, ci.qty, 0::numeric, 'conv_out'::text, sc.cdate, sc.id,
             0::numeric, 0::numeric, 0::numeric, false, false, false,
             null::numeric,
             sc.created_at, ci.line_no
        from stock_conversion_inputs ci
        join stock_conversions sc on sc.id = ci.conversion_id
       where ci.item_id = p_item_id
         and sc.deleted_at is null and sc.status <> 'cancelled'
         and (cutoff is null or sc.cdate >= cutoff)
         and (p_stop_before is null or sc.cdate < p_stop_before)
    )
    union all
    (
      -- Conversion: output item mein maal aaya (transfer hui cost par)
      select co.id, co.qty,
             (case when co.qty > 0 then co.cost_amount / co.qty else 0 end),
             'conv_in'::text, sc.cdate, sc.id,
             0::numeric, 0::numeric, 0::numeric, false, false, false,
             null::numeric,
             sc.created_at, co.line_no
        from stock_conversion_outputs co
        join stock_conversions sc on sc.id = co.conversion_id
       where co.item_id = p_item_id
         and sc.deleted_at is null and sc.status <> 'cancelled'
         and (cutoff is null or sc.cdate >= cutoff)
         and (p_stop_before is null or sc.cdate < p_stop_before)
    )
    union all
    (
      -- Stock Adjustment (H6): +/− qty, us waqt ke average par
      select sa.id, sa.qty, 0::numeric, 'adjust'::text, sa.adj_date, sa.id,
             0::numeric, 0::numeric, 0::numeric, false, false, false,
             null::numeric,
             sa.created_at, 0
        from stock_adjustments sa
       where sa.item_id = p_item_id
         and (cutoff is null or sa.adj_date >= cutoff)
         and (p_stop_before is null or sa.adj_date < p_stop_before)
    )
    order by vdate asc, seq_ts asc, seq_no asc, line_id asc
  loop
    in_qty := null;

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
      in_qty := ln.qty; in_value := ln.qty * landed_rate;

    elsif ln.vtype = 'return' then
      -- maal wapas, asal sale ke waqt ke per-unit cost par
      in_qty := ln.qty; in_value := coalesce(ln.ret_cost, 0);

    elsif ln.vtype = 'conv_in' then
      in_qty := ln.qty; in_value := ln.qty * ln.rate;

    elsif ln.vtype = 'sale' then
      if p_stamp then
        out_cost := round(ln.qty * o_cost, 2);
        update voucher_lines set cost_amount = out_cost
         where id = ln.line_id and cost_amount is distinct from out_cost;
      end if;
      o_qty := o_qty - ln.qty;

    elsif ln.vtype = 'conv_out' then
      if p_stamp then
        out_cost := round(ln.qty * o_cost, 2);
        update stock_conversion_inputs set cost_amount = out_cost
         where id = ln.line_id and cost_amount is distinct from out_cost;
      end if;
      o_qty := o_qty - ln.qty;

    elsif ln.vtype = 'adjust' then
      o_qty := o_qty + ln.qty;          -- average wohi rehta hai
    end if;

    -- Maal andar aaya (purchase / return / conversion-in)
    if in_qty is not null then
      if in_qty <= 0 then
        o_qty := o_qty + in_qty;                         -- cost par asar nahi
      elsif o_qty <= 0 then
        o_cost := round(in_value / in_qty, 4);           -- manfi/khali stock: isi maal ka rate
        o_qty  := o_qty + in_qty;
      else
        o_cost := round(((o_qty * o_cost) + in_value) / (o_qty + in_qty), 4);
        o_qty  := o_qty + in_qty;
      end if;
    end if;
  end loop;
end;
$function$;

create or replace function public.recompute_item_cost(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  w    record;
  prev text;
begin
  -- Do bill ek hi item par ek saath save hon to dono purani history se
  -- gin kar aakhri likhne wala jeet-ta tha. Item row ka lock: doosra
  -- intezaar kare aur pehle wale ki likhi hui history ke saath gine.
  perform 1 from items where id = p_item_id for update;
  if not found then return; end if;

  select * into w from item_cost_walk(p_item_id, null, true);

  -- System apna hisaab likh raha hai — permission check aur audit log se
  -- guzarne ki zaroorat nahi. Flag foran pehle wali halat par wapas.
  prev := current_setting('app.system_write', true);
  perform set_config('app.system_write', 'true', true);
  update items set avg_cost = round(w.o_cost, 4), stock_qty = w.o_qty
   where id = p_item_id
     and (avg_cost, stock_qty) is distinct from (round(w.o_cost, 4), w.o_qty);
  perform set_config('app.system_write', coalesce(nullif(prev, ''), 'false'), true);
end;
$function$;

-- N1: snapshot hamesha as_of_date se PEHLE tak ka (jo bhi likhe)
create or replace function public.trg_snapshot_as_of()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare w record;
begin
  select * into w from item_cost_walk(NEW.item_id, NEW.as_of_date, false);
  NEW.stock_qty := w.o_qty;
  NEW.avg_cost  := round(w.o_cost, 4);
  return NEW;
end;
$function$;

drop trigger if exists trg_snapshot_as_of on item_cost_snapshot;
create trigger trg_snapshot_as_of before insert or update on item_cost_snapshot
  for each row execute function trg_snapshot_as_of();


-- ============================================================
--  HISSA 5 — Delete hui sale par return (L, db/06:226)
--
--  MASLA: sale delete ho jaye to bhi API se us par return ban jata tha —
--  maal stock mein wapas aur party ka balance kam, jabke sale hi nahi.
--  HAL: delete hui sale ka returnable 0; aur nayi return line (ya qty
--  barhana / doosri sale line) delete hui sale par rok di jati hai.
--  Purani return ki qty kam karna ya line hatana ab bhi mumkin hai.
-- ============================================================

create or replace function public.returnable_qty(p_sale_line_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public
as $function$
declare
  sold_qty     numeric;
  sale_deleted boolean;
  returned_qty numeric;
begin
  select vl.qty, v.deleted_at is not null into sold_qty, sale_deleted
    from voucher_lines vl
    join vouchers v on v.id = vl.voucher_id
   where vl.id = p_sale_line_id;
  if sold_qty is null or sale_deleted then return 0; end if;

  select coalesce(sum(srl.qty), 0) into returned_qty
    from sales_return_lines srl
    join sales_returns sr on sr.id = srl.return_id
   where srl.sale_line_id = p_sale_line_id
     and sr.deleted_at is null;

  return sold_qty - returned_qty;
end;
$function$;

create or replace function public.trg_check_returnable_qty()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  avail   numeric;
  s_vno   text;
  s_del   timestamptz;
begin
  if NEW.sale_line_id is null then
    raise exception 'Return line ko original sale-line se juda hona zaroori hai';
  end if;

  if TG_OP = 'INSERT' or NEW.sale_line_id is distinct from OLD.sale_line_id or NEW.qty > OLD.qty then
    select v.vno, v.deleted_at into s_vno, s_del
      from voucher_lines vl join vouchers v on v.id = vl.voucher_id
     where vl.id = NEW.sale_line_id;
    if s_del is not null then
      raise exception 'Sale % delete ho chuki hai — is par return nahi ho sakta', s_vno;
    end if;
  end if;

  avail := returnable_qty(NEW.sale_line_id);

  -- agar ye line pehle se maujood hai (edit ho rahi hai) to uski apni purani qty wapas add kar do
  if TG_OP = 'UPDATE' and NEW.sale_line_id is not distinct from OLD.sale_line_id then
    avail := avail + OLD.qty;
  end if;

  if NEW.qty > avail then
    raise exception 'Sirf % tak hi return ho sakta hai (baaki pehle hi wapas ho chuka)', avail;
  end if;

  return NEW;
end;
$function$;


-- ============================================================
--  HISSA 5b — Receivable Aging (receivable_aging + aging_reconcile)
--
--  MASLA: Masters → Aging report in do RPCs ko bulati hai, magar kisi db
--  file mein yeh banti hi nahi thin. Naye install par Aging report error
--  deti thi (live par shayad haath se bani hon — yeh unhein badal deti hai).
--
--  HAL: party ka balance bilkul Trial Balance (HISSA 1) wali tareef se,
--  sirf p_asof tak ki tareekh ke documents:
--    Dr (barhata hai): opening Dr, sale, service invoice, ledger row[7]
--    Cr (ghatata hai): opening Cr, purchase, sale par paid, service paid,
--                      purchase par paid (Dr), sales return, ledger row[6]
--  Phir FIFO: balance jis taraf hai, us taraf ke documents purane se naye
--  tarteeb mein, aur doosri taraf ki kul raqam sab se purane document par
--  pehle lagti hai ("applied"). Jo bacha wo "outstanding".
--
--  Receivable (Dr balance) ke documents din ke hisaab se khanon mein:
--    due date = bill ki due_date, warna bill date + party.credit_days
--    days_overdue = p_asof − due date
--    notdue (< 0) · b0 (0–30) · b30 (31–60) · b60 (61–90) · b90 (90+)
--    unknown = tareekh hi maloom nahi (opening bina opening_date ke)
--  Cr balance: supplier ho to 'payable', warna 'advance' (customer ne
--  zyada de diya) — screen in do ko alag dikhati hai.
--  Columns wahi jo client1-masters.html (loadAging/drawAging) parhta hai.
--  SECURITY INVOKER — wohi RLS jo tables par hai.
-- ============================================================

create or replace function public.party_balance_docs(p_asof date)
returns table(party_id uuid, sgn integer, amt numeric, doc_no text, doc_date date,
              due_date date, seq_ts timestamptz)
language sql
stable
set search_path = public
as $function$
  -- manfi raqam (misal: opening -5000 Cr) = ulti taraf ki musbat raqam
  select u.pid, (case when u.a < 0 then -u.s else u.s end)::integer, abs(u.a),
         u.dno, u.dd, u.due, u.ts
    from (
  -- opening
  select p.id as pid, case when p.opening_side = 'dr' then 1 else -1 end as s, clean_num(p.opening) as a,
         'Opening'::text as dno, p.opening_date as dd,
         p.opening_date + coalesce(p.credit_days, 0) as due, '-infinity'::timestamptz as ts
    from parties p
   where p.deleted_at is null and clean_num(p.opening) <> 0
  union all
  -- bill: sale Dr / purchase Cr
  select v.party_id, case when v.vtype = 'sale' then 1 else -1 end, clean_num(v.grand_total),
         v.vno, v.vdate,
         coalesce(v.due_date, v.vdate + coalesce(p.credit_days, 0)), v.created_at
    from vouchers v join parties p on p.id = v.party_id
   where v.deleted_at is null and v.vdate <= p_asof and clean_num(v.grand_total) <> 0
  union all
  -- bill par jo paisa usi waqt diya/liya
  select v.party_id, case when v.vtype = 'sale' then -1 else 1 end, clean_num(v.paid),
         v.vno || ' paid', v.vdate, v.vdate, v.created_at
    from vouchers v
   where v.deleted_at is null and v.party_id is not null and v.vdate <= p_asof
     and clean_num(v.paid) <> 0
  union all
  -- service invoice: sale jaisa
  select si.party_id, 1, clean_num(si.grand_total), si.sino, si.sidate,
         si.sidate + coalesce(p.credit_days, 0), si.created_at
    from service_invoices si join parties p on p.id = si.party_id
   where si.deleted_at is null and si.status <> 'cancelled' and si.sidate <= p_asof
     and clean_num(si.grand_total) <> 0
  union all
  select si.party_id, -1, clean_num(si.paid), si.sino || ' paid', si.sidate, si.sidate, si.created_at
    from service_invoices si
   where si.deleted_at is null and si.status <> 'cancelled' and si.party_id is not null
     and si.sidate <= p_asof and clean_num(si.paid) <> 0
  union all
  -- sales return: receivable ghatta hai
  select sr.party_id, -1, clean_num(sr.grand_total), coalesce(sr.rno, 'Return'), sr.rdate, sr.rdate,
         'infinity'::timestamptz
    from sales_returns sr
   where sr.deleted_at is null and sr.party_id is not null and sr.rdate <= p_asof
     and clean_num(sr.grand_total) <> 0
  union all
  -- daily ledger: row[7] Dr (row[0]), row[6] Cr (row[2]) — sirf sahi UUID
  select x.pid, x.sgn, x.amt, 'Ledger', x.sheet_date, x.sheet_date, null::timestamptz
    from (
      select (r ->> 7)::uuid as pid, 1 as sgn, clean_num(r ->> 0) as amt, s.sheet_date
        from sheets s, jsonb_array_elements(s.rows) r
       where s.deleted_at is null and s.sheet_date <= p_asof and jsonb_typeof(r) = 'array'
         and r ->> 7 ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      union all
      select (r ->> 6)::uuid, -1, clean_num(r ->> 2), s.sheet_date
        from sheets s, jsonb_array_elements(s.rows) r
       where s.deleted_at is null and s.sheet_date <= p_asof and jsonb_typeof(r) = 'array'
         and r ->> 6 ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ) x
   where x.amt <> 0
    ) u;
$function$;

create or replace function public.receivable_aging(p_asof date default current_date)
returns table(party_id uuid, party_name text, party_kind text, doc_no text, doc_date date,
              due_date date, original numeric, applied numeric, outstanding numeric,
              days_overdue integer, bucket text)
language sql
stable
set search_path = public
as $function$
  with d as (
    select * from party_balance_docs(coalesce(p_asof, current_date))
  ),
  net as (
    select d.party_id as pid, round(sum(d.sgn * d.amt), 2) as bal
      from d group by d.party_id
  ),
  side_docs as (   -- balance wali taraf ke documents, purane se naye
    select d.*, n.bal,
           sum(d.amt) over (partition by d.party_id
                            order by d.doc_date nulls first, d.seq_ts nulls last, d.doc_no
                            rows between unbounded preceding and current row) as run_amt,
           (select coalesce(sum(o.amt), 0) from d o
             where o.party_id = d.party_id and o.sgn <> d.sgn) as pool
      from d join net n on n.pid = d.party_id
     where n.bal <> 0 and d.sgn = (case when n.bal > 0 then 1 else -1 end)
  ),
  applied as (
    select s.*,
           round(least(s.amt, greatest(s.pool - (s.run_amt - s.amt), 0)), 2) as appl
      from side_docs s
  )
  select a.party_id, p.name, p.kind, a.doc_no, a.doc_date,
         case when a.bal > 0 then a.due_date end,
         round(a.amt, 2), a.appl, round(a.amt - a.appl, 2),
         case when a.bal > 0 and a.due_date is not null
              then (coalesce(p_asof, current_date) - a.due_date) end,
         case
           when a.bal < 0 and p.kind = 'supplier' then 'payable'
           when a.bal < 0 then 'advance'
           when a.due_date is null then 'unknown'
           when coalesce(p_asof, current_date) - a.due_date < 0  then 'notdue'
           when coalesce(p_asof, current_date) - a.due_date <= 30 then 'b0'
           when coalesce(p_asof, current_date) - a.due_date <= 60 then 'b30'
           when coalesce(p_asof, current_date) - a.due_date <= 90 then 'b60'
           else 'b90'
         end
    from applied a join parties p on p.id = a.party_id
   where p.deleted_at is null and round(a.amt - a.appl, 2) <> 0
   order by p.name, a.doc_date nulls first;
$function$;

-- Aging ka jama party ke ledger balance (TB tareef, p_asof tak) se milao.
-- Ledger balance yahan seedhe tables se — aging wale raste se alag — ginte hain.
create or replace function public.aging_reconcile(p_asof date default current_date)
returns table(party_id uuid, party_name text, aging_total numeric, ledger_balance numeric, diff numeric)
language sql
stable
set search_path = public
as $function$
  with asof as (select coalesce(p_asof, current_date) as d),
  ledger as (
    select p.id as pid, p.name,
      round(
        (case when p.opening_side = 'dr' then 1 else -1 end) * clean_num(p.opening)
      + coalesce((select sum((case when v.vtype = 'sale' then 1 else -1 end) * clean_num(v.grand_total)
                           + (case when v.vtype = 'sale' then -1 else 1 end) * clean_num(v.paid))
                    from vouchers v, asof where v.party_id = p.id and v.deleted_at is null and v.vdate <= asof.d), 0)
      + coalesce((select sum(clean_num(si.grand_total) - clean_num(si.paid))
                    from service_invoices si, asof
                   where si.party_id = p.id and si.deleted_at is null and si.status <> 'cancelled'
                     and si.sidate <= asof.d), 0)
      - coalesce((select sum(clean_num(sr.grand_total)) from sales_returns sr, asof
                   where sr.party_id = p.id and sr.deleted_at is null and sr.rdate <= asof.d), 0)
      + coalesce((select sum(clean_num(r ->> 0)) from sheets s, asof, jsonb_array_elements(s.rows) r
                   where s.deleted_at is null and s.sheet_date <= asof.d and jsonb_typeof(r) = 'array'
                     and r ->> 7 = p.id::text), 0)
      - coalesce((select sum(clean_num(r ->> 2)) from sheets s, asof, jsonb_array_elements(s.rows) r
                   where s.deleted_at is null and s.sheet_date <= asof.d and jsonb_typeof(r) = 'array'
                     and r ->> 6 = p.id::text), 0), 2) as bal
      from parties p where p.deleted_at is null
  ),
  aged as (
    select a.party_id as pid,
           round(sum(case when a.bucket in ('payable', 'advance') then -a.outstanding
                          else a.outstanding end), 2) as tot
      from receivable_aging(p_asof) a group by a.party_id
  )
  select l.pid, l.name, coalesce(g.tot, 0), l.bal, round(l.bal - coalesce(g.tot, 0), 2)
    from ledger l left join aged g on g.pid = l.pid
   where l.bal <> 0 or coalesce(g.tot, 0) <> 0
   order by l.name;
$function$;


-- ============================================================
--  HISSA 6 — Ijazat (db/27 ka usool)
--
--  Nayi andar wali functions bahar se band — yeh sirf triggers aur
--  costing ke andar se chalti hain. trial_balance / recompute_item_cost /
--  returnable_qty "create or replace" hain, un ki purani ijazat jyun ki
--  tyun rehti hai.
-- ============================================================

revoke all on function public.js_round2(double precision)               from public, anon, authenticated;
revoke all on function public.doc_line_amount(numeric, numeric, numeric) from public, anon, authenticated;
revoke all on function public.doc_totals(text, uuid, jsonb)               from public, anon, authenticated;
revoke all on function public.recalc_doc_totals(text, uuid[])             from public, anon, authenticated;
revoke all on function public.item_cost_walk(uuid, date, boolean)         from public, anon, authenticated;
revoke all on function public.check_period_lock_sales_returns()           from public, anon;
revoke all on function public.check_period_lock_lines()                   from public, anon;
revoke all on function public.check_period_lock_adjustments()             from public, anon;
revoke all on function public.trg_doc_header_totals()                     from public, anon;
revoke all on function public.trg_doc_line_amount()                       from public, anon;
revoke all on function public.trg_doc_lines_stmt()                        from public, anon;
revoke all on function public.trg_doc_lines_row()                         from public, anon;
revoke all on function public.trg_snapshot_as_of()                        from public, anon;
revoke all on function public.trial_balance()                             from public, anon;
grant execute on function public.trial_balance()                          to authenticated;
revoke all on function public.party_balance_docs(date)                    from public, anon;
revoke all on function public.receivable_aging(date)                      from public, anon;
revoke all on function public.aging_reconcile(date)                       from public, anon;
grant execute on function public.party_balance_docs(date)                 to authenticated;
grant execute on function public.receivable_aging(date)                   to authenticated;
grant execute on function public.aging_reconcile(date)                    to authenticated;


-- ============================================================
--  HISSA 7 — Purane data ki janch (sirf NOTICE, kuch nahi badalta)
-- ============================================================

do $$
declare
  n_hdr  integer;
  n_qty  integer;
  n_neg  integer;
begin
  select count(*) into n_hdr
    from vouchers v cross join lateral doc_totals('vouchers', v.id, to_jsonb(v)) t
   where v.deleted_at is null
     and (abs(v.sub_total - t.o_sub) > 0.005 or abs(v.grand_total - t.o_grand) > 0.005);
  select count(*) into n_qty from voucher_lines where qty <= 0;
  select count(*) into n_neg from vouchers where discount < 0 or paid < 0;
  raise notice '35: % live bill(s) ke header totals lines se mel nahi khate (purane — badle nahi gaye; agli edit par khud theek honge)', n_hdr;
  raise notice '35: % bill line(s) ki qty <= 0, % bill(s) ka discount/paid manfi (purane — chhor diye; dobara save par rukenge)', n_qty, n_neg;
end $$;


-- ============================================================
--  HISSA 8 — EK DAFA: sab items ki costing naye formula se
--
--  recompute_all_item_costs() wala hi tareeqa (conversions ho to teen
--  chakkar + allocation), magar seedha yahan — taake us function par lagi
--  kisi permission check (SQL editor mein login nahi hota) se na atke.
--  Period lock lagi ho to snapshot nayi (lock-date wali) shakal mein.
-- ============================================================

do $$
declare
  lock_d   date;
  it_id    uuid;
  cv_id    uuid;
  has_conv boolean;
  pass     integer;
  n_items  integer := 0;
begin
  select locked_before into lock_d from period_lock where id = 1;
  delete from item_cost_snapshot where true;

  select exists (select 1 from stock_conversions where deleted_at is null and status <> 'cancelled')
    into has_conv;

  for pass in 1 .. (case when has_conv then 3 else 1 end) loop
    for it_id in select id from items loop
      perform recompute_item_cost(it_id);
      n_items := n_items + 1;
    end loop;
    if has_conv then
      for cv_id in select id from stock_conversions
                    where deleted_at is null and status <> 'cancelled' order by cdate, id
      loop
        perform allocate_conversion_cost(cv_id);
      end loop;
    end if;
  end loop;

  if has_conv then   -- allocation ke baad averages dobara
    for it_id in select id from items loop
      perform recompute_item_cost(it_id);
    end loop;
  end if;

  if lock_d is not null then   -- trg_snapshot_as_of asal number khud bharta hai
    insert into item_cost_snapshot (item_id, as_of_date, avg_cost, stock_qty)
      select id, lock_d, 0, 0 from items;
  end if;

  raise notice '35: costing dobara gini gayi (% item-chakkar), lock = %', n_items, lock_d;
end $$;
