-- ============================================================
--  29 — Bara data saaf karne ke liye (TRUNCATE)
--
--  KAB YEH, AUR KAB APP KA BUTTON?
--
--  Masters → Wipe Test Data (yani wipe_test_data function) chhote data
--  ke liye theek hai. Magar us ki ek hadd hai:
--
--    Supabase `authenticated` role par statement_timeout = 8 second
--    laga kar rakhta hai.
--
--  DELETE har row par saare triggers chalati hai — costing dobara,
--  coil balance dobara, audit log. 68,000 bill lines par yeh kai minute
--  ka kaam hai, aur 8 second mein kabhi mukammal nahi hota. App timeout
--  ko "internet nahi hai" samajh kar ghalat message dikhati hai:
--
--    "No internet — wipe not saved"
--
--  Us waqt YEH file istemaal karein, SQL Editor se.
--
--  TRUNCATE kyun chalti hai jahan DELETE nahi chalti:
--    * row-level triggers bilkul nahi chalate — is liye foran hoti hai
--    * SQL Editor `postgres` ban kar chalta hai — 8 second wali hadd
--      us par nahi lagti
--    * safeupdate ka "WHERE clause" wala guard bhi nahi lagta
--
--  YEH WAPAS NAHI HOTA. Chalane se pehle roz wali backup email
--  (QTC-Restore-<date>.json) apne paas mehfooz rakhein.
-- ============================================================


-- ============================================================
--  HISSA 1 — Data urhao
--
--  Yeh 35 tables. Har wo table jo in mein se kisi ki taraf ishara
--  karti hai, khud bhi is list mein hai — is liye "cascade" se koi
--  ghair-mutawaqqa table nahi urhegi.
--
--  Masters (parties, items, companies, item_units) bhi is list mein
--  hain. Agar unhein BACHANA ho to aakhri chaar naam hata dein.
-- ============================================================

truncate table
  -- Own Stock Conversion
  stock_conversion_outputs, stock_conversion_inputs, stock_conversions,
  -- Party Cutting / Processing
  service_invoice_challans, service_invoice_jobs, service_invoice_lines, service_invoices,
  delivery_challan_lines, delivery_challans,
  material_return_lines, material_returns,
  cutting_job_outputs, cutting_job_inputs, cutting_jobs,
  coils, material_inwards,
  -- Accounting
  voucher_lines, quotation_lines, po_lines, sales_return_lines, stock_transfer_lines,
  stock_adjustments, audit_log, item_cost_snapshot, party_opening_balances,
  vouchers, quotations, purchase_orders, sales_returns, stock_transfers, sheets,
  -- Masters (in chaar ko hata dein agar bachani hon)
  item_units, parties, items, companies
cascade;


-- ============================================================
--  HISSA 2 — Period lock khol do
-- ============================================================

update period_lock set locked_before = null where id = 1;


-- ============================================================
--  HISSA 3 — Ginti wapas 1 par
--
--  1, false ka matlab: agla number 1 milega (2 nahi).
-- ============================================================

select setval('voucher_sale_seq',     1, false);
select setval('voucher_purchase_seq', 1, false);
select setval('mi_seq',   1, false);
select setval('cj_seq',   1, false);
select setval('dc_seq',   1, false);
select setval('mr_seq',   1, false);
select setval('sv_seq',   1, false);
select setval('cv_seq',   1, false);
select setval('coil_seq', 1, false);


-- ============================================================
--  HISSA 4 — Tasdeeq
--
--  Har count 0, aur har ginti "1 (abhi shuru nahi hui)".
-- ============================================================

select 'vouchers' t, count(*) from vouchers
union all select 'voucher_lines', count(*) from voucher_lines
union all select 'sheets',        count(*) from sheets
union all select 'coils',         count(*) from coils
union all select 'cutting_jobs',  count(*) from cutting_jobs
union all select 'parties',       count(*) from parties
union all select 'items',         count(*) from items
union all select 'companies',     count(*) from companies
union all select 'audit_log',     count(*) from audit_log
order by 1;

select sequencename,
       case when last_value is null then '1 (abhi shuru nahi hui)'
            else (last_value + 1)::text end as agla_number
  from pg_sequences where schemaname = 'public' order by sequencename;


-- ============================================================
--  BAAD MEIN
--
--  Masters bhi urha di hain to bill banane se pehle kam se kam EK FIRM
--  banani hogi — Masters → Firms. (DEPLOYMENT.md ka section 10.)
--
--  Yeh tables jyun ki tyun rehti hain:
--    app_users (logins aur permissions), app_settings, cutting_settings,
--    period_lock, warehouses, party_kinds, machines, operators,
--    service_categories
-- ============================================================
