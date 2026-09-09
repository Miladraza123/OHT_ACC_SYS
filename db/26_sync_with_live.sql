-- ============================================================
--  26 — Live database ke saath milaan (9 September 2026)
--
--  Yeh file production (OHT_Acc_Sys_QTC) se seedha parh kar banai gayi
--  hai. Waqt ke saath kuch cheezein Supabase par to add ho gayin magar
--  in SQL files mein likhi nahi gayin. Nateeja: agar koi in files se
--  naya database banata to wo asal system se mel nahi khata — aur backup
--  se restore wahan kabhi kaam na karta.
--
--  Sab se aakhir mein chalayein — 25 ke baad.
--  Har cheez "if not exists" / "or replace" hai, is liye ek se zyada
--  dafa chalane se koi nuqsan nahi.
-- ============================================================


-- ============================================================
--  HISSA 1 — item_units
--
--  Ek cheez ek se zyada unit mein bik sakti hai. Misal: sariya "kg" mein
--  rakha jata hai magar bikta "ton" mein hai. Yeh table har item ke liye
--  wo doosri units aur unka factor rakhti hai (1 ton = 1000 kg).
--
--  Yeh table in files mein bilkul thi hi nahi, jabke Masters aur Billing
--  dono ise istemaal karti hain — aur roz ka backup bhi.
-- ============================================================

create table if not exists item_units (
  id          uuid        not null default gen_random_uuid(),
  item_id     uuid        not null,
  unit        text        not null,
  factor      numeric     not null,       -- 1 sale-unit = kitni base unit
  rate        numeric,                    -- is unit ka apna rate (marzi)
  is_default  boolean     not null default false,
  line_no     integer     not null default 0,
  created_at  timestamptz not null default now(),
  created_by  uuid,
  updated_at  timestamptz,
  updated_by  uuid
);

do $$ begin
  alter table item_units add constraint item_units_pkey primary key (id);
exception when duplicate_table or duplicate_object or invalid_table_definition then null; end $$;

do $$ begin
  alter table item_units add constraint item_units_item_fkey
    foreign key (item_id) references items(id) on delete cascade;
exception when duplicate_object then null; end $$;

do $$ begin
  alter table item_units add constraint item_units_created_by_fkey
    foreign key (created_by) references app_users(id);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table item_units add constraint item_units_updated_by_fkey
    foreign key (updated_by) references app_users(id);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table item_units add constraint item_units_factor_pos check (factor > 0);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table item_units add constraint item_units_rate_nonneg
    check (rate is null or rate >= 0);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table item_units add constraint item_units_unit_required
    check (trim(unit) <> '');
exception when duplicate_object then null; end $$;

create index if not exists item_units_item_idx on item_units (item_id);

-- Ek item mein ek hi unit do dafa na aaye — "Ton" aur "ton" ek hi cheez hai
create unique index if not exists item_units_uniq
  on item_units (item_id, lower(trim(unit)));

-- Har item ka default unit sirf ek ho sakta hai
create unique index if not exists item_units_one_default
  on item_units (item_id) where is_default;

alter table item_units enable row level security;

drop policy if exists "item_units select" on item_units;
drop policy if exists "item_units write"  on item_units;

create policy "item_units select" on item_units for select
  using (auth.role() = 'authenticated');
create policy "item_units write"  on item_units for all
  using      (is_app_admin() or has_perm('masters_edit'))
  with check (is_app_admin() or has_perm('masters_edit'));

drop trigger if exists trg_audit_item_units on item_units;
create trigger trg_audit_item_units before insert or update on item_units
  for each row execute function stamp_audit_fields();


-- ============================================================
--  HISSA 2 — Jo columns baad mein add hue
--
--  Yeh sab production mein mojood hain. "if not exists" is liye hai ke
--  agar koi column pehle se ho to kuch na ho.
-- ============================================================

-- Party: udhaar ke din, aur opening balance kis tareekh ka hai
alter table parties add column if not exists opening_date date;
alter table parties add column if not exists credit_days  integer not null default 0;

do $$ begin
  alter table parties add constraint parties_credit_days_check check (credit_days >= 0);
exception when duplicate_object then null; end $$;

-- Bill ki due date — aging report isi par chalti hai
alter table vouchers add column if not exists due_date date;

