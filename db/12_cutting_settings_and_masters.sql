-- ============================================================
--  12 — Cutting / Processing: Settings, Masters & Sequences
-- ============================================================

-- ---------- Number series (concurrency-safe) ----------
-- Postgres sequences istemaal kiye gaye hain — do users ek saath
-- document banayein tab bhi number kabhi dohraya nahi ja sakta.

create sequence if not exists mi_seq   start with 1 increment by 1;  -- Material Inward
create sequence if not exists coil_seq start with 1 increment by 1;  -- Coil serial
create sequence if not exists cj_seq   start with 1 increment by 1;  -- Cutting Job
create sequence if not exists sv_seq   start with 1 increment by 1;  -- Service Invoice
create sequence if not exists dc_seq   start with 1 increment by 1;  -- Delivery Challan
create sequence if not exists mr_seq   start with 1 increment by 1;  -- Material Return

-- ---------- Cutting Settings (single row, id = 1) ----------

create table if not exists cutting_settings (
  id                       integer     not null default 1,
  coil_finish_threshold_kg numeric     not null default 200,
  coil_serial_prefix       text        not null default 'CUT',
  inward_prefix            text        not null default 'MI',
  job_prefix               text        not null default 'CJ',
  service_invoice_prefix   text        not null default 'SV',
  challan_prefix           text        not null default 'DC',
  return_prefix            text        not null default 'MR',
  updated_at               timestamptz not null default now(),
  updated_by               uuid
);

-- ---------- Machines ----------

create table if not exists machines (
  id          uuid        not null default gen_random_uuid(),
  name        text        not null,
  notes       text        default ''::text,
  active      boolean     not null default true,
  version     integer     not null default 1,
  created_at  timestamptz not null default now(),
  created_by  uuid,
  updated_at  timestamptz,
  updated_by  uuid,
  deleted_at  timestamptz
);

-- ---------- Operators / Cutters ----------

create table if not exists operators (
  id          uuid        not null default gen_random_uuid(),
  name        text        not null,
  phone       text        default ''::text,
  notes       text        default ''::text,
  active      boolean     not null default true,
  version     integer     not null default 1,
  created_at  timestamptz not null default now(),
  created_by  uuid,
  updated_at  timestamptz,
  updated_by  uuid,
  deleted_at  timestamptz
);

-- ---------- Service Categories ----------
-- User khud add/edit kar sakta hai. Rate YAHAN LOCK NAHI HOTA —
-- last_rate sirf tajweez ke liye hai, invoice par rate hamesha
-- user apni marzi se daal sakta hai (requirement 23).

create table if not exists service_categories (
  id                  uuid        not null default gen_random_uuid(),
  name                text        not null,
  default_calc_method text        not null default 'kg',
  last_rate           numeric,     -- sirf tajweez, majboori nahi
  notes               text        default ''::text,
  active              boolean     not null default true,
  version             integer     not null default 1,
  created_at          timestamptz not null default now(),
  created_by          uuid,
  updated_at          timestamptz,
  updated_by          uuid,
  deleted_at          timestamptz
);

-- ---------- Own Stock: Coil / Sheet / General ----------
-- Mojooda items table hi istemaal hoti hai (koi doosra inventory
-- engine nahi banaya gaya). Yeh column sirf Own Stock ko teen
-- views mein baantne ke liye hai: Coil Inventory, Sheet Inventory,
-- aur General Inventory.

alter table items add column if not exists item_form text not null default 'general';

alter table items drop constraint if exists items_item_form_check;
alter table items add constraint items_item_form_check
  check (item_form in ('coil', 'sheet', 'general'));
