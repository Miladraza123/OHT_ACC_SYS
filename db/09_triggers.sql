-- ============================================================
--  09 — Triggers
--  Har table par teen tarah ke trigger lagte hain:
--    trg_audit_*   → created_by / updated_by / updated_at bharna
--    trg_log_*     → audit_log mein field-level diff likhna
--    trg_perm_*    → per-checkbox permission DB level par lagu karna
--    trg_version_* → version counter barhana (concurrent edit detection)
-- ============================================================

-- ---------- companies ----------
drop trigger if exists trg_audit_companies   on companies;
drop trigger if exists trg_log_companies     on companies;
drop trigger if exists trg_perm_companies    on companies;
drop trigger if exists trg_version_companies on companies;

create trigger trg_audit_companies   before insert or update           on companies for each row execute function stamp_audit_fields();
create trigger trg_log_companies     after  insert or update or delete on companies for each row execute function log_audit_event();
create trigger trg_perm_companies    before update                     on companies for each row execute function enforce_perm_on_update('masters_edit', 'masters_delete', 'recycle_bin');
create trigger trg_version_companies before update                     on companies for each row execute function bump_version();

-- ---------- parties ----------
drop trigger if exists trg_audit_parties   on parties;
drop trigger if exists trg_log_parties     on parties;
drop trigger if exists trg_perm_parties    on parties;
drop trigger if exists trg_version_parties on parties;

create trigger trg_audit_parties   before insert or update           on parties for each row execute function stamp_audit_fields();
create trigger trg_log_parties     after  insert or update or delete on parties for each row execute function log_audit_event();
create trigger trg_perm_parties    before update                     on parties for each row execute function enforce_perm_on_update('masters_edit', 'masters_delete', 'recycle_bin');
create trigger trg_version_parties before update                     on parties for each row execute function bump_version();

-- ---------- items ----------
drop trigger if exists trg_audit_items   on items;
drop trigger if exists trg_log_items     on items;
drop trigger if exists trg_perm_items    on items;
drop trigger if exists trg_version_items on items;

create trigger trg_audit_items   before insert or update           on items for each row execute function stamp_audit_fields();
create trigger trg_log_items     after  insert or update or delete on items for each row execute function log_audit_event();
create trigger trg_perm_items    before update                     on items for each row execute function enforce_perm_on_update('masters_edit', 'masters_delete', 'recycle_bin');
create trigger trg_version_items before update                     on items for each row execute function bump_version();

-- ---------- warehouses ----------
drop trigger if exists trg_audit_warehouses on warehouses;
drop trigger if exists trg_log_warehouses   on warehouses;
drop trigger if exists trg_perm_warehouses  on warehouses;

create trigger trg_audit_warehouses before insert or update           on warehouses for each row execute function stamp_audit_fields();
create trigger trg_log_warehouses   after  insert or update or delete on warehouses for each row execute function log_audit_event();
create trigger trg_perm_warehouses  before update                     on warehouses for each row execute function enforce_perm_on_update('masters_edit', 'masters_delete', 'recycle_bin');

-- ---------- vouchers ----------
drop trigger if exists trg_assign_voucher_number on vouchers;
drop trigger if exists trg_audit_vouchers        on vouchers;
drop trigger if exists trg_log_vouchers          on vouchers;
drop trigger if exists trg_period_lock_vouchers  on vouchers;
drop trigger if exists trg_perm_vouchers         on vouchers;
drop trigger if exists trg_version_vouchers      on vouchers;
drop trigger if exists trg_cost_on_voucher       on vouchers;

create trigger trg_assign_voucher_number before insert                     on vouchers for each row execute function assign_voucher_number();
create trigger trg_audit_vouchers        before insert or update           on vouchers for each row execute function stamp_audit_fields();
create trigger trg_log_vouchers          after  insert or update or delete on vouchers for each row execute function log_audit_event();
create trigger trg_period_lock_vouchers  before insert or update or delete on vouchers for each row execute function check_period_lock_vouchers();
create trigger trg_perm_vouchers         before update                     on vouchers for each row execute function enforce_perm_on_update('bill_edit', 'bill_delete', 'recycle_bin');
create trigger trg_version_vouchers      before update                     on vouchers for each row execute function bump_version();
create trigger trg_cost_on_voucher       after  update                     on vouchers for each row execute function trg_recompute_cost_on_voucher();

