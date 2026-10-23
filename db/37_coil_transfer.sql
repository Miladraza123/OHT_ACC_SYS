-- ============================================================
--  37 — Coil Transfer (Malikiyat Tabdeeli): Ahmed ki coil ka bina kata
--       maal Bilal ke naam (23 Oktober 2026)
--
--  Karobari soorat: Ahmed ki coil hamare godown mein hai. Ahmed ne (poori ya
--  kuch) coil Bilal ko bech di, Bilal khud uthayega. Hum Ahmed ki coil ka
--  RAW (bina kata) balance Bilal ke naam par muntaqil karte hain — Ahmed ke
--  purane jobs / challan / invoice ko haath NAHI lagta. Kata hua (finished)
--  maal job wali party ka hi rehta hai aur normal Delivery Challan se jata hai.
--
--  Is file mein:
--    1. coil_transfers table + ct_seq + cutting_settings.transfer_prefix (CT-0001)
--    2. coils: transfer_id (FK nahi — gol FK se bachne ke liye) aur
--       transferred_out_weight (sirf trigger likhta hai)
--    3. recalc_coil_balances: returned_weight = wapsi + transfer out
--    4. trg_coil_guard: nayi columns bhi trigger-owned; transfer wali coil par tala
--    5. create_coil_transfer / cancel_coil_transfer (RPC — sirf yehi likhte hain)
--    6. RLS + audit + guard triggers
--    7. Views: coil_ledger_v, party_coil_stock_v, party_material_ledger_v
--    8. wipe_test_data (28) + bulk wipe (29) mein coil_transfers aur ct_seq
--
--  FAISLAY (har faisla yahan likha hai):
--
--    F1  Sirf RAW balance muntaqil hota hai, poora ya aadha. Wazan
--        <= raw_balance AUR <= physical_balance — transfer se physical kabhi
--        manfi nahi hota. Tolerance (balance_tolerance_pct) transfer par
--        LAGU NAHI — tolerance sirf naap ke farq ke liye hai, malikiyat ke
--        liye nahi.
--    F2  Naya coil: ownership 'party', party = Bilal, received_weight = wazan,
--        received_date = transfer ki tareekh, inward_id null, transfer_id = CT,
--        serial wahi purana generator (assign_coil_serial / coil_seq).
--    F3  Ahmed ki coil ka hisaab: returned_weight = material return + active
--        transfer out. Is tarah raw_balance / physical_balance (generated) aur
--        db/36 ke saare guards (trg_check_coil_limits, trg_coil_guard,
--        inward cancel, close_coil) bina badle transfer ko bhi ginte hain.
--        transferred_out_weight = sirf transfer out. Khalis return =
--        returned_weight - transferred_out_weight.
--    F4  Cancel sirf tab jab Bilal ki nayi coil BILKUL istemaal na hui ho
--        (consumed = returned = finished = delivered = closing = 0, active).
--        Warna saaf message ke kya ho chuka hai. Ahmed ki source coil band ho
--        chuki ho to bhi cancel mana (pehle reopen_coil). Cancel par nayi coil
--        'cancelled' hoti hai aur Ahmed ka raw_balance wapas aata hai.
--        Cancelled transfer ki nayi coil coil_ledger_v mein nahi dikhti
--        (cancelled coil ka transfer_in nahi), aur transfer_out bhi nahi.
--    F5  Likhne ka raasta sirf RPC. RLS mein authenticated ke liye seedhi
--        insert/update ki policy NAHI — SIWAYE admin ke. (CONTRACT kehta tha
--        "koi insert/update policy nahi"; magar Restore admin ban kar seedha
--        coil_transfers upsert karta hai, is liye admin ke liye rakhi.) Admin
--        ki seedhi likhai par bhi trigger lagte hain: tno / coil / party /
--        wazan badalna mana, status sirf RPC se, active transfer ki delete
--        mana. DELETE sirf admin.
--    F6  Active transfer hard delete / soft delete nahi ho sakta (pehle
--        cancel). Wipe functions ke liye app.wipe_mode setting se rasta.
--    F7  Transfer se bani coil (active transfer) par seedhi cancel / delete /
--        party / received_weight badalna mana — sirf cancel_coil_transfer.
--    F8  Bulk wipe (29) ek TRUNCATE ... CASCADE hai: coil_transfers coils
--        ki FK se khud cascade ho jati hai, is liye FK error nahi. 29 wali
--        file mein ct_seq reset nahi hota; is liye coil_transfers par TRUNCATE
--        trigger hai jo ct_seq 1 par le aata hai (cascade se bhi chalta hai).
--    F9  Numbering: transfer_prefix naya column (default 'CT') cutting_settings
--        mein; tno = CT-0001. Number RPC pehle hi le leta hai taake nayi coil
--        ke remarks mein likha ja sake.
--
--  Ijazatein (admin ko sab implicit): cutting_transfer_view,
--  cutting_transfer_create, cutting_transfer_cancel. SELECT: admin ya
--  transfer_view ya cutting_stock_view.
--
--  Yeh file dobara chalane par bhi mehfooz hai (create or replace,
--  if not exists, drop trigger/policy if exists). 36 ke baad chalayein,
--  ek hi transaction mein (psql -1 / SQL editor).
--
--  LIVE DB OWNER KE LIYE:
--    * Koi purani row nahi badalti, koi data recompute nahi — naye columns
--      0 / null hain aur abhi koi transfer nahi, is liye purane balance
--      wahi rehte hain.
--    * Koi function ka return type nahi badla (drop ki zaroorat nahi). Views
--      mein sirf aakhir mein columns barhe: agar live par in teen views mein
--      haath se koi EXTRA column ban chuka ho to create or replace
--      ("cannot drop columns") rok dega — pehle us column ka naam bata dein.
--    * recalc_coil_balances, trg_coil_guard, wipe_test_data nayi definition se
--      badal jate hain. Agar live par in mein haath se tabdeeli hui hai to
--      pehle pg_get_functiondef se mawazna karein.
--    * Chalane ke baad PostgREST ko batayein: notify pgrst, 'reload schema';
--    * App ki Users screen mein 3 nayi ijazatein (client1-masters.html) aur
--      client1-cutting.html ka Coil Transfer screen alag files mein hain.
--    * Bulk wipe (29) ki table-list mein coil_transfers nahi — zaroori nahi
--      (cascade), magar saaf rakhne ke liye wahan add ki ja sakti hai.
-- ============================================================


