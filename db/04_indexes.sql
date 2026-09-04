-- ============================================================
--  04 — Indexes
--
--  Note: master system mein kuch indexes teen teen dafa mojood thay
--  (misaal: voucher_lines.item_id par vlines_item_idx, idx_voucher_lines_item_id
--  aur voucher_lines_item_id_idx — teenon aik jaise). Yahan har ek sirf
--  aik dafa banaya gaya hai. Kaam bilkul wohi rehta hai, DB halka rehta hai.
-- ============================================================

-- ---------- Masters ----------

create unique index if not exists parties_name_uniq   on parties   (lower(trim(both from name)));
create        index if not exists parties_name_idx    on parties   (name);
create        index if not exists parties_deleted_idx on parties   (deleted_at);

create unique index if not exists items_name_uniq     on items     (lower(trim(both from name)));
create        index if not exists items_name_idx      on items     (name);
create        index if not exists items_deleted_idx   on items     (deleted_at);

create unique index if not exists companies_name_uniq on companies (lower(trim(both from name)));
create        index if not exists companies_deleted_idx on companies (deleted_at);

-- ---------- Vouchers ----------

-- Voucher number kabhi dohraya na jaye. Do alag index:
--   vouchers_no_uniq          — deleted vouchers samet (number dobara istemaal na ho)
--   vouchers_vtype_vno_unique — sirf active vouchers par
create unique index if not exists vouchers_no_uniq
  on vouchers (vtype, lower(trim(both from vno)))
  where trim(both from vno) <> ''::text;

create unique index if not exists vouchers_vtype_vno_unique
  on vouchers (vtype, vno)
  where deleted_at is null and vno is not null and vno <> ''::text;

create index if not exists vouchers_party_idx   on vouchers (party_id);
create index if not exists vouchers_vdate_idx   on vouchers (vdate desc);
create index if not exists vouchers_deleted_idx on vouchers (deleted_at);
create index if not exists vouchers_active_idx  on vouchers (party_id, vdate desc) where deleted_at is null;

create index if not exists voucher_lines_voucher_idx   on voucher_lines (voucher_id);
create index if not exists voucher_lines_item_idx      on voucher_lines (item_id);
create index if not exists voucher_lines_warehouse_idx on voucher_lines (warehouse_id);

-- ---------- Sales returns ----------

create index if not exists sales_returns_party_idx      on sales_returns (party_id);
create index if not exists sales_returns_sale_idx       on sales_returns (sale_id);
create index if not exists sales_returns_rdate_idx      on sales_returns (rdate desc);
create index if not exists sales_return_lines_ret_idx   on sales_return_lines (return_id);
create index if not exists sales_return_lines_sline_idx on sales_return_lines (sale_line_id);

-- ---------- Quotations & POs ----------

create index if not exists quotations_party_idx     on quotations (party_id);
create index if not exists quotations_qdate_idx     on quotations (qdate desc);
create index if not exists quotation_lines_qid_idx  on quotation_lines (quotation_id);

create index if not exists po_party_idx    on purchase_orders (party_id);
create index if not exists po_podate_idx   on purchase_orders (podate desc);
create index if not exists po_lines_po_idx on po_lines (po_id);

-- ---------- Stock ----------

create index if not exists stock_transfers_tdate_idx    on stock_transfers (tdate desc);
create index if not exists stock_transfer_lines_tid_idx on stock_transfer_lines (transfer_id);
create index if not exists stock_adjustments_item_idx   on stock_adjustments (item_id);
create index if not exists stock_adjustments_date_idx   on stock_adjustments (adj_date desc);

-- ---------- Daily Ledger ----------

create index if not exists sheets_date_idx        on sheets (sheet_date desc);
create index if not exists sheets_deleted_idx     on sheets (deleted_at);
create index if not exists sheets_active_date_idx on sheets (sheet_date desc) where deleted_at is null;

-- ---------- Audit ----------

create index if not exists audit_log_changed_at_idx    on audit_log (changed_at desc);
create index if not exists audit_log_table_record_idx  on audit_log (table_name, record_id);