-- ---------- voucher_lines ----------
-- Bill ki line badalte hi us item ka weighted-average cost aur
-- stock_qty dobara ginn jate hain. (Hard delete par voucher_lines
-- cascade se urhti hain, jis se yahi trigger chal kar hisaab theek kar deta hai.)
drop trigger if exists trg_cost_on_lines on voucher_lines;

create trigger trg_cost_on_lines after insert or update or delete on voucher_lines for each row execute function trg_recompute_cost_on_line();

-- ---------- sales_returns ----------
drop trigger if exists trg_audit_sales_returns on sales_returns;
drop trigger if exists trg_log_sales_returns   on sales_returns;
drop trigger if exists trg_perm_sales_returns  on sales_returns;
drop trigger if exists trg_cost_on_return      on sales_returns;

create trigger trg_audit_sales_returns before insert or update           on sales_returns for each row execute function stamp_audit_fields();
create trigger trg_log_sales_returns   after  insert or update or delete on sales_returns for each row execute function log_audit_event();
create trigger trg_perm_sales_returns  before update                     on sales_returns for each row execute function enforce_perm_on_update('bill_edit', 'bill_delete', 'recycle_bin');
create trigger trg_cost_on_return      after  update                     on sales_returns for each row execute function trg_recompute_cost_on_return();

-- ---------- sales_return_lines ----------
drop trigger if exists trg_returnable_qty         on sales_return_lines;
drop trigger if exists trg_stamp_return_line_cost on sales_return_lines;
drop trigger if exists trg_cost_on_return_lines   on sales_return_lines;

create trigger trg_returnable_qty         before insert or update           on sales_return_lines for each row execute function trg_check_returnable_qty();
create trigger trg_stamp_return_line_cost before insert or update           on sales_return_lines for each row execute function stamp_return_line_cost();
create trigger trg_cost_on_return_lines   after  insert or update or delete on sales_return_lines for each row execute function trg_recompute_cost_on_return_line();

-- ---------- quotations ----------
drop trigger if exists trg_audit_quotations on quotations;
drop trigger if exists trg_log_quotations   on quotations;
drop trigger if exists trg_perm_quotations  on quotations;

create trigger trg_audit_quotations before insert or update           on quotations for each row execute function stamp_audit_fields();
create trigger trg_log_quotations   after  insert or update or delete on quotations for each row execute function log_audit_event();
create trigger trg_perm_quotations  before update                     on quotations for each row execute function enforce_perm_on_update('quotation_edit', 'quotation_delete', 'recycle_bin');

-- ---------- purchase_orders ----------
drop trigger if exists trg_audit_po            on purchase_orders;
drop trigger if exists trg_log_purchase_orders on purchase_orders;
drop trigger if exists trg_perm_po             on purchase_orders;

create trigger trg_audit_po            before insert or update           on purchase_orders for each row execute function stamp_audit_fields();
create trigger trg_log_purchase_orders after  insert or update or delete on purchase_orders for each row execute function log_audit_event();
create trigger trg_perm_po             before update                     on purchase_orders for each row execute function enforce_perm_on_update('po_edit', 'po_delete', 'recycle_bin');

-- ---------- stock_transfers ----------
drop trigger if exists trg_audit_stock_transfers on stock_transfers;
drop trigger if exists trg_log_stock_transfers   on stock_transfers;
drop trigger if exists trg_perm_stock_transfers  on stock_transfers;

create trigger trg_audit_stock_transfers before insert or update           on stock_transfers for each row execute function stamp_audit_fields();
create trigger trg_log_stock_transfers   after  insert or update or delete on stock_transfers for each row execute function log_audit_event();
create trigger trg_perm_stock_transfers  before update                     on stock_transfers for each row execute function enforce_perm_on_update('bill_edit', 'bill_delete', 'recycle_bin');

-- ---------- sheets (daily ledger) ----------
drop trigger if exists trg_audit_sheets       on sheets;
drop trigger if exists trg_period_lock_sheets on sheets;
drop trigger if exists trg_perm_sheets        on sheets;

create trigger trg_audit_sheets       before insert or update           on sheets for each row execute function stamp_audit_fields();
create trigger trg_period_lock_sheets before insert or update or delete on sheets for each row execute function check_period_lock_sheets();
create trigger trg_perm_sheets        before update                     on sheets for each row execute function enforce_perm_on_update('ledger_create', 'ledger_delete', 'recycle_bin');

-- ---------- period_lock ----------
drop trigger if exists trg_invalidate_opening_balances on period_lock;

create trigger trg_invalidate_opening_balances
  after update on period_lock
  for each row
  when (old.locked_before is distinct from new.locked_before)
  execute function invalidate_opening_balances();
