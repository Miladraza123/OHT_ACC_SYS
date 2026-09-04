-- ============================================================
--  10 — Row Level Security
--
--  Usool: har logged-in user sab kuch parh sakta hai (SELECT),
--  lekin likhne (INSERT/UPDATE/DELETE) ke liye permission chahiye.
--  Hard delete sirf admin kar sakta hai — aam users soft delete
--  (deleted_at set karna) karte hain, jise trg_perm_* check karta hai.
-- ============================================================

alter table app_users              enable row level security;
alter table audit_log              enable row level security;
alter table companies              enable row level security;
alter table parties                enable row level security;
alter table party_kinds            enable row level security;
alter table items                  enable row level security;
alter table warehouses             enable row level security;
alter table period_lock            enable row level security;
alter table party_opening_balances enable row level security;
alter table item_cost_snapshot     enable row level security;
alter table vouchers               enable row level security;
alter table voucher_lines          enable row level security;
alter table sales_returns          enable row level security;
alter table sales_return_lines     enable row level security;
alter table quotations             enable row level security;
alter table quotation_lines        enable row level security;
alter table purchase_orders        enable row level security;
alter table po_lines               enable row level security;
alter table stock_transfers        enable row level security;
alter table stock_transfer_lines   enable row level security;
alter table stock_adjustments      enable row level security;
alter table sheets                 enable row level security;

-- ---------- app_users ----------
drop policy if exists "app_users read"        on app_users;
drop policy if exists "app_users admin write" on app_users;

create policy "app_users read"        on app_users for select using (auth.role() = 'authenticated');
create policy "app_users admin write" on app_users for all    using (is_app_admin()) with check (is_app_admin());

-- ---------- audit_log ----------
drop policy if exists "audit_log select" on audit_log;
create policy "audit_log select" on audit_log for select using (is_app_admin());

-- ---------- companies ----------
drop policy if exists "companies select" on companies;
drop policy if exists "companies insert" on companies;
drop policy if exists "companies update" on companies;
drop policy if exists "companies delete" on companies;

create policy "companies select" on companies for select using (auth.role() = 'authenticated');
create policy "companies insert" on companies for insert with check (is_app_admin() or has_perm('masters_edit'));
create policy "companies update" on companies for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "companies delete" on companies for delete using (is_app_admin());

-- ---------- parties ----------
drop policy if exists "parties select" on parties;
drop policy if exists "parties insert" on parties;
drop policy if exists "parties update" on parties;
drop policy if exists "parties delete" on parties;

create policy "parties select" on parties for select using (auth.role() = 'authenticated');
create policy "parties insert" on parties for insert with check (is_app_admin() or has_perm('masters_edit'));
create policy "parties update" on parties for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "parties delete" on parties for delete using (is_app_admin());

-- ---------- party_kinds ----------
drop policy if exists "party_kinds select" on party_kinds;
drop policy if exists "party_kinds write"  on party_kinds;

create policy "party_kinds select" on party_kinds for select using (auth.role() = 'authenticated');
create policy "party_kinds write"  on party_kinds for all
  using (is_app_admin() or has_perm('masters_categories'))
  with check (is_app_admin() or has_perm('masters_categories'));

-- ---------- items ----------
drop policy if exists "items select" on items;
drop policy if exists "items insert" on items;
drop policy if exists "items update" on items;
drop policy if exists "items delete" on items;

create policy "items select" on items for select using (auth.role() = 'authenticated');
create policy "items insert" on items for insert with check (is_app_admin() or has_perm('masters_edit'));
create policy "items update" on items for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "items delete" on items for delete using (is_app_admin());

-- ---------- warehouses ----------
drop policy if exists "warehouses select" on warehouses;
drop policy if exists "warehouses insert" on warehouses;
drop policy if exists "warehouses update" on warehouses;
drop policy if exists "warehouses delete" on warehouses;

create policy "warehouses select" on warehouses for select using (auth.role() = 'authenticated');
create policy "warehouses insert" on warehouses for insert with check (is_app_admin() or has_perm('masters_edit'));
create policy "warehouses update" on warehouses for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "warehouses delete" on warehouses for delete using (is_app_admin());