/* Cheez kisi doosri unit mein bhi bik sakti hai. Bill par wohi qty aur
   unit chapte hain jo user ne likhe (sale_qty / sale_unit); stock hamesha
   base unit mein chalta hai. unit_factor dono ko jorta hai. */
alter table voucher_lines add column if not exists sale_unit   text;
alter table voucher_lines add column if not exists sale_qty    numeric;
alter table voucher_lines add column if not exists unit_factor numeric not null default 1;

do $$ begin
  alter table voucher_lines add constraint voucher_lines_factor_pos check (unit_factor > 0);
exception when duplicate_object then null; end $$;

-- Sales return par bhi wahi baat — wapsi usi unit mein hoti hai jis mein bika tha
alter table sales_return_lines add column if not exists sale_unit   text;
alter table sales_return_lines add column if not exists sale_qty    numeric;
alter table sales_return_lines add column if not exists unit_factor numeric not null default 1;

do $$ begin
  alter table sales_return_lines add constraint sales_return_lines_factor_pos
    check (unit_factor > 0);
exception when duplicate_object then null; end $$;

-- Cutting job ka output: lambai aur naap ki unit
alter table cutting_job_outputs add column if not exists length    numeric;
alter table cutting_job_outputs add column if not exists size_unit text not null default 'mm';

do $$ begin
  alter table cutting_job_outputs add constraint cutting_job_outputs_unit_check
    check (size_unit in ('mm', 'ft', 'inch'));
exception when duplicate_object then null; end $$;

/* Delivery aur balance ki tolerance. Weighbridge ka wazan hamesha thora
   aage peeche hota hai — yeh teen number tay karte hain ke kitna farq
   qabool hai aur kahan system rok de. */
alter table cutting_settings add column if not exists delivery_variance_pct    numeric not null default 1;
alter table cutting_settings add column if not exists delivery_variance_min_kg numeric not null default 25;
alter table cutting_settings add column if not exists balance_tolerance_pct    numeric not null default 10;

do $$ begin
  alter table cutting_settings add constraint cutting_settings_var_pct_check
    check (delivery_variance_pct >= 0 and delivery_variance_pct <= 100);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table cutting_settings add constraint cutting_settings_var_min_check
    check (delivery_variance_min_kg >= 0);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table cutting_settings add constraint cutting_settings_tol_check
    check (balance_tolerance_pct >= 0 and balance_tolerance_pct <= 100);
exception when duplicate_object then null; end $$;

-- Purani coil constraints — production se hata di gayin thin, yahan se bhi
-- (wajah 14 wali file mein likhi hai)
alter table coils drop constraint if exists coils_raw_balance_nonneg;
alter table coils drop constraint if exists coils_pending_delivery_nonneg;


-- ============================================================
--  HISSA 3 — Jo functions kahin likhi hi nahi gayin
-- ============================================================

/* Item ka opening qty ya rate badle to us ki poori costing dobara. */
create or replace function public.trg_recompute_on_item()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform recompute_item_cost(NEW.id);
  return NEW;
end;
$function$;

/* Stock adjustment se bhi average cost hilti hai. Item badal diya jaye to
   purane aur naye — dono ki costing dobara chalti hai. */
create or replace function public.trg_recompute_on_adjust()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if TG_OP = 'DELETE' then
    perform recompute_item_cost(OLD.item_id);
    return OLD;
  end if;
  perform recompute_item_cost(NEW.item_id);
  if TG_OP = 'UPDATE' and OLD.item_id is distinct from NEW.item_id then
    perform recompute_item_cost(OLD.item_id);
  end if;
  return NEW;
end;
$function$;

/* Coil se us se zyada maal nahi nikal sakta jitna aaya tha.
   Sakhti bilkul theek nahi hai — weighbridge ka wazan hamesha thora aage
   peeche hota hai. Is liye cutting_settings ki tolerance dekhi jati hai:
   received ka kuch percent, ya kam se kam itne KG — jo bara ho. */
create or replace function public.trg_check_coil_limits()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  pct    numeric;
  min_kg numeric;
  tol    numeric;
  raw_b  numeric;
  phy_b  numeric;