-- ============================================================
--  HISSA 1 — Numbering: ct_seq aur transfer_prefix
-- ============================================================

create sequence if not exists public.ct_seq;

alter table public.cutting_settings
  add column if not exists transfer_prefix text not null default 'CT';

-- Internal helper (sirf RPC / trigger ke andar se)
create or replace function public.next_transfer_no()
returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare prefix text;
begin
  select coalesce(nullif(trim(transfer_prefix), ''), 'CT') into prefix from cutting_settings where id = 1;
  return coalesce(prefix, 'CT') || '-' || lpad(nextval('public.ct_seq')::text, 4, '0');
end;
$function$;

revoke all on function public.next_transfer_no() from public, anon, authenticated;


-- ============================================================
--  HISSA 2 — coil_transfers table
-- ============================================================

create table if not exists public.coil_transfers (
  id               uuid        primary key default gen_random_uuid(),
  tno              text        not null,
  tdate            date        not null default current_date,
  from_party_id    uuid        not null,
  to_party_id      uuid        not null,
  from_coil_id     uuid        not null,
  to_coil_id       uuid        not null,
  weight           numeric     not null,
  reference        text        default '',
  remarks          text        default '',
  status           text        not null default 'active',
  cancel_reason    text,
  cancelled_at     timestamptz,
  cancelled_by     uuid,
  version          integer     not null default 1,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  updated_at       timestamptz,
  updated_by       uuid,
  deleted_at       timestamptz
);

-- Constraints: har ek alag, taake live par aadhi bani table ho to bhi chalein
do $$
begin
  perform 1 from pg_constraint where conname = 'coil_transfers_tno_key' and conrelid = 'public.coil_transfers'::regclass;
  if not found then
    alter table public.coil_transfers add constraint coil_transfers_tno_key unique (tno);
  end if;
  perform 1 from pg_constraint where conname = 'coil_transfers_weight_pos' and conrelid = 'public.coil_transfers'::regclass;
  if not found then
    alter table public.coil_transfers add constraint coil_transfers_weight_pos check (weight > 0);
  end if;
  perform 1 from pg_constraint where conname = 'coil_transfers_status_check' and conrelid = 'public.coil_transfers'::regclass;
  if not found then
    alter table public.coil_transfers add constraint coil_transfers_status_check check (status in ('active', 'cancelled'));
  end if;
  perform 1 from pg_constraint where conname = 'coil_transfers_parties_differ' and conrelid = 'public.coil_transfers'::regclass;
  if not found then
    alter table public.coil_transfers add constraint coil_transfers_parties_differ check (from_party_id <> to_party_id);
  end if;
  perform 1 from pg_constraint where conname = 'coil_transfers_coils_differ' and conrelid = 'public.coil_transfers'::regclass;
  if not found then
    alter table public.coil_transfers add constraint coil_transfers_coils_differ check (from_coil_id <> to_coil_id);
  end if;
  perform 1 from pg_constraint where conname = 'coil_transfers_from_party_fkey' and conrelid = 'public.coil_transfers'::regclass;
  if not found then
    alter table public.coil_transfers add constraint coil_transfers_from_party_fkey foreign key (from_party_id) references public.parties(id);
  end if;
  perform 1 from pg_constraint where conname = 'coil_transfers_to_party_fkey' and conrelid = 'public.coil_transfers'::regclass;
  if not found then
    alter table public.coil_transfers add constraint coil_transfers_to_party_fkey foreign key (to_party_id) references public.parties(id);
  end if;
  perform 1 from pg_constraint where conname = 'coil_transfers_from_coil_fkey' and conrelid = 'public.coil_transfers'::regclass;
  if not found then
    alter table public.coil_transfers add constraint coil_transfers_from_coil_fkey foreign key (from_coil_id) references public.coils(id);
  end if;
  perform 1 from pg_constraint where conname = 'coil_transfers_to_coil_fkey' and conrelid = 'public.coil_transfers'::regclass;
  if not found then
    alter table public.coil_transfers add constraint coil_transfers_to_coil_fkey foreign key (to_coil_id) references public.coils(id);
  end if;
  perform 1 from pg_constraint where conname = 'coil_transfers_created_by_fkey' and conrelid = 'public.coil_transfers'::regclass;
  if not found then
    alter table public.coil_transfers add constraint coil_transfers_created_by_fkey foreign key (created_by) references public.app_users(id);
  end if;
  perform 1 from pg_constraint where conname = 'coil_transfers_updated_by_fkey' and conrelid = 'public.coil_transfers'::regclass;
  if not found then
    alter table public.coil_transfers add constraint coil_transfers_updated_by_fkey foreign key (updated_by) references public.app_users(id);
  end if;
  perform 1 from pg_constraint where conname = 'coil_transfers_cancelled_by_fkey' and conrelid = 'public.coil_transfers'::regclass;
  if not found then
    alter table public.coil_transfers add constraint coil_transfers_cancelled_by_fkey foreign key (cancelled_by) references public.app_users(id);
  end if;
end $$;

create index if not exists coil_transfers_from_coil_idx  on public.coil_transfers (from_coil_id);
create index if not exists coil_transfers_to_coil_idx    on public.coil_transfers (to_coil_id);
create index if not exists coil_transfers_from_party_idx on public.coil_transfers (from_party_id);
create index if not exists coil_transfers_to_party_idx   on public.coil_transfers (to_party_id);
create index if not exists coil_transfers_date_idx       on public.coil_transfers (tdate desc);


