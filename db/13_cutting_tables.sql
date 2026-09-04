-- ============================================================
--  13 — Cutting / Processing: Transaction tables
-- ============================================================

-- ---------- Material Inward (party ka maal andar aana) ----------

create table if not exists material_inwards (
  id            uuid        not null default gen_random_uuid(),
  ino           text,                                   -- MI-0001
  idate         date        not null default current_date,
  party_id      uuid        not null,
  warehouse_id  uuid        not null,
  vehicle_no    text        default ''::text,
  gate_pass_no  text        default ''::text,           -- party ka challan / gate pass
  remarks       text        default ''::text,
  status        text        not null default 'active',  -- active | cancelled
  version       integer     not null default 1,
  created_at    timestamptz not null default now(),
  created_by    uuid,
  updated_at    timestamptz,
  updated_by    uuid,
  deleted_at    timestamptz
);

-- ---------- Coils ----------
--  ownership = 'party' → customer ka maal. Koi company asset nahi.
--                        party_id lazmi, item_id hona mana hai.
--  ownership = 'own'   → company ka apna maal, mojooda items se juda,
--                        normal valuation ke qawaid par chalta hai.
--                        item_id lazmi, party_id hona mana hai.
--
--  Balances trigger se maintain hote hain aur CHECK constraints
--  se mehfooz hain — do users ek saath coil se zyada maal nahi
--  nikaal sakte, kyunki rok database level par hai.

create table if not exists coils (
  id                    uuid        not null default gen_random_uuid(),
  coil_serial           text        not null,             -- CUT-2026-000154
  ownership             text        not null default 'party',
  party_id              uuid,
  item_id               uuid,
  inward_id             uuid,
  warehouse_id          uuid        not null,

  party_coil_ref        text        default ''::text,     -- party ka apna coil number
  material_type         text        default ''::text,
  grade                 text        default ''::text,
  thickness_mm          numeric,
  width_mm              numeric,

  received_weight       numeric     not null default 0,
  received_date         date        not null default current_date,

  -- trigger se maintain hone wale running totals
  consumed_weight       numeric     not null default 0,   -- cutting jobs mein gaya
  returned_weight       numeric     not null default 0,   -- raw wapas hua
  closing_adjust_weight numeric     not null default 0,   -- coil band karte waqt variance
  finished_weight       numeric     not null default 0,   -- jobs se bana hua maal
  delivered_weight      numeric     not null default 0,   -- challan se gaya

  raw_balance numeric generated always as
    (received_weight - consumed_weight - returned_weight - closing_adjust_weight) stored,
  pending_delivery numeric generated always as
    (finished_weight - delivered_weight) stored,

  status            text        not null default 'active', -- active | closed | cancelled
  closed_at         timestamptz,
  closed_by         uuid,
  closing_remarks   text,
  closing_reason    text,        -- weighbridge | scale | handling | leftover | scrap | other

  remarks     text        default ''::text,
  version     integer     not null default 1,
  created_at  timestamptz not null default now(),
  created_by  uuid,
  updated_at  timestamptz,
  updated_by  uuid,
  deleted_at  timestamptz
);

-- ---------- Cutting Job ----------
-- Yeh physical kaam ka record hai — bill NAHI. Bill Service Invoice hai.

create table if not exists cutting_jobs (
  id            uuid        not null default gen_random_uuid(),
  jno           text,                                    -- CJ-0001
  jdate         date        not null default current_date,
  party_id      uuid        not null,
  warehouse_id  uuid        not null,
  machine_id    uuid,
  operator_id   uuid,
  remarks       text        default ''::text,
  status        text        not null default 'draft',    -- draft | completed | cancelled
  completed_at  timestamptz,
  completed_by  uuid,
  version       integer     not null default 1,
  created_at    timestamptz not null default now(),
  created_by    uuid,
  updated_at    timestamptz,
  updated_by    uuid,
  deleted_at    timestamptz
);

-- Job mein kaun si coil se kitna maal gaya
create table if not exists cutting_job_inputs (
  id            uuid    not null default gen_random_uuid(),
  job_id        uuid    not null,
  coil_id       uuid    not null,
  input_weight  numeric not null default 0,
  line_no       integer not null default 0
);

-- Cutting sizes — structured rows (requirement 12)
-- coil_id is liye zaroori hai ke ek job mein kai coils ho sakti hain,
-- aur har coil ka finished weight alag track karna hai.
create table if not exists cutting_job_outputs (
  id             uuid    not null default gen_random_uuid(),
  job_id         uuid    not null,
  coil_id        uuid    not null,
  width_mm       numeric,
  pieces         numeric not null default 0,   -- qty / slits
  output_weight  numeric not null default 0,   -- ACTUAL tola hua weight
  remarks        text    default ''::text,
  line_no        integer not null default 0
);