-- ---------- period_lock ----------
drop policy if exists "period_lock select" on period_lock;
drop policy if exists "period_lock update" on period_lock;

create policy "period_lock select" on period_lock for select using (auth.role() = 'authenticated');
create policy "period_lock update" on period_lock for update
  using (auth.role() = 'authenticated')
  with check (is_app_admin() or has_perm('period_lock'));

-- ---------- party_opening_balances ----------
drop policy if exists "party_opening_balances select" on party_opening_balances;
drop policy if exists "party_opening_balances write"  on party_opening_balances;

create policy "party_opening_balances select" on party_opening_balances for select using (auth.role() = 'authenticated');
create policy "party_opening_balances write"  on party_opening_balances for all
  using (is_app_admin() or has_perm('period_lock'))
  with check (is_app_admin() or has_perm('period_lock'));

-- ---------- item_cost_snapshot ----------
drop policy if exists "item_cost_snapshot select" on item_cost_snapshot;
drop policy if exists "item_cost_snapshot write"  on item_cost_snapshot;

create policy "item_cost_snapshot select" on item_cost_snapshot for select using (auth.role() = 'authenticated');
create policy "item_cost_snapshot write"  on item_cost_snapshot for all
  using (is_app_admin() or has_perm('period_lock'))
  with check (is_app_admin() or has_perm('period_lock'));

-- ---------- vouchers ----------
drop policy if exists "vouchers select" on vouchers;
drop policy if exists "vouchers insert" on vouchers;
drop policy if exists "vouchers update" on vouchers;
drop policy if exists "vouchers delete" on vouchers;

create policy "vouchers select" on vouchers for select using (auth.role() = 'authenticated');
create policy "vouchers insert" on vouchers for insert with check (is_app_admin() or has_perm('bill_create'));
create policy "vouchers update" on vouchers for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "vouchers delete" on vouchers for delete using (is_app_admin());

-- ---------- voucher_lines ----------
drop policy if exists "voucher_lines select" on voucher_lines;
drop policy if exists "voucher_lines insert" on voucher_lines;
drop policy if exists "voucher_lines update" on voucher_lines;
drop policy if exists "voucher_lines delete" on voucher_lines;

create policy "voucher_lines select" on voucher_lines for select using (auth.role() = 'authenticated');
create policy "voucher_lines insert" on voucher_lines for insert
  with check (is_app_admin() or has_perm('bill_create') or has_perm('bill_edit'));
create policy "voucher_lines update" on voucher_lines for update
  using (auth.role() = 'authenticated')
  with check (is_app_admin() or has_perm('bill_create') or has_perm('bill_edit'));
create policy "voucher_lines delete" on voucher_lines for delete
  using (is_app_admin() or has_perm('bill_create') or has_perm('bill_edit'));

-- ---------- sales_returns ----------
drop policy if exists "sales_returns select" on sales_returns;
drop policy if exists "sales_returns insert" on sales_returns;
drop policy if exists "sales_returns update" on sales_returns;
drop policy if exists "sales_returns delete" on sales_returns;

create policy "sales_returns select" on sales_returns for select using (auth.role() = 'authenticated');
create policy "sales_returns insert" on sales_returns for insert with check (is_app_admin() or has_perm('bill_create'));
create policy "sales_returns update" on sales_returns for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "sales_returns delete" on sales_returns for delete using (is_app_admin());

-- ---------- sales_return_lines ----------
drop policy if exists "sales_return_lines select" on sales_return_lines;
drop policy if exists "sales_return_lines write"  on sales_return_lines;

create policy "sales_return_lines select" on sales_return_lines for select using (auth.role() = 'authenticated');
create policy "sales_return_lines write"  on sales_return_lines for all
  using (is_app_admin() or has_perm('bill_create') or has_perm('bill_edit'))
  with check (is_app_admin() or has_perm('bill_create') or has_perm('bill_edit'));

-- ---------- quotations ----------
drop policy if exists "quotations select" on quotations;
drop policy if exists "quotations insert" on quotations;
drop policy if exists "quotations update" on quotations;
drop policy if exists "quotations delete" on quotations;