begin
  select coalesce(balance_tolerance_pct, 10), coalesce(delivery_variance_min_kg, 25)
    into pct, min_kg
    from cutting_settings where id = 1;
  if pct    is null then pct    := 10; end if;
  if min_kg is null then min_kg := 25; end if;

  tol := greatest(coalesce(NEW.received_weight, 0) * pct / 100, min_kg);

  raw_b := NEW.received_weight - NEW.consumed_weight - NEW.returned_weight;
  phy_b := NEW.received_weight - NEW.delivered_weight - NEW.returned_weight
             - NEW.closing_adjust_weight;

  if raw_b < -tol then
    raise exception 'Coil % par itna maal tha hi nahi — bina kata balance % KG manfi ja raha hai (hadd % KG). Number dobara dekh lein.',
      NEW.coil_serial, round(-raw_b, 3), round(tol, 3);
  end if;

  if phy_b < -tol then
    raise exception 'Coil % se us se zyada maal nikal raha hai jitna party ne diya tha — % KG manfi (hadd % KG). Number dobara dekh lein.',
      NEW.coil_serial, round(-phy_b, 3), round(tol, 3);
  end if;

  return NEW;
end;
$function$;

/* Adhoore job ka maal delivery par nahi ja sakta. Pehle job Completed ho,
   phir challan bane. */
create or replace function public.trg_check_delivery_job()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare j record;
begin
  if NEW.job_id is null then return NEW; end if;
  select jno, status into j from cutting_jobs where id = NEW.job_id;
  if not found then return NEW; end if;
  if j.status <> 'completed' then
    raise exception 'Job % abhi mukammal nahi hua. Pehle usay Completed karein, phir delivery banayein.', j.jno;
  end if;
  return NEW;
end;
$function$;


-- ============================================================
--  HISSA 4 — Jo triggers kahin likhe hi nahi gaye
-- ============================================================

drop trigger if exists trg_item_opening_ins on items;
create trigger trg_item_opening_ins after insert on items
  for each row execute function trg_recompute_on_item();

drop trigger if exists trg_item_opening_upd on items;
create trigger trg_item_opening_upd after update on items
  for each row
  when (old.opening_qty  is distinct from new.opening_qty
     or old.opening_rate is distinct from new.opening_rate)
  execute function trg_recompute_on_item();

drop trigger if exists trg_adjust_recompute on stock_adjustments;
create trigger trg_adjust_recompute after insert or update or delete on stock_adjustments
  for each row execute function trg_recompute_on_adjust();

drop trigger if exists trg_coil_limits on coils;
create trigger trg_coil_limits before insert or update on coils
  for each row execute function trg_check_coil_limits();

drop trigger if exists trg_delivery_job_completed on delivery_challan_lines;
create trigger trg_delivery_job_completed before insert or update on delivery_challan_lines
  for each row execute function trg_check_delivery_job();

-- Yeh purana trigger production se hat chuka hai — trg_delivery_job_completed
-- ne is ki jagah le li
drop trigger if exists trg_delivery_available on delivery_challan_lines;


-- ============================================================
--  HISSA 5 — Restore ke liye zaroori baatein
--
--  Yeh chalti hui SQL nahi, sirf likha hua sach hai. Backup se restore
--  karte waqt do cheezein file mein hoti hi nahi:
--
--  1. NUMBERING (sequences)
--     voucher_sale_seq, voucher_purchase_seq, mi_seq, cj_seq, dc_seq,
--     mr_seq, sv_seq, cv_seq, coil_seq — inn ki halat backup file mein
--     nahi jati. Purane bill apne asal number ke saath wapas aa jate hain
--     (assign_voucher_number khali number hi banata hai, mojood ko haath
--     nahi lagata) — magar ginti wahin rehti hai jahan naye database mein
--     thi, yani 1 par. Agla naya bill purane number se takra sakta hai.
--
--     Is liye Masters → Restore ke aakhir mein system khud "setval" wali
--     SQL bana kar dikhata hai. Naye database par restore karne ke baad
--     wo ek dafa chala dein.
--
--  2. USERS
--     app_users ki id auth.users se juri hui hai (on delete cascade).
--     Naye project mein wo auth users hote hi nahi, is liye app_users ko
--     restore karna namumkin hai — foreign key rok degi. Users naye
--     project mein Masters → Users se dobara banane parte hain.
--
--  Aur ek cheez khud ba khud theek ho jati hai:
--     party_opening_balances aur item_cost_snapshot sirf hisaab ka
--     "cache" hain. Period lock badalte hi khali ho jate hain aur zaroorat
--     par dobara ban jate hain — inhein backup mein rakhne ka faida nahi.
-- ============================================================
