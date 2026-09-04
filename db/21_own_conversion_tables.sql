-- ============================================================
--  21 — Own Stock Conversion (Own Cutting / Processing)
--
--  Company ka apna maal: Coil → Sheet / Strip / doosri size.
--  Yeh Sale ya Purchase nahi hai. Koi revenue, koi profit nahi.
--  Sirf inventory ki shakal badalti hai aur cost saath transfer hoti hai:
--
--      Raw Coil stock  ↓   (cost bahar)
--      Finished stock  ↑   (wohi cost andar)
--
--  Total inventory value barabar rehti hai — siwaye is ke ke user
--  alag se conversion cost daale (labour, bijli waghera), jo output
--  ke cost mein jama ho jati hai.
--
--  Party ka cutting is se bilkul alag hai (cutting_jobs) — us mein
--  koi valuation hoti hi nahi kyunki maal company ka hai hi nahi.
-- ============================================================

create sequence if not exists cv_seq start with 1 increment by 1;

alter table cutting_settings add column if not exists conversion_prefix text not null default 'CV';

-- ---------- Header ----------

create table if not exists stock_conversions (
  id               uuid        not null default gen_random_uuid(),
  cno              text,                                   -- CV-0001
  cdate            date        not null default current_date,
  warehouse_id     uuid,
  conversion_cost  numeric     not null default 0,         -- labour/bijli — output cost mein jama hoti hai
  narration        text        default ''::text,
  status           text        not null default 'active',  -- active | cancelled
  version          integer     not null default 1,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  updated_at       timestamptz,
  updated_by       uuid,
  deleted_at       timestamptz
);

-- ---------- Input: jo maal kharch hua ----------
-- cost_amount costing engine KHUD bharta hai — us waqt ke weighted
-- average par, bilkul waise jaise sale line par bharta hai.

create table if not exists stock_conversion_inputs (
  id             uuid    not null default gen_random_uuid(),
  conversion_id  uuid    not null,
  item_id        uuid    not null,
  coil_id        uuid,                      -- agar own coil-wise track ho rahi ho
  qty            numeric not null default 0,
  cost_amount    numeric not null default 0,   -- engine bharta hai
  remarks        text    default ''::text,
  line_no        integer not null default 0
);

-- ---------- Output: jo maal bana ----------
-- cost_amount inputs se allocate hoti hai, output weight ke tanasub se.

create table if not exists stock_conversion_outputs (
  id             uuid    not null default gen_random_uuid(),
  conversion_id  uuid    not null,
  item_id        uuid    not null,
  qty            numeric not null default 0,
  cost_amount    numeric not null default 0,   -- allocate hoti hai
  width_mm       numeric,
  pieces         numeric,
  remarks        text    default ''::text,
  line_no        integer not null default 0
);

-- ============================================================
--  Constraints
-- ============================================================

alter table stock_conversions        add constraint stock_conversions_pkey        primary key (id);
alter table stock_conversion_inputs  add constraint stock_conversion_inputs_pkey  primary key (id);
alter table stock_conversion_outputs add constraint stock_conversion_outputs_pkey primary key (id);

alter table stock_conversions add constraint stock_conversions_status_check
  check (status in ('active', 'cancelled'));
alter table stock_conversions add constraint stock_conversions_cost_nonneg
  check (conversion_cost >= 0);

alter table stock_conversion_inputs  add constraint stock_conversion_inputs_qty_pos  check (qty > 0);
alter table stock_conversion_outputs add constraint stock_conversion_outputs_qty_pos check (qty > 0);

alter table stock_conversions add constraint stock_conversions_warehouse_fkey foreign key (warehouse_id) references warehouses(id);
alter table stock_conversions add constraint stock_conversions_created_by_fkey foreign key (created_by) references app_users(id);
alter table stock_conversions add constraint stock_conversions_updated_by_fkey foreign key (updated_by) references app_users(id);

alter table stock_conversion_inputs add constraint stock_conversion_inputs_conv_fkey
  foreign key (conversion_id) references stock_conversions(id) on delete cascade;
alter table stock_conversion_inputs add constraint stock_conversion_inputs_item_fkey foreign key (item_id) references items(id);
alter table stock_conversion_inputs add constraint stock_conversion_inputs_coil_fkey foreign key (coil_id) references coils(id);

alter table stock_conversion_outputs add constraint stock_conversion_outputs_conv_fkey
  foreign key (conversion_id) references stock_conversions(id) on delete cascade;
alter table stock_conversion_outputs add constraint stock_conversion_outputs_item_fkey foreign key (item_id) references items(id);

create unique index if not exists stock_conversions_no_uniq
  on stock_conversions (lower(trim(both from cno))) where cno is not null and trim(both from cno) <> '';

create index if not exists stock_conversions_date_idx    on stock_conversions (cdate desc);
create index if not exists stock_conversions_active_idx  on stock_conversions (status) where deleted_at is null;
create index if not exists sc_inputs_conv_idx            on stock_conversion_inputs  (conversion_id);
create index if not exists sc_inputs_item_idx            on stock_conversion_inputs  (item_id);
create index if not exists sc_inputs_coil_idx            on stock_conversion_inputs  (coil_id);
create index if not exists sc_outputs_conv_idx           on stock_conversion_outputs (conversion_id);
create index if not exists sc_outputs_item_idx           on stock_conversion_outputs (item_id);