create policy "quotations select" on quotations for select using (auth.role() = 'authenticated');
create policy "quotations insert" on quotations for insert with check (is_app_admin() or has_perm('quotation_create'));
create policy "quotations update" on quotations for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "quotations delete" on quotations for delete using (is_app_admin());

-- ---------- quotation_lines ----------
drop policy if exists "quotation_lines select" on quotation_lines;
drop policy if exists "quotation_lines write"  on quotation_lines;

create policy "quotation_lines select" on quotation_lines for select using (auth.role() = 'authenticated');
create policy "quotation_lines write"  on quotation_lines for all
  using (is_app_admin() or has_perm('quotation_create') or has_perm('quotation_edit'))
  with check (is_app_admin() or has_perm('quotation_create') or has_perm('quotation_edit'));

-- ---------- purchase_orders ----------
drop policy if exists "po select" on purchase_orders;
drop policy if exists "po insert" on purchase_orders;
drop policy if exists "po update" on purchase_orders;
drop policy if exists "po delete" on purchase_orders;

create policy "po select" on purchase_orders for select using (auth.role() = 'authenticated');
create policy "po insert" on purchase_orders for insert with check (is_app_admin() or has_perm('po_create'));
create policy "po update" on purchase_orders for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "po delete" on purchase_orders for delete using (is_app_admin());

-- ---------- po_lines ----------
drop policy if exists "po_lines select" on po_lines;
drop policy if exists "po_lines write"  on po_lines;

create policy "po_lines select" on po_lines for select using (auth.role() = 'authenticated');
create policy "po_lines write"  on po_lines for all
  using (is_app_admin() or has_perm('po_create') or has_perm('po_edit'))
  with check (is_app_admin() or has_perm('po_create') or has_perm('po_edit'));

-- ---------- stock_transfers ----------
drop policy if exists "stock_transfers select" on stock_transfers;
drop policy if exists "stock_transfers insert" on stock_transfers;
drop policy if exists "stock_transfers update" on stock_transfers;
drop policy if exists "stock_transfers delete" on stock_transfers;

create policy "stock_transfers select" on stock_transfers for select using (auth.role() = 'authenticated');
create policy "stock_transfers insert" on stock_transfers for insert with check (is_app_admin() or has_perm('bill_create'));
create policy "stock_transfers update" on stock_transfers for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "stock_transfers delete" on stock_transfers for delete using (is_app_admin());

-- ---------- stock_transfer_lines ----------
drop policy if exists "stock_transfer_lines select" on stock_transfer_lines;
drop policy if exists "stock_transfer_lines write"  on stock_transfer_lines;

create policy "stock_transfer_lines select" on stock_transfer_lines for select using (auth.role() = 'authenticated');
create policy "stock_transfer_lines write"  on stock_transfer_lines for all
  using (is_app_admin() or has_perm('bill_create') or has_perm('bill_edit'))
  with check (is_app_admin() or has_perm('bill_create') or has_perm('bill_edit'));

-- ---------- stock_adjustments ----------
drop policy if exists "stock_adjustments select" on stock_adjustments;
drop policy if exists "stock_adjustments insert" on stock_adjustments;
drop policy if exists "stock_adjustments update" on stock_adjustments;
drop policy if exists "stock_adjustments delete" on stock_adjustments;

create policy "stock_adjustments select" on stock_adjustments for select using (auth.role() = 'authenticated');
create policy "stock_adjustments insert" on stock_adjustments for insert with check (is_app_admin() or has_perm('masters_edit'));
create policy "stock_adjustments update" on stock_adjustments for update
  using (is_app_admin() or has_perm('masters_edit'))
  with check (is_app_admin() or has_perm('masters_edit'));
create policy "stock_adjustments delete" on stock_adjustments for delete using (is_app_admin());

-- ---------- sheets (daily ledger) ----------
drop policy if exists "sheets select" on sheets;
drop policy if exists "sheets insert" on sheets;
drop policy if exists "sheets update" on sheets;
drop policy if exists "sheets delete" on sheets;

create policy "sheets select" on sheets for select using (auth.role() = 'authenticated');
create policy "sheets insert" on sheets for insert with check (is_app_admin() or has_perm('ledger_create'));
create policy "sheets update" on sheets for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "sheets delete" on sheets for delete using (is_app_admin());
