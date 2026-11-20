-- ============================================================
--  39 — Cutting Job: SUB ORDERS
--
--  Ek Cutting Job ke andar kai Sub Order (SO-1, SO-2 ...). Har sub order
--  ka apna input (coil + KG), apni cutting sizes, apni delivery aur apna
--  bill ho sakta hai — ya kai sub orders ek saath ek challan / invoice par.
--
--  * cutting_sub_orders table; inputs / outputs / invoice-jobs mein
--    sub_order_id. Purane har job ko "SO-1" mil jata hai, us ki saari
--    lines us par — purana kaam bilkul waisa hi.
--  * Tala (challan / bill ke baad badalna mana) ab SUB ORDER par: ek sub
--    order deliver / bill ho jaye to usi job ke doosre sub orders badle ja
--    sakte hain. Job cancel / draft: ab bhi tab tak nahi jab tak koi bhi
--    sub order deliver / bill ho.
--  * Bill: ek sub order ek hi zinda invoice par. Purana (bina sub order)
--    client chale to us job ka pehla unbilled sub order utha leta hai.
--  * Naya view unbilled_sub_orders_v. Purane views / RPC nahi chhere.
--
--  Dobara chalana mehfooz hai.
-- ============================================================


-- ============================================================
--  HISSA 1 — table, columns, RLS
-- ============================================================

create table if not exists public.cutting_sub_orders (
  id          uuid        not null default gen_random_uuid(),
  job_id      uuid        not null,
  sub_no      integer     not null,
  name        text        not null default ''::text,
  created_at  timestamptz not null default now(),
  created_by  uuid,
  updated_at  timestamptz,
  updated_by  uuid
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'cutting_sub_orders_pkey') then
    alter table public.cutting_sub_orders add constraint cutting_sub_orders_pkey primary key (id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'cutting_sub_orders_job_fkey') then
    alter table public.cutting_sub_orders add constraint cutting_sub_orders_job_fkey
      foreign key (job_id) references public.cutting_jobs(id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'cutting_sub_orders_no_pos') then
    alter table public.cutting_sub_orders add constraint cutting_sub_orders_no_pos check (sub_no > 0);
  end if;
end $$;

create unique index if not exists cutting_sub_orders_job_no_uniq on public.cutting_sub_orders (job_id, sub_no);
create index if not exists cutting_sub_orders_job_idx on public.cutting_sub_orders (job_id);

alter table public.cutting_job_inputs  add column if not exists sub_order_id uuid;
alter table public.cutting_job_outputs add column if not exists sub_order_id uuid;
alter table public.service_invoice_jobs add column if not exists sub_order_id uuid;

do $$
declare t text;
begin
  foreach t in array array['cutting_job_inputs', 'cutting_job_outputs', 'service_invoice_jobs'] loop
    if not exists (select 1 from pg_constraint where conname = t || '_sub_fkey') then
      execute format('alter table public.%I add constraint %I foreign key (sub_order_id) references public.cutting_sub_orders(id)',
                     t, t || '_sub_fkey');
    end if;
    execute format('create index if not exists %I on public.%I (sub_order_id)', t || '_sub_idx', t);
  end loop;
end $$;

alter table public.cutting_sub_orders enable row level security;

drop policy if exists "cutting_sub_orders select" on public.cutting_sub_orders;
drop policy if exists "cutting_sub_orders write"  on public.cutting_sub_orders;
drop policy if exists "active user only"          on public.cutting_sub_orders;

create policy "cutting_sub_orders select" on public.cutting_sub_orders for select
  using (is_app_admin() or has_perm('cutting_job_view') or has_perm('service_invoice_view')
         or has_perm('cutting_challan_view'));
create policy "cutting_sub_orders write" on public.cutting_sub_orders for all
  using (is_app_admin() or has_perm('cutting_job_create') or has_perm('cutting_job_edit'))
  with check (is_app_admin() or has_perm('cutting_job_create') or has_perm('cutting_job_edit'));
create policy "active user only" on public.cutting_sub_orders as restrictive for all to authenticated
  using ((select is_active_app_user()))
  with check ((select is_active_app_user()));

revoke all on public.cutting_sub_orders from anon;
revoke all on public.cutting_sub_orders from public;
grant select, insert, update, delete on public.cutting_sub_orders to authenticated;
grant all on public.cutting_sub_orders to service_role;


