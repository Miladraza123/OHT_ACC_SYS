-- ============================================================
--  02 — Tables
--  Foreign keys yahan nahi hain — wo 03_constraints.sql mein hain,
--  taake table banane ki tarteeb se koi masla na aaye.
-- ============================================================

-- ---------- Users & audit ----------

create table if not exists app_users (
  id          uuid        not null,
  username    text        not null,
  is_admin    boolean     not null default false,
  is_active   boolean     not null default true,
  perms       jsonb       not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create table if not exists audit_log (
  id            uuid        not null default gen_random_uuid(),
  table_name    text        not null,
  record_id     uuid,
  record_label  text,
  action        text        not null,
  changed_by    uuid,
  changed_at    timestamptz not null default now(),
  changes       jsonb
);

-- ---------- Masters ----------

create table if not exists companies (
  id          uuid        not null default gen_random_uuid(),
  name        text        not null,
  address     text        default ''::text,
  city        text        default ''::text,
  phone       text        default ''::text,
  email       text        default ''::text,
  ntn         text        default ''::text,
  strn        text        default ''::text,
  logo        text        default ''::text,
  is_default  boolean     not null default false,
  notes       text        default ''::text,
  active      boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     integer     not null default 1,
  created_by  uuid,
  updated_by  uuid
);

create table if not exists parties (
  id            uuid        not null default gen_random_uuid(),
  name          text        not null,
  kind          text        not null default 'customer'::text,
  phone         text        default ''::text,
  city          text        default ''::text,
  address       text        default ''::text,
  ntn           text        default ''::text,
  opening       numeric     not null default 0,
  opening_side  text        not null default 'dr'::text,
  notes         text        default ''::text,
  active        boolean     not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  version       integer     not null default 1,
  created_by    uuid,
  updated_by    uuid,
  expense_type  text
);

create table if not exists party_kinds (
  id          uuid        not null default gen_random_uuid(),
  value       text        not null,
  label       text        not null,
  created_at  timestamptz default now()
);

create table if not exists items (
  id             uuid        not null default gen_random_uuid(),
  name           text        not null,
  unit           text        not null default 'pcs'::text,
  sale_rate      numeric     not null default 0,
  buy_rate       numeric     not null default 0,
  tax_pct        numeric     not null default 0,
  opening_qty    numeric     not null default 0,
  opening_rate   numeric     not null default 0,
  hs_code        text        default ''::text,
  notes          text        default ''::text,
  active         boolean     not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  reorder_level  numeric     not null default 0,
  deleted_at     timestamptz,
  version        integer     not null default 1,
  created_by     uuid,
  updated_by     uuid,
  avg_cost       numeric     not null default 0,
  stock_qty      numeric     not null default 0
);

create table if not exists warehouses (
  id          uuid        not null default gen_random_uuid(),
  name        text        not null,
  city        text,
  active      boolean     not null default true,
  is_default  boolean     not null default false,
  version     integer     not null default 1,
  created_by  uuid,
  updated_by  uuid,
  updated_at  timestamptz,
  deleted_at  timestamptz
);

-- ---------- Accounting config ----------

create table if not exists period_lock (
  id             integer not null default 1,
  locked_before  date
);

create table if not exists party_opening_balances (
  party_id       uuid        not null,
  as_of_date     date        not null,
  balance        numeric     not null default 0,
  computed_at    timestamptz not null default now(),
  last_txn_date  date
);

create table if not exists item_cost_snapshot (
  item_id      uuid        not null,
  as_of_date   date        not null,
  avg_cost     numeric     not null default 0,
  stock_qty    numeric     not null default 0,
  computed_at  timestamptz not null default now()
);

-- ---------- Vouchers (Sale / Purchase) ----------

create table if not exists vouchers (
  id           uuid        not null default gen_random_uuid(),
  vtype        text        not null,
  vno          text        not null default ''::text,
  vdate        date        not null default current_date,
  party_id     uuid,
  narration    text        default ''::text,
  tax_on       boolean     not null default false,
  sub_total    numeric     not null default 0,
  discount     numeric     not null default 0,
  tax_total    numeric     not null default 0,
  grand_total  numeric     not null default 0,
  paid         numeric     not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   uuid,
  company_id   uuid,
  deleted_at   timestamptz,
  version      integer     not null default 1,
  created_by   uuid,
  loading_on   boolean     not null default false,
  loading_amt  numeric     not null default 0,
  cartage_on   boolean     not null default false,
  cartage_amt  numeric     not null default 0,
  cutting_on   boolean     not null default false,
  cutting_amt  numeric     not null default 0
);

create table if not exists voucher_lines (
  id            uuid    not null default gen_random_uuid(),
  voucher_id    uuid    not null,
  line_no       integer not null default 1,
  item_id       uuid,
  qty           numeric not null default 0,
  rate          numeric not null default 0,
  tax_pct       numeric not null default 0,
  amount        numeric not null default 0,
  cost_amount   numeric,
  pcs_on        boolean not null default false,
  pcs           numeric,
  warehouse_id  uuid
);

-- ---------- Sales Returns ----------

create table if not exists sales_returns (
  id           uuid        not null default gen_random_uuid(),
  rno          text,
  sale_id      uuid,
  party_id     uuid,
  rdate        date        not null default current_date,
  narration    text,
  subtotal     numeric     not null default 0,
  grand_total  numeric     not null default 0,
  version      integer     not null default 1,
  created_by   uuid,
  updated_by   uuid,
  updated_at   timestamptz,
  deleted_at   timestamptz
);

create table if not exists sales_return_lines (
  id            uuid    not null default gen_random_uuid(),
  return_id     uuid,
  sale_line_id  uuid,
  item_id       uuid,
  qty           numeric not null default 0,
  rate          numeric not null default 0,
  amount        numeric not null default 0,
  cost_amount   numeric not null default 0,
  line_no       integer not null default 0,
  warehouse_id  uuid
);

-- ---------- Quotations ----------

create table if not exists quotations (
  id           uuid        not null default gen_random_uuid(),
  qno          text,
  party_id     uuid,
  qdate        date        not null default current_date,
  company_id   uuid,
  narration    text,
  subtotal     numeric     not null default 0,
  tax_on       boolean     not null default false,
  discount     numeric     not null default 0,
  tax_total    numeric     not null default 0,
  grand_total  numeric     not null default 0,
  version      integer     not null default 1,
  created_by   uuid,
  updated_by   uuid,
  updated_at   timestamptz,
  deleted_at   timestamptz,
  loading_on   boolean     not null default false,
  loading_amt  numeric     not null default 0,
  cartage_on   boolean     not null default false,
  cartage_amt  numeric     not null default 0,
  cutting_on   boolean     not null default false,
  cutting_amt  numeric     not null default 0
);

create table if not exists quotation_lines (
  id            uuid    not null default gen_random_uuid(),
  quotation_id  uuid,
  item_id       uuid,
  qty           numeric not null default 0,
  rate          numeric not null default 0,
  amount        numeric not null default 0,
  line_no       integer not null default 0,
  tax_pct       numeric not null default 0,
  pcs_on        boolean not null default false,
  pcs           numeric
);

-- ---------- Purchase Orders ----------

create table if not exists purchase_orders (
  id           uuid        not null default gen_random_uuid(),
  pono         text,
  party_id     uuid,
  podate       date        not null default current_date,
  company_id   uuid,
  narration    text,
  subtotal     numeric     not null default 0,
  tax_on       boolean     not null default false,
  discount     numeric     not null default 0,
  tax_total    numeric     not null default 0,
  grand_total  numeric     not null default 0,
  version      integer     not null default 1,
  created_by   uuid,
  updated_by   uuid,
  updated_at   timestamptz,
  deleted_at   timestamptz
);

create table if not exists po_lines (
  id       uuid    not null default gen_random_uuid(),
  po_id    uuid,
  item_id  uuid,
  qty      numeric not null default 0,
  rate     numeric not null default 0,
  amount   numeric not null default 0,
  line_no  integer not null default 0,
  tax_pct  numeric not null default 0,
  pcs_on   boolean not null default false,
  pcs      numeric
);

-- ---------- Stock movement ----------

create table if not exists stock_transfers (
  id              uuid        not null default gen_random_uuid(),
  tno             text,
  tdate           date        not null default current_date,
  from_warehouse  uuid,
  to_warehouse    uuid,
  narration       text,
  version         integer     not null default 1,
  created_by      uuid,
  updated_by      uuid,
  updated_at      timestamptz,
  deleted_at      timestamptz
);

create table if not exists stock_transfer_lines (
  id           uuid    not null default gen_random_uuid(),
  transfer_id  uuid,
  item_id      uuid,
  qty          numeric not null,
  line_no      integer not null default 0
);

create table if not exists stock_adjustments (
  id            uuid        not null default gen_random_uuid(),
  item_id       uuid        not null,
  adj_date      date        not null default current_date,
  qty           numeric     not null default 0,
  reason        text        default ''::text,
  created_at    timestamptz not null default now(),
  updated_by    uuid,
  warehouse_id  uuid
);

-- ---------- Daily Ledger ----------

create table if not exists sheets (
  id          uuid        not null default gen_random_uuid(),
  sheet_date  date        not null,
  firm        text        default ''::text,
  opening     text        default ''::text,
  side        text        default 'cr'::text,
  page        text        default ''::text,
  rows        jsonb       not null default '[]'::jsonb,
  updated_by  uuid,
  updated_at  timestamptz not null default now(),
  version     integer     not null default 1,
  deleted_at  timestamptz,
  created_by  uuid
);
