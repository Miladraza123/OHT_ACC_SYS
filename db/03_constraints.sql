-- ============================================================
--  03 — Primary keys, Unique keys, Foreign keys, CHECK constraints
-- ============================================================

-- ---------- Primary keys ----------

alter table app_users              add constraint app_users_pkey              primary key (id);
alter table audit_log              add constraint audit_log_pkey              primary key (id);
alter table companies              add constraint companies_pkey              primary key (id);
alter table parties                add constraint parties_pkey                primary key (id);
alter table party_kinds            add constraint party_kinds_pkey            primary key (id);
alter table items                  add constraint items_pkey                  primary key (id);
alter table warehouses             add constraint warehouses_pkey             primary key (id);
alter table period_lock            add constraint period_lock_pkey            primary key (id);
alter table party_opening_balances add constraint party_opening_balances_pkey primary key (party_id);
alter table item_cost_snapshot     add constraint item_cost_snapshot_pkey     primary key (item_id);
alter table vouchers               add constraint vouchers_pkey               primary key (id);
alter table voucher_lines          add constraint voucher_lines_pkey          primary key (id);
alter table sales_returns          add constraint sales_returns_pkey          primary key (id);
alter table sales_return_lines     add constraint sales_return_lines_pkey     primary key (id);
alter table quotations             add constraint quotations_pkey             primary key (id);
alter table quotation_lines        add constraint quotation_lines_pkey        primary key (id);
alter table purchase_orders        add constraint purchase_orders_pkey        primary key (id);
alter table po_lines               add constraint po_lines_pkey               primary key (id);
alter table stock_transfers        add constraint stock_transfers_pkey        primary key (id);
alter table stock_transfer_lines   add constraint stock_transfer_lines_pkey   primary key (id);
alter table stock_adjustments      add constraint stock_adjustments_pkey      primary key (id);
alter table sheets                 add constraint sheets_pkey                 primary key (id);

-- ---------- Unique keys ----------

alter table app_users   add constraint app_users_username_key   unique (username);
alter table party_kinds add constraint party_kinds_value_key    unique (value);
alter table sheets      add constraint sheets_sheet_date_key    unique (sheet_date);

-- ---------- CHECK constraints ----------

alter table period_lock add constraint period_lock_id_check check (id = 1);

alter table parties add constraint parties_name_required
  check (name is not null and trim(both from name) <> ''::text);

alter table items add constraint items_name_required
  check (name is not null and trim(both from name) <> ''::text);

alter table items add constraint items_opening_nonneg
  check ((opening_qty is null or opening_qty >= 0::numeric)
     and (opening_rate is null or opening_rate >= 0::numeric));

alter table voucher_lines add constraint voucher_lines_qty_nonneg  check (qty  >= 0::numeric);
alter table voucher_lines add constraint voucher_lines_rate_nonneg check (rate >= 0::numeric);

-- ---------- Foreign keys: users ----------

alter table app_users add constraint app_users_id_fkey
  foreign key (id) references auth.users(id) on delete cascade;

alter table audit_log add constraint audit_log_changed_by_fkey
  foreign key (changed_by) references app_users(id);

-- ---------- Foreign keys: masters ----------

alter table companies add constraint companies_created_by_fkey foreign key (created_by) references app_users(id);
alter table companies add constraint companies_updated_by_fkey foreign key (updated_by) references app_users(id);

alter table parties add constraint parties_created_by_fkey foreign key (created_by) references app_users(id);
alter table parties add constraint parties_updated_by_fkey foreign key (updated_by) references app_users(id);

alter table items add constraint items_created_by_fkey foreign key (created_by) references app_users(id);
alter table items add constraint items_updated_by_fkey foreign key (updated_by) references app_users(id);

alter table warehouses add constraint warehouses_created_by_fkey foreign key (created_by) references app_users(id);
alter table warehouses add constraint warehouses_updated_by_fkey foreign key (updated_by) references app_users(id);

-- ---------- Foreign keys: accounting config ----------

alter table party_opening_balances add constraint party_opening_balances_party_id_fkey
  foreign key (party_id) references parties(id) on delete cascade;

alter table item_cost_snapshot add constraint item_cost_snapshot_item_id_fkey
  foreign key (item_id) references items(id) on delete cascade;

-- ---------- Foreign keys: vouchers ----------