-- ============================================================
--  HISSA 2 — sub_no khud, naam / job ka rishta
-- ============================================================

create or replace function public.trg_sub_order_number()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if TG_OP = 'INSERT' then
    -- ek hi job mein do sub order ek saath banen to alag number mile
    perform pg_advisory_xact_lock(hashtextextended('sub_order:' || NEW.job_id::text, 0));
    if NEW.sub_no is null or NEW.sub_no <= 0 then
      select coalesce(max(sub_no), 0) + 1 into NEW.sub_no from cutting_sub_orders where job_id = NEW.job_id;
    end if;
  elsif NEW.job_id is distinct from OLD.job_id or NEW.sub_no is distinct from OLD.sub_no then
    raise exception 'Sub order ka job aur number badla nahi ja sakta';
  end if;
  NEW.name := coalesce(left(btrim(NEW.name), 120), '');
  return NEW;
end;
$function$;

drop trigger if exists trg_00_sub_order_number on public.cutting_sub_orders;
drop trigger if exists trg_audit_sub_orders    on public.cutting_sub_orders;
create trigger trg_00_sub_order_number before insert or update on public.cutting_sub_orders
  for each row execute function trg_sub_order_number();
create trigger trg_audit_sub_orders before insert or update on public.cutting_sub_orders
  for each row execute function stamp_audit_fields();

-- Line par sub order na ho (purana client) to job ka pehla sub order (na ho to banao);
-- ho to wohi job ka ho.
create or replace function public.trg_fill_sub_order()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v uuid;
begin
  if NEW.sub_order_id is null then
    select id into v from cutting_sub_orders where job_id = NEW.job_id order by sub_no limit 1;
    if v is null then
      insert into cutting_sub_orders (job_id, sub_no, name) values (NEW.job_id, 1, '') returning id into v;
    end if;
    NEW.sub_order_id := v;
  elsif not exists (select 1 from cutting_sub_orders where id = NEW.sub_order_id and job_id = NEW.job_id) then
    raise exception 'Yeh sub order is job ka nahi hai';
  end if;
  return NEW;
end;
$function$;

drop trigger if exists trg_00_fill_sub_order on public.cutting_job_inputs;
drop trigger if exists trg_00_fill_sub_order on public.cutting_job_outputs;
create trigger trg_00_fill_sub_order before insert or update on public.cutting_job_inputs
  for each row execute function trg_fill_sub_order();
create trigger trg_00_fill_sub_order before insert or update on public.cutting_job_outputs
  for each row execute function trg_fill_sub_order();

-- Output ki coil usi SUB ORDER ke input mein honi chahiye
create or replace function public.trg_check_output_coil()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not exists (select 1 from cutting_job_inputs
                  where job_id = NEW.job_id and coil_id = NEW.coil_id
                    and sub_order_id is not distinct from NEW.sub_order_id) then
    raise exception 'Output ki coil pehle usi sub order ke input mein add karein';
  end if;
  return NEW;
end;
$function$;


-- ============================================================
--  HISSA 3 — purane jobs: har job ko SO-1, saari lines us par
-- ============================================================

do $$
begin
  perform set_config('app.system_write', 'true', true);
  -- sirf sub_order_id bhar rahe hain — wazan nahi badalta, is liye line triggers band
  alter table public.cutting_job_inputs   disable trigger user;
  alter table public.cutting_job_outputs  disable trigger user;
  alter table public.service_invoice_jobs disable trigger user;

  insert into cutting_sub_orders (job_id, sub_no, name)
  select j.id, 1, '' from cutting_jobs j
   where not exists (select 1 from cutting_sub_orders s where s.job_id = j.id);

  update cutting_job_inputs i set sub_order_id = s.id
    from cutting_sub_orders s where s.job_id = i.job_id and s.sub_no = 1 and i.sub_order_id is null;
  update cutting_job_outputs o set sub_order_id = s.id
    from cutting_sub_orders s where s.job_id = o.job_id and s.sub_no = 1 and o.sub_order_id is null;
  update service_invoice_jobs x set sub_order_id = s.id
    from cutting_sub_orders s where s.job_id = x.job_id and s.sub_no = 1 and x.sub_order_id is null;

  alter table public.cutting_job_inputs   enable trigger user;
  alter table public.cutting_job_outputs  enable trigger user;
  alter table public.service_invoice_jobs enable trigger user;
  perform set_config('app.system_write', 'false', true);
