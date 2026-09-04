-- ============================================================
--  24 — Test data wipe ka aakhri version
--
--  Sab se aakhir mein chalayein. Yeh 19 wale wipe_test_data() ko
--  badalti hai aur Own Stock Conversion ki tables bhi shamil karti hai.
--  (Alag file is liye hai ke wo tables 21 mein banti hain.)
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

  -- Own Stock Conversion
  delete from stock_conversion_outputs;
  delete from stock_conversion_inputs;
  delete from stock_conversions;

  -- Party Cutting / Processing (lines pehle, phir headers)
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