-- ---------- Delivery Challan (maal party ko wapas) ----------

create table if not exists delivery_challans (
  id                  uuid        not null default gen_random_uuid(),
  dno                 text,                                  -- DC-0001
  ddate               date        not null default current_date,
  party_id            uuid        not null,
  warehouse_id        uuid        not null,
  vehicle_no          text        default ''::text,
  driver_name         text        default ''::text,
  weighbridge_slip_no text        default ''::text,
  remarks             text        default ''::text,
  status              text        not null default 'active',  -- active | cancelled
  version             integer     not null default 1,
  created_at          timestamptz not null default now(),
  created_by          uuid,
  updated_at          timestamptz,
  updated_by          uuid,
  deleted_at          timestamptz
);

-- expected_weight = job output ke mutabiq jo jana chahiye tha
-- delivered_weight = gaari/weighbridge par ACTUAL tola gaya
-- Farq "Weight Variance" hai — system isay KABHI khud scrap nahi banata.
create table if not exists delivery_challan_lines (
  id               uuid    not null default gen_random_uuid(),
  challan_id       uuid    not null,
  job_id           uuid,
  coil_id          uuid    not null,
  output_id        uuid,                          -- kaun si cutting size
  expected_weight  numeric not null default 0,
  delivered_weight numeric not null default 0,
  variance_kg numeric generated always as (delivered_weight - expected_weight) stored,
  variance_reason  text,   -- weighbridge | scale | handling | leftover | scrap | other
  remarks          text    default ''::text,
  line_no          integer not null default 0
);

-- ---------- Material Return (bina kata hua raw maal wapas) ----------

create table if not exists material_returns (
  id            uuid        not null default gen_random_uuid(),
  rno           text,                                   -- MR-0001
  rdate         date        not null default current_date,
  party_id      uuid        not null,
  warehouse_id  uuid        not null,
  vehicle_no    text        default ''::text,
  remarks       text        default ''::text,
  status        text        not null default 'active',  -- active | cancelled
  version       integer     not null default 1,
  created_at    timestamptz not null default now(),
  created_by    uuid,
  updated_at    timestamptz,
  updated_by    uuid,
  deleted_at    timestamptz
);

create table if not exists material_return_lines (
  id             uuid    not null default gen_random_uuid(),
  return_id      uuid    not null,
  coil_id        uuid    not null,
  return_weight  numeric not null default 0,
  remarks        text    default ''::text,
  line_no        integer not null default 0
);

-- ---------- Service Invoice (asal financial bill) ----------
-- Mojooda accounting engine hi istemaal hota hai: party ledger,
-- tax, receipts sab wohi. Sirf number series alag hai (SV-0001)
-- aur P&L mein revenue alag dikhta hai.

create table if not exists service_invoices (
  id           uuid        not null default gen_random_uuid(),
  sino         text,                                   -- SV-0001
  sidate       date        not null default current_date,
  party_id     uuid        not null,
  company_id   uuid,
  narration    text        default ''::text,
  sub_total    numeric     not null default 0,
  discount     numeric     not null default 0,
  tax_on       boolean     not null default false,
  tax_total    numeric     not null default 0,
  grand_total  numeric     not null default 0,
  paid         numeric     not null default 0,
  status       text        not null default 'active',  -- active | cancelled
  version      integer     not null default 1,
  created_at   timestamptz not null default now(),
  created_by   uuid,
  updated_at   timestamptz,
  updated_by   uuid,
  deleted_at   timestamptz
);

-- calc_method har line par alag ho sakta hai (requirement 24):
-- kg | ton | piece | meter | foot | cut | fixed
-- rate hamesha user likhta hai — kahin lock nahi hai (requirement 23).
create table if not exists service_invoice_lines (
  id                   uuid    not null default gen_random_uuid(),
  invoice_id           uuid    not null,
  service_category_id  uuid,
  description          text    default ''::text,
  calc_method          text    not null default 'kg',
  qty                  numeric not null default 0,
  rate                 numeric not null default 0,
  amount               numeric not null default 0,
  tax_pct              numeric not null default 0,
  remarks              text    default ''::text,
  line_no              integer not null default 0
);

-- Kaun se jobs is invoice par bill hue — dobara billing rokne ke liye
create table if not exists service_invoice_jobs (
  id          uuid not null default gen_random_uuid(),
  invoice_id  uuid not null,
  job_id      uuid not null
);

-- Kaun se challans is invoice se jure hain (optional reference)
create table if not exists service_invoice_challans (
  id          uuid not null default gen_random_uuid(),
  invoice_id  uuid not null,
  challan_id  uuid not null
);
