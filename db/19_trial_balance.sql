-- ============================================================
--  19 — Trial Balance: Service Invoices shamil karna
--
--  Requirement 28: Service Invoice usi financial Party Ledger mein
--  jayega — alag customer ledger nahi banega.
--
--  Service Invoice sale ki tarah hi chalta hai: party ka balance
--  grand_total se barhta hai, aur jo paisa mila (paid) usse ghatta hai.
--
--  YEH FILE 08_rpc_functions.sql WALE trial_balance() KO BADALTI HAI.
--  Cutting module install karne ke baad hi chalayein.
-- ============================================================

create or replace function public.trial_balance()
returns table(party_id uuid, party_name text, balance numeric, side text)
language plpgsql
stable
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
  cash_credit as (   -- row[6] = credit party (paisa aaya) → balance ghatta hai
    select nullif(row_data ->> 6, '')::uuid as pid,
           sum(clean_num(row_data ->> 2)) * -1 as amt
      from sheets s, jsonb_array_elements(s.rows) as row_data
     where s.deleted_at is null and row_data ->> 6 is not null and row_data ->> 6 <> ''
     group by row_data ->> 6
  ),
  cash_debit as (    -- row[7] = debit party (paisa gaya) → balance barhta hai
    select nullif(row_data ->> 7, '')::uuid as pid,
           sum(clean_num(row_data ->> 0)) as amt
      from sheets s, jsonb_array_elements(s.rows) as row_data
     where s.deleted_at is null and row_data ->> 7 is not null and row_data ->> 7 <> ''
     group by row_data ->> 7
  ),
  combined as (
    select pid, amt from opening
    union all select pid, amt from bills
    union all select pid, amt from services
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
--  Test data wipe — cutting module ki tables bhi shamil
--  (Own Conversion ki tables 24_final_wipe.sql mein add hoti hain,
--   kyunki wo tables 21 mein banti hain.)
-- ============================================================

create or replace function public.wipe_test_data(p_include_masters boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not is_app_admin() then
    raise exception 'Sirf admin ye kar sakta hai';
  end if;

  -- Cutting / Processing (lines pehle, phir headers)
  delete from service_invoice_challans;
  delete from service_invoice_jobs;
  delete from service_invoice_lines;
  delete from service_invoices;
  delete from delivery_challan_lines;
  delete from delivery_challans;
  delete from material_return_lines;
  delete from material_returns;
  delete from cutting_job_outputs;
  delete from cutting_job_inputs;
  delete from cutting_jobs;
  delete from coils;
  delete from material_inwards;

  -- Accounting
  delete from voucher_lines;
  delete from quotation_lines;
  delete from po_lines;
  delete from sales_return_lines;
  delete from stock_transfer_lines;
  delete from stock_adjustments;
  delete from audit_log;
  delete from item_cost_snapshot;
  delete from party_opening_balances;
  delete from vouchers;
  delete from quotations;
  delete from purchase_orders;
  delete from sales_returns;
  delete from stock_transfers;
  delete from sheets;

  update items set avg_cost = 0, stock_qty = 0;
  update period_lock set locked_before = null where id = 1;

  if p_include_masters then
    delete from parties;
    delete from items;
    delete from companies;
  end if;

  return jsonb_build_object('status', 'ok');
end;
$function$;
