-- ============================================================
--  28 — Fresh start: data saaf, ginti dobara 1 se
--
--  Masla jo theek kiya ja raha hai:
--
--  wipe_test_data() saara data to urha deti thi, magar NUMBERING ko
--  haath nahi lagati thi. Nateeja: system khali dikhta, magar agla bill
--  S-0001 ke bajaye S-0009 se shuru hota. Client ko naya system dete
--  waqt yeh bura lagta hai — aur ginti mein khali jagahen hamesha
--  sawaal khari karti hain.
--
--  Ab yeh function 9 sequences bhi wapas 1 par le aati hai:
--    voucher_sale_seq, voucher_purchase_seq  (bill S-0001 / P-0001)
--    mi_seq   (material inward   MI-0001)
--    cj_seq   (cutting job       CJ-0001)
--    dc_seq   (delivery challan  DC-0001)
--    mr_seq   (material return   MR-0001)
--    sv_seq   (service invoice   SV-0001)
--    cv_seq   (conversion        CV-0001)
--    coil_seq (coil serial       CUT-2026-000001)
--
--  Baqi kaam bilkul wahi hai jo 24 wali file mein tha — koi tabdeeli
--  nahi. Sirf sequences ka hissa naya hai.
--
--  25/26/27 ke baad chalayein.
-- ============================================================

create or replace function public.wipe_test_data(p_include_masters boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  s   text;
  seqs text[] := array[
    'voucher_sale_seq', 'voucher_purchase_seq',
    'mi_seq', 'cj_seq', 'dc_seq', 'mr_seq', 'sv_seq', 'cv_seq', 'coil_seq'
  ];
begin
  if not is_app_admin() then
    raise exception 'Sirf admin ye kar sakta hai';
  end if;

  /* Har DELETE aur UPDATE par "where true" lazmi hai.

     Supabase `authenticated` role par safeupdate laga kar rakhta hai —
     wo bina WHERE wali DELETE/UPDATE ko rok deta hai, taake koi ghalti
     se poori table na urha de. Yeh rok SECURITY DEFINER function ke
     andar bhi lagti hai, kyunki wo session ki setting hai, user ki
     nahi.

     Isi wajah se wipe_test_data() app ke button se kabhi chali hi
     nahi — "DELETE requires a WHERE clause" par ruk jati thi.

     "where true" us guard ko poora kar deta hai aur kaam wahi rehta
     hai: sab kuch urh jata hai. (06, 07 aur 22 wali files mein yeh
     tareeqa pehle se istemaal hua hai.) */

  -- ---------- Own Stock Conversion ----------
  delete from stock_conversion_outputs where true;
  delete from stock_conversion_inputs  where true;
  delete from stock_conversions        where true;

  -- ---------- Party Cutting / Processing (lines pehle, phir headers) ----------
  delete from service_invoice_challans where true;
  delete from service_invoice_jobs     where true;
  delete from service_invoice_lines    where true;
  delete from service_invoices         where true;
  delete from delivery_challan_lines   where true;
  delete from delivery_challans        where true;
  delete from material_return_lines    where true;
  delete from material_returns         where true;
  delete from cutting_job_outputs      where true;
  delete from cutting_job_inputs       where true;
  delete from cutting_jobs             where true;
  delete from coils                    where true;
  delete from material_inwards         where true;

  -- ---------- Accounting ----------
  delete from voucher_lines          where true;
  delete from quotation_lines        where true;
  delete from po_lines               where true;
  delete from sales_return_lines     where true;
  delete from stock_transfer_lines   where true;
  delete from stock_adjustments      where true;
  delete from audit_log              where true;
  delete from item_cost_snapshot     where true;
  delete from party_opening_balances where true;
  delete from vouchers               where true;
  delete from quotations             where true;
  delete from purchase_orders        where true;
  delete from sales_returns          where true;
  delete from stock_transfers        where true;
  delete from sheets                 where true;

  update items set avg_cost = 0, stock_qty = 0 where true;
  update period_lock set locked_before = null where id = 1;

  if p_include_masters then
    -- item_units khud urh jati hain — items par cascade laga hua hai
    delete from parties   where true;
    delete from items     where true;
    delete from companies where true;
  end if;

  /* ---------- Ginti wapas 1 par ----------
     setval(..., 1, false) ka matlab: agli dafa jo number milega wo 1
     hoga. (Agar 1, true likhein to agla number 2 mil jata.)
     to_regclass is liye ke agar koi sequence kisi purane system mein
     mojood na ho to yeh function wahin ruk na jaye. */
  foreach s in array seqs loop
    if to_regclass('public.' || s) is not null then
      -- s ek text hai; setval regclass maangti hai, is liye cast lazmi
      perform setval(s::regclass, 1, false);
    end if;
  end loop;

  return jsonb_build_object(
    'status', 'ok',
    'masters_deleted', p_include_masters,
    'sequences_reset', array_length(seqs, 1)
  );
end;
$function$;

-- Ijazat wahi jo 27 wali file ne tay ki thi
revoke all on function public.wipe_test_data(boolean) from public, anon;
grant execute on function public.wipe_test_data(boolean) to authenticated;


-- ============================================================
--  CHALANE KA TAREEQA
--
--  Do raaste hain — dono ek hi kaam karte hain:
--
--  1. App se (asaan):
--       Masters → Wipe Test Data   (sirf admin ko dikhta hai)
--
--  2. SQL Editor se:
--       select wipe_test_data(true);   -- masters BHI urhengi
--       select wipe_test_data(false);  -- masters bachengi
--
--  DHYAN DEIN: yeh wapas nahi hota. Chalane se pehle backup email
--  (QTC-Restore-<date>.json) apne paas mehfooz rakhein.
-- ============================================================


-- ============================================================
--  Chalane ke BAAD yeh chala kar tasdeeq kar lein
--
--  Har ginti "1 (abhi shuru nahi hui)" honi chahiye, aur har table
--  ka count 0.
-- ============================================================

-- select sequencename, last_value,
--        case when last_value is null then '1 (abhi shuru nahi hui)'
--             else last_value::text end as agla_number
--   from pg_sequences where schemaname = 'public' order by sequencename;

-- select 'vouchers' as t, count(*) from vouchers
-- union all select 'sheets',        count(*) from sheets
-- union all select 'coils',         count(*) from coils
-- union all select 'cutting_jobs',  count(*) from cutting_jobs
-- union all select 'parties',       count(*) from parties
-- union all select 'items',         count(*) from items
-- union all select 'companies',     count(*) from companies
-- union all select 'audit_log',     count(*) from audit_log;