end $$;


-- ============================================================
--  HISSA 4 — sub order ke helper (tala / label)
-- ============================================================

create or replace function public.cutting_sub_label(p_sub uuid)
returns text
language sql
stable
security definer
set search_path to 'public'
as $function$
  select 'SO-' || s.sub_no || case when s.name <> '' then ' (' || s.name || ')' else '' end
    from cutting_sub_orders s where s.id = p_sub;
$function$;

-- Sub order ka maal kisi zinda challan par gaya hai?
create or replace function public.cutting_sub_is_delivered(p_sub uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (
    select 1 from delivery_challan_lines l
      join delivery_challans d on d.id = l.challan_id
      join cutting_job_outputs o on o.id = l.output_id
     where o.sub_order_id = p_sub and d.deleted_at is null and d.status <> 'cancelled');
$function$;

-- Sub order kis zinda invoice par bill hai (null = kisi par nahi)
create or replace function public.cutting_sub_invoice_no(p_sub uuid, p_except uuid default null)
returns text
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(si.sino, '(bina number)')
    from service_invoice_jobs sij
    join service_invoices si on si.id = sij.invoice_id
   where sij.sub_order_id = p_sub
     and si.deleted_at is null and si.status <> 'cancelled'
     and si.id is distinct from p_except
   limit 1;
$function$;

-- Challan kisi zinda invoice se jura hai — seedha ya us ki kisi line ka SUB ORDER bill ho chuka hai
create or replace function public.cutting_challan_invoice_no(p_challan uuid)
returns text
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(
    (select coalesce(si.sino, '(bina number)')
       from service_invoice_challans sic
       join service_invoices si on si.id = sic.invoice_id
      where sic.challan_id = p_challan and si.deleted_at is null and si.status <> 'cancelled'
      limit 1),
    (select coalesce(cutting_sub_invoice_no(o.sub_order_id), case when o.id is null then cutting_job_invoice_no(l.job_id) end)
       from delivery_challan_lines l
       left join cutting_job_outputs o on o.id = l.output_id
      where l.challan_id = p_challan
        and coalesce(cutting_sub_invoice_no(o.sub_order_id),
                     case when o.id is null and l.job_id is not null then cutting_job_invoice_no(l.job_id) end) is not null
      limit 1));
$function$;


-- ============================================================
--  HISSA 5 — line tala: ab sub order par
-- ============================================================

create or replace function public.trg_cutting_line_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  kind      text := TG_ARGV[0];      -- job | challan | invoice | return
  edit_perm text;
  hdr_tbl   text;
  fk        text;
  ids       uuid[];
  hid       uuid;
  h         record;
  v_admin   boolean := is_app_admin();
  v_inv     text;
  subs      uuid[];
  sid       uuid;
  v_oid     uuid;
  v_sub     uuid;
  v_exists  boolean;
begin
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    return coalesce(NEW, OLD);
  end if;

  -- INSERT ... ON CONFLICT (Restore ka upsert): id pehle se maujood ho to yeh asal mein UPDATE hai —
  -- badli hui row ko UPDATE ka apna tala rokta hai, bilkul wohi row guzar jati hai. Pehle yahan
  -- bill ho chuke job ki lines ka Restore (chahe "sirf ghaayab" mode) rok diya jata tha.
  if TG_OP = 'INSERT' and (to_jsonb(NEW) ->> 'id') is not null then
    execute format('select exists (select 1 from public.%I where id = $1)', TG_TABLE_NAME)
      into v_exists using (to_jsonb(NEW) ->> 'id')::uuid;
    if v_exists then return NEW; end if;
  end if;

  -- bilkul wohi row dobara (Restore upsert) — kuch nahi badla
  if TG_OP = 'UPDATE'
     and (to_jsonb(NEW) - 'variance_kg') = (to_jsonb(OLD) - 'variance_kg') then
    return NEW;
  end if;

  if kind = 'job' then
    hdr_tbl := 'cutting_jobs';      fk := 'job_id';     edit_perm := 'cutting_job_edit';
  elsif kind = 'challan' then
    hdr_tbl := 'delivery_challans'; fk := 'challan_id'; edit_perm := 'cutting_challan_edit';
  elsif kind = 'invoice' then
    hdr_tbl := 'service_invoices';  fk := 'invoice_id'; edit_perm := 'service_invoice_edit';
  else
    hdr_tbl := 'material_returns';  fk := 'return_id';  edit_perm := null;   -- return mein edit ijazat nahi
  end if;

  if TG_OP <> 'INSERT' then ids := array[(to_jsonb(OLD) ->> fk)::uuid]; end if;
  if TG_OP <> 'DELETE' and (ids is null or (to_jsonb(NEW) ->> fk)::uuid <> all (ids)) then
    ids := coalesce(ids, '{}') || (to_jsonb(NEW) ->> fk)::uuid;
  end if;

  foreach hid in array ids loop
    execute format('select id, created_by, created_at, deleted_at, status, %s as doc_no from %I where id = $1',
                   case kind when 'job' then 'jno' when 'challan' then 'dno'
                             when 'invoice' then 'sino' else 'rno' end, hdr_tbl)
       into h using hid;
    if h.id is null then continue; end if;   -- header hi delete ho raha hai (cascade) ya FK rokegi

    -- 1. hisaab ka tala — sab ke liye
    if kind = 'job' then
      -- Tala ab SUB ORDER par hai: jis sub order ka maal challan / bill par gaya sirf wohi lock;
      -- usi job ke doosre sub orders badle ja sakte hain. Sub order na ho to purana job-level tala.
      subs := '{}';
      if TG_OP <> 'INSERT' and (to_jsonb(OLD) ->> 'sub_order_id') is not null then
        subs := subs || (to_jsonb(OLD) ->> 'sub_order_id')::uuid;
      end if;
      if TG_OP <> 'DELETE' and (to_jsonb(NEW) ->> 'sub_order_id') is not null
         and (to_jsonb(NEW) ->> 'sub_order_id')::uuid <> all (subs) then
        subs := subs || (to_jsonb(NEW) ->> 'sub_order_id')::uuid;
      end if;
      if cardinality(subs) = 0 then
        v_inv := cutting_job_invoice_no(hid);
        if v_inv is not null then
          raise exception 'Job % invoice % par bill ho chuka hai — is ke input / sizes nahi badal sakte. Pehle invoice cancel karein.', h.doc_no, v_inv;
        end if;
        if cutting_job_is_delivered(hid) then
          raise exception 'Job % ka maal challan par ja chuka hai — is ke input / sizes nahi badal sakte. Pehle challan cancel karein.', h.doc_no;
        end if;
      else
        foreach sid in array subs loop
          v_inv := cutting_sub_invoice_no(sid);
          if v_inv is not null then
            raise exception 'Job % ka % invoice % par bill ho chuka hai — is ke input / sizes nahi badal sakte. Pehle invoice cancel karein.', h.doc_no, cutting_sub_label(sid), v_inv;
          end if;
          if cutting_sub_is_delivered(sid) then
            raise exception 'Job % ka % maal challan par ja chuka hai — is ke input / sizes nahi badal sakte. Pehle challan cancel karein.', h.doc_no, cutting_sub_label(sid);
          end if;
        end loop;
      end if;
    elsif kind = 'challan' and TG_OP <> 'INSERT' then
      v_inv := cutting_challan_invoice_no(hid);
      if v_inv is not null then
        raise exception 'Challan % ka maal invoice % par bill ho chuka hai — is ki lines nahi badal sakti', h.doc_no, v_inv;
      end if;
    end if;

    if v_admin then continue; end if;

    -- 2. cancel / delete document
    if h.deleted_at is not null or h.status = 'cancelled' then
      raise exception '% cancel / delete ho chuka hai — is ki lines nahi badal sakti', coalesce(h.doc_no, 'Document');
    end if;

    -- 3. ijazat — header jaisa qaida
    if edit_perm is not null and not has_perm(edit_perm) then
      if not (TG_OP = 'INSERT' and h.created_by = auth.uid()
              and h.created_at > now() - interval '15 minutes') then
        raise exception 'Permission denied: % zaroori hai % ki lines badalne ke liye', edit_perm, coalesce(h.doc_no, 'document');
      end if;
    end if;
  end loop;

  -- challan line: jis job ki line badal / hat rahi hai wo bill ho chuka ho
  if kind = 'challan' and TG_OP <> 'INSERT' then
    v_oid := (to_jsonb(OLD) ->> 'output_id')::uuid;
    select o.sub_order_id into v_sub from cutting_job_outputs o where o.id = v_oid;
    v_inv := case when v_sub is not null then cutting_sub_invoice_no(v_sub)
                  else cutting_job_invoice_no((to_jsonb(OLD) ->> 'job_id')::uuid) end;
    if v_inv is not null then
      raise exception 'Is line ka sub order / job invoice % par bill ho chuka hai — line nahi badal sakti', v_inv;
    end if;
  end if;

  return coalesce(NEW, OLD);
end;
$function$;


drop trigger if exists trg_guard_job_input  on public.cutting_job_inputs;
drop trigger if exists trg_guard_job_output on public.cutting_job_outputs;
create trigger trg_guard_job_input  before insert or update or delete on public.cutting_job_inputs
  for each row execute function trg_cutting_line_guard('job');
create trigger trg_guard_job_output before insert or update or delete on public.cutting_job_outputs
  for each row execute function trg_cutting_line_guard('job');


-- ============================================================
--  HISSA 6 — bill: ek sub order ek hi zinda invoice par
-- ============================================================

drop index if exists public.service_invoice_jobs_inv_job_uniq;
create unique index if not exists service_invoice_jobs_inv_sub_uniq
  on public.service_invoice_jobs (invoice_id, sub_order_id) where sub_order_id is not null;
create unique index if not exists service_invoice_jobs_inv_job_nosub_uniq
  on public.service_invoice_jobs (invoice_id, job_id) where sub_order_id is null;

create or replace function public.check_sub_billable(p_invoice_id uuid, p_job_id uuid, p_sub uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  inv   record;
  j     record;
  other text;
begin
  select * into inv from service_invoices where id = p_invoice_id;
  if not found then return; end if;
  -- cancel / delete invoice ki link sirf tareekh hai
  if inv.deleted_at is not null or inv.status = 'cancelled' then return; end if;

  select * into j from cutting_jobs where id = p_job_id for update;
  if not found then return; end if;     -- FK rokegi

  if j.deleted_at is not null or j.status <> 'completed' then
    raise exception 'Job % abhi Completed nahi (halat: %) — bill nahi ho sakta',
      j.jno, case when j.deleted_at is not null then 'deleted' else j.status end;
  end if;
  if j.party_id is distinct from inv.party_id then
    raise exception 'Job % kisi aur party ka hai — is invoice par bill nahi ho sakta', j.jno;
  end if;
  if not exists (select 1 from cutting_sub_orders where id = p_sub and job_id = p_job_id) then
    raise exception 'Yeh sub order job % ka nahi hai', j.jno;
  end if;

  other := cutting_sub_invoice_no(p_sub, p_invoice_id);
  if other is not null then
    raise exception 'Job % ka % pehle hi invoice % par bill ho chuka hai', j.jno, cutting_sub_label(p_sub), other;
  end if;
end;
$function$;

create or replace function public.trg_check_job_not_billed()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_sub uuid := NEW.sub_order_id;
begin
  if v_sub is null then
    -- purana client: job ka pehla abhi unbilled sub order
    select s.id into v_sub from cutting_sub_orders s
     where s.job_id = NEW.job_id and cutting_sub_invoice_no(s.id, NEW.invoice_id) is null
     order by s.sub_no limit 1;
    if v_sub is null then
      if exists (select 1 from cutting_sub_orders where job_id = NEW.job_id) then
        raise exception 'Yeh job pehle hi bill ho chuka hai (is ke saare sub orders bill hain)';
      end if;
      perform check_job_billable(NEW.invoice_id, NEW.job_id);   -- sub order wala job hi nahi: purana qaida
      return NEW;
    end if;
    NEW.sub_order_id := v_sub;
  end if;
  perform check_sub_billable(NEW.invoice_id, NEW.job_id, v_sub);
  return NEW;
end;
$function$;

create or replace function public.trg_invoice_state_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare jid uuid; sid uuid;
begin
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    return NEW;
  end if;
  if NEW.status = 'cancelled' or NEW.deleted_at is not null then return NEW; end if;

  if OLD.status = 'cancelled' or OLD.deleted_at is not null
     or NEW.party_id is distinct from OLD.party_id then
    for jid, sid in select job_id, sub_order_id from service_invoice_jobs where invoice_id = NEW.id loop
      -- NEW abhi table mein nahi — is liye party yahan khud dekhte hain
      if exists (select 1 from cutting_jobs where id = jid and party_id is distinct from NEW.party_id) then
        raise exception 'Is invoice ka ek job kisi aur party ka hai — party nahi badal sakti';
      end if;
      -- Sub order ho to sirf wohi; warna (purani link) poora job
      if sid is not null then
        if cutting_sub_invoice_no(sid, NEW.id) is not null then
          raise exception 'Is invoice ka sub order ab invoice % par bill ho chuka hai — yeh invoice wapas zinda nahi ho sakti',
            cutting_sub_invoice_no(sid, NEW.id);
        end if;
      elsif cutting_job_invoice_no(jid, NEW.id) is not null then
        raise exception 'Is invoice ka job ab invoice % par bill ho chuka hai — yeh invoice wapas zinda nahi ho sakti',
          cutting_job_invoice_no(jid, NEW.id);
      end if;
    end loop;
  end if;
  return NEW;
end;
$function$;



-- ============================================================
--  HISSA 7 — view: unbilled sub orders
-- ============================================================

create or replace view public.unbilled_sub_orders_v as
select s.id            as sub_order_id,
       s.sub_no,
       s.name          as sub_name,
       j.id            as job_id,
       j.jno,
       j.jdate,
       j.party_id,
       p.name          as party_name,
       j.warehouse_id,
       coalesce((select sum(i.input_weight)  from cutting_job_inputs  i where i.sub_order_id = s.id), 0) as input_weight,
       coalesce((select sum(o.output_weight) from cutting_job_outputs o where o.sub_order_id = s.id), 0) as output_weight,
       coalesce((select sum(o.pieces)        from cutting_job_outputs o where o.sub_order_id = s.id), 0) as total_pieces
  from cutting_sub_orders s
  join cutting_jobs j on j.id = s.job_id
  join parties p on p.id = j.party_id
 where j.deleted_at is null
   and j.status = 'completed'
   and exists (select 1 from cutting_job_outputs o where o.sub_order_id = s.id)
   and not exists (
     select 1 from service_invoice_jobs sij
      join service_invoices si on si.id = sij.invoice_id
     where sij.sub_order_id = s.id and si.deleted_at is null and si.status <> 'cancelled'
   );

alter view public.unbilled_sub_orders_v set (security_invoker = on);
revoke all on public.unbilled_sub_orders_v from anon;
revoke all on public.unbilled_sub_orders_v from public;
grant select on public.unbilled_sub_orders_v to authenticated;
grant all on public.unbilled_sub_orders_v to service_role;


-- ============================================================
--  HISSA 8 — andar ke helper sirf triggers ke liye
-- ============================================================

do $$
declare f text;
begin
  foreach f in array array[
    'public.cutting_sub_label(uuid)',
    'public.cutting_sub_is_delivered(uuid)',
    'public.cutting_sub_invoice_no(uuid, uuid)',
    'public.check_sub_billable(uuid, uuid, uuid)'
  ] loop
    execute 'revoke all on function ' || f || ' from public, anon, authenticated';
  end loop;
end $$;


-- ============================================================
--  Jaanch (sirf parhne wali)
--
--  1. Har job ka kam az kam ek sub order:
--     select j.jno from cutting_jobs j
--      where not exists (select 1 from cutting_sub_orders s where s.job_id = j.id);       -- 0 rows
--  2. Koi line bina sub order ke:
--     select count(*) from cutting_job_inputs  where sub_order_id is null;                -- 0
--     select count(*) from cutting_job_outputs where sub_order_id is null;                -- 0
--  3. Line ka sub order usi job ka:
--     select count(*) from cutting_job_outputs o join cutting_sub_orders s on s.id = o.sub_order_id
--      where s.job_id <> o.job_id;                                                         -- 0
-- ============================================================