alter table vouchers add constraint vouchers_party_id_fkey   foreign key (party_id)   references parties(id);
alter table vouchers add constraint vouchers_company_id_fkey foreign key (company_id) references companies(id);
alter table vouchers add constraint vouchers_created_by_fkey foreign key (created_by) references app_users(id);
alter table vouchers add constraint vouchers_updated_by_fkey foreign key (updated_by) references auth.users(id);

alter table voucher_lines add constraint voucher_lines_voucher_id_fkey
  foreign key (voucher_id) references vouchers(id) on delete cascade;
alter table voucher_lines add constraint voucher_lines_item_id_fkey      foreign key (item_id)      references items(id);
alter table voucher_lines add constraint voucher_lines_warehouse_id_fkey foreign key (warehouse_id) references warehouses(id);

-- ---------- Foreign keys: sales returns ----------

alter table sales_returns add constraint sales_returns_sale_id_fkey    foreign key (sale_id)    references vouchers(id);
alter table sales_returns add constraint sales_returns_party_id_fkey   foreign key (party_id)   references parties(id);
alter table sales_returns add constraint sales_returns_created_by_fkey foreign key (created_by) references app_users(id);
alter table sales_returns add constraint sales_returns_updated_by_fkey foreign key (updated_by) references app_users(id);

alter table sales_return_lines add constraint sales_return_lines_return_id_fkey
  foreign key (return_id) references sales_returns(id) on delete cascade;
alter table sales_return_lines add constraint sales_return_lines_sale_line_id_fkey foreign key (sale_line_id) references voucher_lines(id);
alter table sales_return_lines add constraint sales_return_lines_item_id_fkey      foreign key (item_id)      references items(id);
alter table sales_return_lines add constraint sales_return_lines_warehouse_id_fkey foreign key (warehouse_id) references warehouses(id);

-- ---------- Foreign keys: quotations ----------

alter table quotations add constraint quotations_party_id_fkey   foreign key (party_id)   references parties(id);
alter table quotations add constraint quotations_company_id_fkey foreign key (company_id) references companies(id);
alter table quotations add constraint quotations_created_by_fkey foreign key (created_by) references app_users(id);
alter table quotations add constraint quotations_updated_by_fkey foreign key (updated_by) references app_users(id);

alter table quotation_lines add constraint quotation_lines_quotation_id_fkey
  foreign key (quotation_id) references quotations(id) on delete cascade;
alter table quotation_lines add constraint quotation_lines_item_id_fkey foreign key (item_id) references items(id);

-- ---------- Foreign keys: purchase orders ----------

alter table purchase_orders add constraint purchase_orders_party_id_fkey   foreign key (party_id)   references parties(id);
alter table purchase_orders add constraint purchase_orders_company_id_fkey foreign key (company_id) references companies(id);
alter table purchase_orders add constraint purchase_orders_created_by_fkey foreign key (created_by) references app_users(id);
alter table purchase_orders add constraint purchase_orders_updated_by_fkey foreign key (updated_by) references app_users(id);

alter table po_lines add constraint po_lines_po_id_fkey
  foreign key (po_id) references purchase_orders(id) on delete cascade;
alter table po_lines add constraint po_lines_item_id_fkey foreign key (item_id) references items(id);

-- ---------- Foreign keys: stock ----------

alter table stock_transfers add constraint stock_transfers_from_warehouse_fkey foreign key (from_warehouse) references warehouses(id);
alter table stock_transfers add constraint stock_transfers_to_warehouse_fkey   foreign key (to_warehouse)   references warehouses(id);
alter table stock_transfers add constraint stock_transfers_created_by_fkey     foreign key (created_by)     references app_users(id);
alter table stock_transfers add constraint stock_transfers_updated_by_fkey     foreign key (updated_by)     references app_users(id);

alter table stock_transfer_lines add constraint stock_transfer_lines_transfer_id_fkey
  foreign key (transfer_id) references stock_transfers(id) on delete cascade;

alter table stock_adjustments add constraint stock_adjustments_item_id_fkey
  foreign key (item_id) references items(id) on delete cascade;
alter table stock_adjustments add constraint stock_adjustments_warehouse_id_fkey foreign key (warehouse_id) references warehouses(id);
alter table stock_adjustments add constraint stock_adjustments_updated_by_fkey   foreign key (updated_by)   references auth.users(id);

-- ---------- Foreign keys: sheets ----------

alter table sheets add constraint sheets_created_by_fkey foreign key (created_by) references app_users(id);
alter table sheets add constraint sheets_updated_by_fkey foreign key (updated_by) references auth.users(id);