-- ============================================================
--  HISSA 3 — coils ke naye columns
--
--  transfer_id par FK jaan boojh kar nahi (coil_transfers.to_coil_id coils
--  ki taraf pehle se ishara karta hai — gol FK restore / wipe ko mushkil
--  kar deta).
-- ============================================================

alter table public.coils add column if not exists transfer_id uuid;
alter table public.coils add column if not exists transferred_out_weight numeric not null default 0;

do $$
begin
  perform 1 from pg_constraint where conname = 'coils_transferred_nonneg' and conrelid = 'public.coils'::regclass;
  if not found then
    alter table public.coils add constraint coils_transferred_nonneg check (transferred_out_weight >= 0);
  end if;
end $$;

create index if not exists coils_transfer_idx on public.coils (transfer_id) where transfer_id is not null;


-- ============================================================
--  HISSA 4 — recalc_coil_balances: returned_weight mein transfer out bhi
--
--  MASLA  Transfer ke baad Ahmed ki coil ka raw_balance kam hona chahiye
--         (aur physical bhi), warna maal do jagah dikhta.
--  HAL    36 wala function bilkul wahi (row lock, ginti, likhai); party coil
--         par ek ginti barhi: active transfer out. returned_weight = wapsi +
--         transfer out, transferred_out_weight = sirf transfer out.
-- ============================================================

create or replace function public.recalc_coil_balances(p_coil_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c             record;
  v_consumed    numeric;
  v_returned    numeric;
  v_transferred numeric;
  v_finished    numeric;
  v_delivered   numeric;
begin
  if p_coil_id is null then return; end if;
  select * into c from coils where id = p_coil_id for update;
  if not found then return; end if;

  if c.ownership = 'own' then
    -- Company ki apni coil: sirf Stock Conversion se kharch hoti hai
    select coalesce(sum(ci.qty), 0) into v_consumed
      from stock_conversion_inputs ci
      join stock_conversions sc on sc.id = ci.conversion_id
     where ci.coil_id = p_coil_id and sc.deleted_at is null and sc.status <> 'cancelled';

    v_returned := 0; v_transferred := 0; v_finished := 0; v_delivered := 0;
  else
    -- Party ki coil: cutting jobs, returns, transfers aur delivery challans
    select coalesce(sum(i.input_weight), 0) into v_consumed
      from cutting_job_inputs i
      join cutting_jobs j on j.id = i.job_id
     where i.coil_id = p_coil_id and j.deleted_at is null and j.status <> 'cancelled';

    select coalesce(sum(o.output_weight), 0) into v_finished
      from cutting_job_outputs o
      join cutting_jobs j on j.id = o.job_id
     where o.coil_id = p_coil_id and j.deleted_at is null and j.status <> 'cancelled';

    select coalesce(sum(l.return_weight), 0) into v_returned
      from material_return_lines l
      join material_returns r on r.id = l.return_id
     where l.coil_id = p_coil_id and r.deleted_at is null and r.status <> 'cancelled';

    select coalesce(sum(t.weight), 0) into v_transferred
      from coil_transfers t
     where t.from_coil_id = p_coil_id and t.deleted_at is null and t.status = 'active';

    select coalesce(sum(l.delivered_weight), 0) into v_delivered
      from delivery_challan_lines l
      join delivery_challans d on d.id = l.challan_id
     where l.coil_id = p_coil_id and d.deleted_at is null and d.status <> 'cancelled';
  end if;

  perform set_config('app.system_write', 'true', true);
  update coils
     set consumed_weight        = v_consumed,
         finished_weight        = v_finished,
         returned_weight        = v_returned + v_transferred,
         transferred_out_weight = v_transferred,
         delivered_weight       = v_delivered
   where id = p_coil_id;
  perform set_config('app.system_write', 'false', true);
end;
$function$;

revoke all on function public.recalc_coil_balances(uuid) from public, anon, authenticated;


-- ============================================================
--  HISSA 5 — trg_coil_guard: nayi columns + transfer wali coil
--
--  MASLA  (a) transferred_out_weight / transfer_id ko cutting_coil_adjust
--         wala user seedha PATCH kar sakta tha. (b) Transfer se bani coil ko
--         seedha cancel / delete karne se transfer "active" rehta aur Ahmed
--         ka maal gum.
--  HAL    36 wala function waisa hi; do cheezein barhi: dono columns
--         trigger-owned (chupke se purani value, jaise baqi), aur active
--         transfer ki coil par cancel / delete / party / received_weight
--         badalna mana — rasta sirf cancel_coil_transfer (system_write).
-- ============================================================

create or replace function public.trg_coil_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_used boolean; v_live_transfer boolean;
begin
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    return NEW;
  end if;

  -- trigger-owned: jo trigger ne likha wohi rahega
  NEW.consumed_weight        := OLD.consumed_weight;
  NEW.finished_weight        := OLD.finished_weight;
  NEW.returned_weight        := OLD.returned_weight;
  NEW.transferred_out_weight := OLD.transferred_out_weight;
  NEW.transfer_id            := OLD.transfer_id;
  NEW.delivered_weight       := OLD.delivered_weight;
  NEW.closing_adjust_weight  := OLD.closing_adjust_weight;
  NEW.closed_at              := OLD.closed_at;
  NEW.closed_by              := OLD.closed_by;

  if (NEW.status = 'closed') is distinct from (OLD.status = 'closed') then
    raise exception 'Coil % band karna / kholna sirf "Coil band karein" / "Dobara kholein" se ho sakta hai', OLD.coil_serial;
  end if;

  v_used := (OLD.consumed_weight + OLD.returned_weight + OLD.delivered_weight
             + OLD.finished_weight + OLD.closing_adjust_weight) > 0;

  if NEW.received_weight < OLD.received_weight
     and NEW.received_weight < greatest(OLD.consumed_weight + OLD.returned_weight,
                                        OLD.delivered_weight + OLD.returned_weight + OLD.closing_adjust_weight) then
    raise exception 'Coil % se % KG maal istemaal / deliver ho chuka hai — received weight % KG nahi ho sakta',
      OLD.coil_serial,
      greatest(OLD.consumed_weight + OLD.returned_weight,
               OLD.delivered_weight + OLD.returned_weight + OLD.closing_adjust_weight),
      NEW.received_weight;
  end if;

  if v_used and (
       (OLD.status <> 'cancelled' and NEW.status = 'cancelled')
    or (OLD.deleted_at is null and NEW.deleted_at is not null)
    or NEW.party_id  is distinct from OLD.party_id
    or NEW.item_id   is distinct from OLD.item_id
    or NEW.ownership is distinct from OLD.ownership) then
    raise exception 'Coil % par kaam ho chuka hai — cancel / delete / party ya item badalna mana hai', OLD.coil_serial;
  end if;

  -- Transfer se bani coil: uska wazan / party / halat transfer ke saath bandhi hai
  if OLD.transfer_id is not null then
    select exists (select 1 from coil_transfers t
                    where t.id = OLD.transfer_id and t.status = 'active' and t.deleted_at is null)
      into v_live_transfer;
    if v_live_transfer and (
         (OLD.status <> 'cancelled' and NEW.status = 'cancelled')
      or (OLD.deleted_at is null and NEW.deleted_at is not null)
      or NEW.party_id is distinct from OLD.party_id
      or NEW.received_weight is distinct from OLD.received_weight) then
      raise exception 'Coil % Coil Transfer se bani hai — cancel / delete / party ya wazan badalna mana hai. Pehle Coil Transfer cancel karein.', OLD.coil_serial;
    end if;
  end if;

  return NEW;
end;
$function$;

-- naam "trg_coil_guard" < "trg_coil_limits": pehle yeh chale, phir hadd
drop trigger if exists trg_coil_guard on coils;
create trigger trg_coil_guard before update on coils for each row execute function trg_coil_guard();


-- ============================================================
--  HISSA 6 — coil_transfers ke triggers
--    * tno khud
--    * audit / version / permission (cutting documents jaisa)
--    * guard: seedhi likhai par bhi hisaab ki sachai
--    * recalc: Ahmed ki coil ka balance
-- ============================================================

create or replace function public.assign_transfer_number()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if NEW.tno is null or trim(NEW.tno) = '' then
    NEW.tno := next_transfer_no();
  end if;
  return NEW;
end;
$function$;

create or replace function public.trg_transfer_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if TG_OP = 'DELETE' then
    if coalesce(current_setting('app.wipe_mode', true), '') = 'true' then return OLD; end if;
    if OLD.status = 'active' and OLD.deleted_at is null then
      raise exception 'Transfer % abhi active hai — delete nahi ho sakta. Pehle cancel karein (cancel_coil_transfer).', OLD.tno;
    end if;
    return OLD;
  end if;

  if TG_OP = 'INSERT' then
    -- naye transfer ki dono coil party ki hon, aur party coil se mel khayein
    if not exists (select 1 from coils where id = NEW.from_coil_id and party_id = NEW.from_party_id and ownership = 'party') then
      raise exception 'Transfer: source coil us party ki nahi (ya party coil nahi)';
    end if;
    if not exists (select 1 from coils where id = NEW.to_coil_id and party_id = NEW.to_party_id and ownership = 'party') then
      raise exception 'Transfer: nayi coil us party ki nahi (ya party coil nahi)';
    end if;
    return NEW;
  end if;

  -- UPDATE
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    return NEW;
  end if;
  if NEW.tno is distinct from OLD.tno
     or NEW.from_party_id is distinct from OLD.from_party_id
     or NEW.to_party_id   is distinct from OLD.to_party_id
     or NEW.from_coil_id  is distinct from OLD.from_coil_id
     or NEW.to_coil_id    is distinct from OLD.to_coil_id
     or NEW.weight        is distinct from OLD.weight then
    raise exception 'Transfer % ka number / party / coil / wazan badalna mana hai — cancel karke naya transfer banayein', OLD.tno;
  end if;
  if NEW.status is distinct from OLD.status
     or NEW.cancel_reason is distinct from OLD.cancel_reason
     or NEW.cancelled_at is distinct from OLD.cancelled_at
     or NEW.cancelled_by is distinct from OLD.cancelled_by then
    raise exception 'Transfer % ki halat sirf cancel_coil_transfer se badal sakti hai', OLD.tno;
  end if;
  if OLD.status = 'active' and OLD.deleted_at is null and NEW.deleted_at is not null then
    raise exception 'Transfer % abhi active hai — delete nahi ho sakta. Pehle cancel karein.', OLD.tno;
  end if;
  return NEW;
end;
$function$;

create or replace function public.trg_transfer_recalc()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if coalesce(current_setting('app.wipe_mode', true), '') = 'true' then
    return null;
  end if;
  if TG_OP = 'DELETE' then
    perform recalc_coil_balances(OLD.from_coil_id);
  else
    perform recalc_coil_balances(NEW.from_coil_id);
    if TG_OP = 'UPDATE' and OLD.from_coil_id is distinct from NEW.from_coil_id then
      perform recalc_coil_balances(OLD.from_coil_id);
    end if;
  end if;
  return null;
end;
$function$;

-- TRUNCATE (bulk wipe 29, cascade se bhi) par ginti wapas 1
create or replace function public.trg_transfer_truncate()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform setval('public.ct_seq', 1, false);
  return null;
end;
$function$;

drop trigger if exists trg_no_coil_transfers       on coil_transfers;
drop trigger if exists trg_guard_coil_transfers    on coil_transfers;
drop trigger if exists trg_audit_coil_transfers    on coil_transfers;
drop trigger if exists trg_log_coil_transfers      on coil_transfers;
drop trigger if exists trg_version_coil_transfers  on coil_transfers;
drop trigger if exists trg_perm_coil_transfers     on coil_transfers;
drop trigger if exists trg_recalc_coil_transfers   on coil_transfers;
drop trigger if exists trg_truncate_coil_transfers on coil_transfers;

create trigger trg_no_coil_transfers       before insert                     on coil_transfers for each row execute function assign_transfer_number();
create trigger trg_guard_coil_transfers    before insert or update or delete on coil_transfers for each row execute function trg_transfer_guard();
create trigger trg_audit_coil_transfers    before insert or update           on coil_transfers for each row execute function stamp_audit_fields();
create trigger trg_log_coil_transfers      after  insert or update or delete on coil_transfers for each row execute function log_audit_event();
create trigger trg_version_coil_transfers  before update                     on coil_transfers for each row execute function bump_version();
create trigger trg_perm_coil_transfers     before update                     on coil_transfers for each row execute function enforce_doc_perm_on_update('cutting_transfer_create','cutting_transfer_cancel','recycle_bin');
create trigger trg_recalc_coil_transfers   after  insert or update or delete on coil_transfers for each row execute function trg_transfer_recalc();
create trigger trg_truncate_coil_transfers after  truncate                   on coil_transfers for each statement execute function trg_transfer_truncate();


-- ============================================================
--  HISSA 7 — RLS
--
--  SELECT: admin / cutting_transfer_view / cutting_stock_view.
--  Likhai: sirf RPC (SECURITY DEFINER). Seedhi insert/update sirf admin
--  (Restore ke liye — F5). DELETE sirf admin. db/34 ki restrictive
--  "active user only" policy bhi.
-- ============================================================

alter table public.coil_transfers enable row level security;

drop policy if exists "coil_transfers select" on public.coil_transfers;
drop policy if exists "coil_transfers insert" on public.coil_transfers;
drop policy if exists "coil_transfers update" on public.coil_transfers;
drop policy if exists "coil_transfers delete" on public.coil_transfers;
drop policy if exists "active user only"      on public.coil_transfers;

create policy "coil_transfers select" on public.coil_transfers for select
  using (is_app_admin() or has_perm('cutting_transfer_view') or has_perm('cutting_stock_view'));
create policy "coil_transfers insert" on public.coil_transfers for insert
  with check (is_app_admin());
create policy "coil_transfers update" on public.coil_transfers for update
  using (is_app_admin()) with check (is_app_admin());
create policy "coil_transfers delete" on public.coil_transfers for delete
  using (is_app_admin());
create policy "active user only" on public.coil_transfers as restrictive for all to authenticated
  using ((select is_active_app_user()))
  with check ((select is_active_app_user()));

revoke all on public.coil_transfers from anon;
revoke all on public.coil_transfers from public;
grant select, insert, update, delete on public.coil_transfers to authenticated;
grant all on public.coil_transfers to service_role;


-- ============================================================
--  HISSA 8 — create_coil_transfer
-- ============================================================

drop function if exists public.create_coil_transfer(uuid, uuid, numeric, date, text, text);

create or replace function public.create_coil_transfer(
  p_from_coil uuid,
  p_to_party  uuid,
  p_weight    numeric,
  p_date      date default current_date,
  p_reference text default '',
  p_remarks   text default ''
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c         record;
  tp        record;
  fp_name   text;
  v_w       numeric;
  v_tid     uuid := gen_random_uuid();
  v_cid     uuid := gen_random_uuid();
  v_tno     text;
  v_serial  text;
begin
  if auth.uid() is null or not (is_app_admin() or has_perm('cutting_transfer_create')) then
    raise exception 'Permission denied: cutting_transfer_create zaroori hai';
  end if;

  if p_weight is null or p_weight <= 0 then
    raise exception 'Transfer ka wazan 0 se zyada hona chahiye';
  end if;
  v_w := round(p_weight, 3);
  if v_w <= 0 then
    raise exception 'Transfer ka wazan 0 se zyada hona chahiye';
  end if;

  -- FOR UPDATE: do transfer ek saath ek hi coil se zyada maal na nikal saken.
  -- Lock ke baad raw_balance taza parhta hai (READ COMMITTED).
  select * into c from coils where id = p_from_coil for update;
  if not found then raise exception 'Coil mojood nahi'; end if;
  if c.deleted_at is not null then raise exception 'Coil % delete ho chuki hai', c.coil_serial; end if;
  if c.ownership <> 'party' then
    raise exception 'Coil % company ki apni coil hai — sirf party ki coil transfer ho sakti hai', c.coil_serial;
  end if;
  if c.status = 'cancelled' then raise exception 'Coil % cancel ho chuki hai', c.coil_serial; end if;
  if c.status = 'closed' then
    raise exception 'Coil % band ho chuki hai — transfer nahi ho sakta', c.coil_serial;
  end if;

  select * into tp from parties where id = p_to_party;
  if not found or tp.deleted_at is not null then
    raise exception 'Naya malik (party) mojood nahi';
  end if;
  if not tp.active then
    raise exception 'Party % band (inactive) hai — usay coil transfer nahi ho sakti', tp.name;
  end if;
  if tp.id = c.party_id then
    raise exception 'Coil % pehle se isi party (%) ki hai — doosri party chunein', c.coil_serial, tp.name;
  end if;

  if v_w > c.raw_balance then
    raise exception 'Coil % ka bina kata balance sirf % KG hai — % KG transfer nahi ho sakta (kata hua maal challan se jata hai, transfer se nahi)',
      c.coil_serial, c.raw_balance, v_w;
  end if;
  if v_w > c.physical_balance then
    raise exception 'Coil % ka physical balance sirf % KG hai — % KG transfer nahi ho sakta',
      c.coil_serial, c.physical_balance, v_w;
  end if;

  select name into fp_name from parties where id = c.party_id;
  v_tno := next_transfer_no();

  insert into coils (id, ownership, party_id, item_id, warehouse_id, party_coil_ref,
                     material_type, grade, thickness_mm, width_mm,
                     received_weight, received_date, inward_id, transfer_id, status, remarks)
  values (v_cid, 'party', tp.id, c.item_id, c.warehouse_id, c.party_coil_ref,
          c.material_type, c.grade, c.thickness_mm, c.width_mm,
          v_w, coalesce(p_date, current_date), null, v_tid, 'active',
          'Transfer in ← ' || coalesce(fp_name, '?') || ' (' || v_tno || ')')
  returning coil_serial into v_serial;

  insert into coil_transfers (id, tno, tdate, from_party_id, to_party_id, from_coil_id, to_coil_id,
                              weight, reference, remarks, status)
  values (v_tid, v_tno, coalesce(p_date, current_date), c.party_id, tp.id, c.id, v_cid,
          v_w, coalesce(p_reference, ''), coalesce(p_remarks, ''), 'active');
  -- (after-insert trigger Ahmed ki coil ka balance dobara ginta hai)

  return jsonb_build_object(
    'id', v_tid,
    'tno', v_tno,
    'to_coil_id', v_cid,
    'to_coil_serial', v_serial,
    'from_coil_serial', c.coil_serial,
    'weight', v_w
  );
end;
$function$;


-- ============================================================
--  HISSA 9 — cancel_coil_transfer
-- ============================================================

drop function if exists public.cancel_coil_transfer(uuid, text);

create or replace function public.cancel_coil_transfer(
  p_id     uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  t       record;
  nc      record;
  fc      record;
  v_used  text[] := array[]::text[];
  v_pure  numeric;
begin
  if auth.uid() is null or not (is_app_admin() or has_perm('cutting_transfer_cancel')) then
    raise exception 'Permission denied: cutting_transfer_cancel zaroori hai';
  end if;
  if p_reason is null or trim(p_reason) = '' then
    raise exception 'Cancel ki wajah likhna zaroori hai';
  end if;

  select * into t from coil_transfers where id = p_id for update;
  if not found or t.deleted_at is not null then raise exception 'Transfer mojood nahi'; end if;
  if t.status = 'cancelled' then
    raise exception 'Transfer % pehle hi cancel ho chuka hai', t.tno;
  end if;

  -- pehle source coil, phir nayi coil (hamesha isi tarteeb se lock)
  select * into fc from coils where id = t.from_coil_id for update;
  select * into nc from coils where id = t.to_coil_id for update;
  if not found then raise exception 'Transfer % ki nayi coil mojood nahi', t.tno; end if;

  -- Ahmed ki coil band / cancel ho chuki ho to maal wapas dene se hisaab ghalat (closing adjustment
  -- transfer ke baghair ginti thi) — pehle coil dobara kholein (reopen_coil)
  if fc.status <> 'active' or fc.deleted_at is not null then
    raise exception 'Transfer % cancel nahi ho sakta — source coil % ab "%" hai. Pehle coil dobara kholein (reopen), phir cancel karein.',
      t.tno, fc.coil_serial, case when fc.deleted_at is not null then 'deleted' else fc.status end;
  end if;

  v_pure := nc.returned_weight - nc.transferred_out_weight;
  if nc.consumed_weight > 0 then
    v_used := v_used || format('job mein %s KG lag chuka', trim_scale(nc.consumed_weight)::text);
  end if;
  if nc.finished_weight > 0 then
    v_used := v_used || format('job se %s KG maal bana', trim_scale(nc.finished_weight)::text);
  end if;
  if nc.delivered_weight > 0 then
    v_used := v_used || format('%s KG delivery ho chuki', trim_scale(nc.delivered_weight)::text);
  end if;
  if v_pure > 0 then
    v_used := v_used || format('%s KG wapas (return) ho chuka', trim_scale(v_pure)::text);
  end if;
  if nc.transferred_out_weight > 0 then
    v_used := v_used || format('%s KG aage doosri party ko transfer ho chuka', trim_scale(nc.transferred_out_weight)::text);
  end if;
  if nc.closing_adjust_weight > 0 then
    v_used := v_used || format('closing adjustment %s KG', trim_scale(nc.closing_adjust_weight)::text);
  end if;
  if nc.status <> 'active' then
    v_used := v_used || format('coil ki halat "%s" hai', nc.status);
  end if;
  if nc.deleted_at is not null then
    v_used := v_used || 'coil delete ho chuki hai';
  end if;

  if array_length(v_used, 1) > 0 then
    raise exception 'Transfer % cancel nahi ho sakta — nayi coil % par kaam ho chuka hai: %. Pehle woh kaam (job / challan / return / transfer) cancel karein.',
      t.tno, nc.coil_serial, array_to_string(v_used, ', ');
  end if;

  perform set_config('app.system_write', 'true', true);
  update coil_transfers
     set status = 'cancelled', cancel_reason = trim(p_reason),
         cancelled_at = now(), cancelled_by = auth.uid()
   where id = t.id;                       -- trigger Ahmed ki coil dobara ginta hai
  perform set_config('app.system_write', 'true', true);   -- recalc ne band kar diya tha
  update coils set status = 'cancelled' where id = nc.id;
  perform set_config('app.system_write', 'false', true);

  perform log_manual_audit('coil_transfers', t.id, t.tno, 'transfer_cancelled',
    jsonb_build_object('reason', trim(p_reason), 'weight', t.weight,
                       'from_coil', fc.coil_serial, 'to_coil', nc.coil_serial));

  return jsonb_build_object('id', t.id, 'tno', t.tno, 'status', 'cancelled');
end;
$function$;

revoke all on function public.create_coil_transfer(uuid, uuid, numeric, date, text, text) from public, anon;
revoke all on function public.cancel_coil_transfer(uuid, text) from public, anon;
grant execute on function public.create_coil_transfer(uuid, uuid, numeric, date, text, text) to authenticated;
grant execute on function public.cancel_coil_transfer(uuid, text) to authenticated;


-- ============================================================
--  HISSA 10 — Views (sirf aakhir mein columns barhe; purane columns jyun ke tyun)
--
--  coil_ledger_v: 'inward' sirf aam coil ka; transfer wali coil ka
--    'transfer_in' (doc_no = tno); Ahmed ki taraf 'transfer_out' (sort 7).
--    'return' wali branch material_return_lines se hai — khalis wapsi.
--  party_coil_stock_v: + transferred_out_weight, transfer_id, transfer_no,
--    transfer_from_party. returned_weight TOTAL (transfer samet) rehta hai.
--  party_material_ledger_v: + transferred_out_weight.
-- ============================================================

create or replace view coil_ledger_v as
  -- 1. Maal aaya (aam inward)
  select c.id                        as coil_id,
         c.coil_serial,
         c.party_id,
         c.received_date             as entry_date,
         1                           as sort_order,
         'inward'                    as entry_type,
         mi.ino                      as doc_no,
         mi.id                       as doc_id,
         'material_inwards'          as doc_table,
         c.received_weight           as in_kg,
         0::numeric                  as out_kg,
         null::uuid                  as job_id,
         c.remarks                   as remarks
    from coils c
    left join material_inwards mi on mi.id = c.inward_id
   where c.deleted_at is null and c.transfer_id is null

  union all
  -- 1b. Maal transfer se aaya (doosri party se)
  select c.id, c.coil_serial, c.party_id, c.received_date, 1,
         'transfer_in', t.tno, t.id, 'coil_transfers',
         c.received_weight, 0::numeric, null::uuid, c.remarks
    from coils c
    join coil_transfers t on t.id = c.transfer_id
   where c.deleted_at is null and t.deleted_at is null and t.status = 'active'

  union all
  -- 2. Cutting job mein raw maal gaya
  select i.coil_id, c.coil_serial, c.party_id, j.jdate, 2,
         'job_input', j.jno, j.id, 'cutting_jobs',
         0::numeric, i.input_weight, j.id, j.remarks
    from cutting_job_inputs i
    join cutting_jobs j on j.id = i.job_id
    join coils c on c.id = i.coil_id
   where j.deleted_at is null and j.status <> 'cancelled'

  union all
  -- 3. Job se maal bana (delivery ke liye tayyar)
  select o.coil_id, c.coil_serial, c.party_id, j.jdate, 3,
         'job_output', j.jno, j.id, 'cutting_jobs',
         o.output_weight, 0::numeric, j.id,
         coalesce(o.width::text || ' ' || coalesce(o.width_unit, 'mm')
                  || case when coalesce(o.length, 0) <> 0
                          then ' x ' || o.length::text || ' ' || coalesce(o.length_unit, 'mm')
                          else '' end
                  || ' x ' || o.pieces::text || ' pcs',
                  o.remarks)
    from cutting_job_outputs o
    join cutting_jobs j on j.id = o.job_id
    join coils c on c.id = o.coil_id
   where j.deleted_at is null and j.status <> 'cancelled'

  union all
  -- 4. Delivery challan se maal gaya (ACTUAL tola gaya weight)
  select l.coil_id, c.coil_serial, c.party_id, d.ddate, 4,
         'delivery', d.dno, d.id, 'delivery_challans',
         0::numeric, l.delivered_weight, l.job_id,
         case when l.variance_kg <> 0
              then 'Variance ' || l.variance_kg::text || ' KG'
                   || coalesce(' (' || l.variance_reason || ')', '')
              else l.remarks end
    from delivery_challan_lines l
    join delivery_challans d on d.id = l.challan_id
    join coils c on c.id = l.coil_id
   where d.deleted_at is null and d.status <> 'cancelled'

  union all
  -- 5. Raw maal wapas (khalis return — transfer is mein shamil nahi)
  select l.coil_id, c.coil_serial, c.party_id, r.rdate, 5,
         'return', r.rno, r.id, 'material_returns',
         0::numeric, l.return_weight, null::uuid, l.remarks
    from material_return_lines l
    join material_returns r on r.id = l.return_id
    join coils c on c.id = l.coil_id
   where r.deleted_at is null and r.status <> 'cancelled'

  union all
  -- 6. Coil band karte waqt closing adjustment / variance
  select c.id, c.coil_serial, c.party_id, c.closed_at::date, 6,
         'closing_adjustment', c.coil_serial, c.id, 'coils',
         0::numeric, c.closing_adjust_weight, null::uuid,
         coalesce(c.closing_reason, 'other')
         || coalesce(' — ' || c.closing_remarks, '')
    from coils c
   where c.deleted_at is null and c.status = 'closed' and c.closing_adjust_weight <> 0

  union all
  -- 7. Maal transfer ke zariye doosri party ko gaya
  select t.from_coil_id, c.coil_serial, c.party_id, t.tdate, 7,
         'transfer_out', t.tno, t.id, 'coil_transfers',
         0::numeric, t.weight, null::uuid,
         'Transfer → ' || coalesce(tp.name, '?')
    from coil_transfers t
    join coils c on c.id = t.from_coil_id
    left join parties tp on tp.id = t.to_party_id
   where c.deleted_at is null and t.deleted_at is null and t.status = 'active';

create or replace view party_coil_stock_v as
select c.id                  as coil_id,
       c.coil_serial,
       c.party_id,
       p.name                as party_name,
       c.party_coil_ref,
       c.material_type,
       c.grade,
       c.thickness_mm,
       c.width_mm,
       c.warehouse_id,
       w.name                as warehouse_name,
       c.received_date,
       c.received_weight,
       c.raw_balance,
       c.consumed_weight     as processed_weight,
       c.finished_weight,
       c.pending_delivery    as finished_pending_delivery,
       c.delivered_weight,
       c.returned_weight,
       c.closing_adjust_weight as variance_weight,
       c.status,
       c.closed_at,
       c.closing_reason,
       c.closing_remarks,
       (current_date - c.received_date) as age_days,
       c.transferred_out_weight,
       c.transfer_id,
       t.tno                 as transfer_no,
       fp.name               as transfer_from_party
  from coils c
  join parties p    on p.id = c.party_id
  join warehouses w on w.id = c.warehouse_id
  left join coil_transfers t on t.id = c.transfer_id
  left join parties fp       on fp.id = t.from_party_id
 where c.deleted_at is null
   and c.ownership = 'party'
   and c.status <> 'cancelled';

create or replace view party_material_ledger_v as
select c.party_id,
       p.name                                as party_name,
       count(*)                              as coil_count,
       count(*) filter (where c.status = 'active') as active_coils,
       sum(c.received_weight)                as received_weight,
       sum(c.raw_balance)                    as raw_balance,
       sum(c.consumed_weight)                as processed_weight,
       sum(c.pending_delivery)               as finished_pending_delivery,
       sum(c.delivered_weight)               as delivered_weight,
       sum(c.returned_weight)                as returned_weight,
       sum(c.closing_adjust_weight)          as variance_weight,
       sum(c.physical_balance)               as physical_balance,
       sum(c.transferred_out_weight)         as transferred_out_weight
  from coils c
  join parties p on p.id = c.party_id
 where c.deleted_at is null and c.ownership = 'party' and c.status <> 'cancelled'
 group by c.party_id, p.name;


-- ============================================================
--  HISSA 11 — wipe_test_data (28 wali definition + coil_transfers + ct_seq)
--
--  Sirf do tabdeeliyan: coil_transfers coils se PEHLE delete (FK), ct_seq
--  reset. Active transfer ka delete-guard wipe ke liye app.wipe_mode se
--  khulta hai. Baqi kaam 28 jaisa, lafz ba lafz.
-- ============================================================

create or replace function public.wipe_test_data(p_include_masters boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  s   text;
  seqs text[] := array[
    'voucher_sale_seq', 'voucher_purchase_seq',
    'mi_seq', 'cj_seq', 'dc_seq', 'mr_seq', 'sv_seq', 'cv_seq', 'coil_seq', 'ct_seq'
  ];
begin
  if not is_app_admin() then
    raise exception 'Sirf admin ye kar sakta hai';
  end if;

  /* Har DELETE aur UPDATE par "where true" lazmi hai (safeupdate) —
     tafseel 28 wali file mein. */

  perform set_config('app.wipe_mode', 'true', true);

  -- ---------- Own Stock Conversion ----------
  delete from stock_conversion_outputs where true;
  delete from stock_conversion_inputs  where true;
  delete from stock_conversions        where true;

  -- ---------- Party Cutting / Processing (lines pehle, phir headers) ----------
  delete from service_invoice_challans where true;
  delete from service_invoice_jobs     where true;
  delete from service_invoice_lines    where true;
  delete from service_invoices         where true;
  delete from delivery_challan_lines   where true;
  delete from delivery_challans        where true;
  delete from material_return_lines    where true;
  delete from material_returns         where true;
  delete from cutting_job_outputs      where true;
  delete from cutting_job_inputs       where true;
  delete from cutting_jobs             where true;
  delete from coil_transfers           where true;
  delete from coils                    where true;
  delete from material_inwards         where true;

  -- ---------- Accounting ----------
  delete from voucher_lines          where true;
  delete from quotation_lines        where true;
  delete from po_lines               where true;
  delete from sales_return_lines     where true;
  delete from stock_transfer_lines   where true;
  delete from stock_adjustments      where true;
  delete from audit_log              where true;
  delete from item_cost_snapshot     where true;
  delete from party_opening_balances where true;
  delete from vouchers               where true;
  delete from quotations             where true;
  delete from purchase_orders        where true;
  delete from sales_returns          where true;
  delete from stock_transfers        where true;
  delete from sheets                 where true;

  update items set avg_cost = 0, stock_qty = 0 where true;
  update period_lock set locked_before = null where id = 1;

  if p_include_masters then
    -- item_units khud urh jati hain — items par cascade laga hua hai
    delete from parties   where true;
    delete from items     where true;
    delete from companies where true;
  end if;

  perform set_config('app.wipe_mode', 'false', true);

  /* ---------- Ginti wapas 1 par ---------- (tafseel 28 mein) */
  foreach s in array seqs loop
    if to_regclass('public.' || s) is not null then
      perform setval(s::regclass, 1, false);
    end if;
  end loop;

  return jsonb_build_object(
    'status', 'ok',
    'masters_deleted', p_include_masters,
    'sequences_reset', array_length(seqs, 1)
  );
end;
$function$;

revoke all on function public.wipe_test_data(boolean) from public, anon;
grant execute on function public.wipe_test_data(boolean) to authenticated;


-- ============================================================
--  Jaanch (sirf parhne wali — chala kar dekh lein)
--
--  1. Har transfer ki nayi coil ka wazan transfer ke barabar:
--     select t.tno, t.weight, c.received_weight from coil_transfers t
--       join coils c on c.id = t.to_coil_id
--      where t.status = 'active' and c.received_weight <> t.weight;      -- 0 rows
--
--  2. Coil ke transfer out ka jama transferred_out_weight ke barabar:
--     select c.coil_serial, c.transferred_out_weight, x.s from coils c
--       left join lateral (select coalesce(sum(weight),0) s from coil_transfers
--                           where from_coil_id = c.id and status = 'active'
--                             and deleted_at is null) x on true
--      where c.transferred_out_weight <> x.s;                            -- 0 rows
--
--  3. Kisi coil ka raw_balance manfi:
--     select coil_serial, raw_balance from coils where raw_balance < 0;  -- 0 rows
-- ============================================================
