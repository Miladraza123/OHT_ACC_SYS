-- ============================================================
--  15 — Cutting / Processing: Functions & Triggers
--
--  Bunyadi usool: coil ke tamam balances SIRF trigger se badalte
--  hain, kabhi frontend se nahi. Har trigger source rows ko dobara
--  jama kar ke likhta hai (delta jama nahi karta) — is liye edit,
--  cancel ya reversal ke baad bhi balance kabhi ghalat nahi hota.
-- ============================================================

-- ---------- Document numbering (concurrency-safe) ----------

create or replace function public.assign_cutting_number()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  s      record;
  prefix text;
  seq    text;
  col    text := TG_ARGV[0];
  cur    text;
begin
  cur := to_jsonb(NEW) ->> col;
  if cur is not null and trim(cur) <> '' then
    return NEW;                       -- user ne khud number diya hai
  end if;

  select * into s from cutting_settings where id = 1;

  if TG_TABLE_NAME = 'material_inwards' then
    prefix := coalesce(s.inward_prefix, 'MI');          seq := 'mi_seq';
  elsif TG_TABLE_NAME = 'cutting_jobs' then
    prefix := coalesce(s.job_prefix, 'CJ');             seq := 'cj_seq';
  elsif TG_TABLE_NAME = 'delivery_challans' then
    prefix := coalesce(s.challan_prefix, 'DC');         seq := 'dc_seq';
  elsif TG_TABLE_NAME = 'material_returns' then
    prefix := coalesce(s.return_prefix, 'MR');          seq := 'mr_seq';
  elsif TG_TABLE_NAME = 'service_invoices' then
    prefix := coalesce(s.service_invoice_prefix, 'SV'); seq := 'sv_seq';
  else
    return NEW;
  end if;

  cur := prefix || '-' || lpad(nextval(seq::regclass)::text, 4, '0');

  NEW := jsonb_populate_record(NEW, jsonb_build_object(col, cur));
  return NEW;
end;
$function$;

-- Coil serial: CUT-2026-000154
create or replace function public.assign_coil_serial()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare prefix text;
begin
  if NEW.coil_serial is not null and trim(NEW.coil_serial) <> '' then
    return NEW;
  end if;
  select coalesce(coil_serial_prefix, 'CUT') into prefix from cutting_settings where id = 1;
  NEW.coil_serial := coalesce(prefix, 'CUT') || '-'
                  || to_char(coalesce(NEW.received_date, current_date), 'YYYY') || '-'
                  || lpad(nextval('coil_seq')::text, 6, '0');
  return NEW;
end;
$function$;

-- ============================================================
--  Coil balances — poora hisaab dobara jama kar ke
-- ============================================================

create or replace function public.recalc_coil_balances(p_coil_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_consumed  numeric;
  v_returned  numeric;
  v_finished  numeric;
  v_delivered numeric;
begin
  if p_coil_id is null then return; end if;

  -- Cutting jobs mein gaya raw maal (cancelled/deleted jobs shumar nahi)
  select coalesce(sum(i.input_weight), 0) into v_consumed
    from cutting_job_inputs i
    join cutting_jobs j on j.id = i.job_id
   where i.coil_id = p_coil_id and j.deleted_at is null and j.status <> 'cancelled';

  -- Jobs se bana hua maal
  select coalesce(sum(o.output_weight), 0) into v_finished
    from cutting_job_outputs o
    join cutting_jobs j on j.id = o.job_id
   where o.coil_id = p_coil_id and j.deleted_at is null and j.status <> 'cancelled';

  -- Raw wapsi
  select coalesce(sum(l.return_weight), 0) into v_returned
    from material_return_lines l
    join material_returns r on r.id = l.return_id
   where l.coil_id = p_coil_id and r.deleted_at is null and r.status <> 'cancelled';

  -- Delivery — ACTUAL tola gaya weight
  select coalesce(sum(l.delivered_weight), 0) into v_delivered
    from delivery_challan_lines l
    join delivery_challans d on d.id = l.challan_id
   where l.coil_id = p_coil_id and d.deleted_at is null and d.status <> 'cancelled';

  perform set_config('app.system_write', 'true', true);
  update coils
     set consumed_weight  = v_consumed,
         finished_weight  = v_finished,
         returned_weight  = v_returned,
         delivered_weight = v_delivered
   where id = p_coil_id;
  perform set_config('app.system_write', 'false', true);
end;
$function$;

-- Line-level trigger: jis coil par asar para, usay dobara gino
create or replace function public.trg_recalc_coil_from_line()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if TG_OP = 'DELETE' then
    perform recalc_coil_balances(OLD.coil_id);
    return OLD;
  end if;
  perform recalc_coil_balances(NEW.coil_id);
  if TG_OP = 'UPDATE' and OLD.coil_id is distinct from NEW.coil_id then
    perform recalc_coil_balances(OLD.coil_id);
  end if;
  return NEW;
end;
$function$;

-- Header-level trigger: status/delete badle to us document ki tamam coils dobara gino
create or replace function public.trg_recalc_coils_from_header()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c   uuid;
  tbl text := TG_ARGV[0];   -- child table
  fk  text := TG_ARGV[1];   -- child ka foreign key column
begin
  if NEW.status is not distinct from OLD.status
     and NEW.deleted_at is not distinct from OLD.deleted_at then
    return NEW;
  end if;

  for c in execute format('select distinct coil_id from %I where %I = $1', tbl, fk) using NEW.id
  loop
    perform recalc_coil_balances(c);
  end loop;
  return NEW;
end;
$function$;

-- ============================================================
--  Hifazati checks
-- ============================================================

-- Band ya cancelled coil par naya kaam nahi ho sakta
create or replace function public.trg_check_coil_usable()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare c record;
begin
  select * into c from coils where id = NEW.coil_id;
  if not found then
    raise exception 'Coil mojood nahi';
  end if;
  if c.deleted_at is not null then
    raise exception 'Coil % delete ho chuki hai', c.coil_serial;
  end if;
  if c.status <> 'active' then
    raise exception 'Coil % ka status "%" hai — is par naya kaam nahi ho sakta', c.coil_serial, c.status;
  end if;
  if c.ownership <> 'party' then
    raise exception 'Coil % company ka apna maal hai — party processing mein istemaal nahi ho sakta', c.coil_serial;
  end if;
  return NEW;
end;
$function$;

-- Job output ki coil job ke input mein bhi honi chahiye
create or replace function public.trg_check_output_coil()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not exists (select 1 from cutting_job_inputs where job_id = NEW.job_id and coil_id = NEW.coil_id) then
    raise exception 'Output ki coil pehle job ke input mein add karein';
  end if;
  return NEW;
end;
$function$;

-- Poore document mein ek hi party ka maal ho
create or replace function public.trg_check_same_party()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  hdr_party  uuid;
  coil_party uuid;
  tbl    text := TG_ARGV[0];   -- header table
  fk     text := TG_ARGV[1];   -- is row mein header ka id kis column mein hai
  hdr_id uuid;
begin
  hdr_id := (to_jsonb(NEW) ->> fk)::uuid;
  if hdr_id is null then return NEW; end if;

  execute format('select party_id from %I where id = $1', tbl) into hdr_party using hdr_id;
  select party_id into coil_party from coils where id = NEW.coil_id;

  if hdr_party is distinct from coil_party then
    raise exception 'Yeh coil kisi doosri party ki hai — ek document mein sirf ek party ka maal aa sakta hai';
  end if;
  return NEW;
end;
$function$;

-- Job ko "completed" karna alag ijazat maangta hai
-- (completed hote hi job Service Invoice par bill ke liye aa jata hai)
create or replace function public.trg_check_job_complete()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if NEW.status = 'completed'
     and (TG_OP = 'INSERT' or OLD.status is distinct from 'completed') then
    if not (is_app_admin() or has_perm('cutting_job_complete')) then
      raise exception 'Permission denied: cutting_job_complete zaroori hai job complete karne ke liye';
    end if;
    if NEW.completed_at is null then NEW.completed_at := now(); end if;
    if NEW.completed_by is null then NEW.completed_by := auth.uid(); end if;
  end if;
  return NEW;
end;
$function$;

-- Ek job dobara bill na ho
create or replace function public.trg_check_job_not_billed()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare inv record;
begin
  select si.sino, si.deleted_at, si.status into inv
    from service_invoice_jobs sij
    join service_invoices si on si.id = sij.invoice_id
   where sij.job_id = NEW.job_id and sij.invoice_id <> NEW.invoice_id
     and si.deleted_at is null and si.status <> 'cancelled'
   limit 1;

  if found then
    raise exception 'Yeh job pehle hi invoice % par bill ho chuka hai', inv.sino;
  end if;
  return NEW;
end;
$function$;

-- Delivery us se zyada na ho jitna maal ban chuka hai
create or replace function public.trg_check_delivery_available()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c            record;
  already      numeric;
  avail        numeric;
begin
  select * into c from coils where id = NEW.coil_id;
  if not found then raise exception 'Coil mojood nahi'; end if;

  select coalesce(sum(l.delivered_weight), 0) into already
    from delivery_challan_lines l
    join delivery_challans d on d.id = l.challan_id
   where l.coil_id = NEW.coil_id and d.deleted_at is null and d.status <> 'cancelled'
     and l.id <> NEW.id;

  avail := c.finished_weight - already;

  if NEW.delivered_weight > avail then
    raise exception 'Coil % par sirf % KG delivery ke liye tayyar hai', c.coil_serial, avail;
  end if;
  return NEW;
end;
$function$;

-- ============================================================
--  Coil closing — requirement 16, 17, 18
--
--  System KABHI khud coil band nahi karta. User se poocha jata hai.
--  Bacha hua balance "Closing Adjustment / Weight Variance" ke tor
--  par likha jata hai — usay khud-ba-khud Scrap NAHI banaya jata.
-- ============================================================

create or replace function public.close_coil(
  p_coil_id uuid,
  p_reason  text default 'other',
  p_remarks text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c         record;
  threshold numeric;
  leftover  numeric;
begin
  if not (is_app_admin() or has_perm('cutting_coil_close')) then
    raise exception 'Permission denied: cutting_coil_close zaroori hai';
  end if;

  -- FOR UPDATE — do users ek saath band na kar saken
  select * into c from coils where id = p_coil_id for update;
  if not found then raise exception 'Coil mojood nahi'; end if;
  if c.status = 'closed' then
    return jsonb_build_object('status', 'already_closed', 'coil_serial', c.coil_serial);
  end if;
  if c.deleted_at is not null then raise exception 'Coil delete ho chuki hai'; end if;

  if c.pending_delivery > 0 then
    raise exception 'Coil % par % KG maal abhi delivery ke liye para hai — pehle challan banayein',
      c.coil_serial, c.pending_delivery;
  end if;

  leftover := c.raw_balance;

  perform set_config('app.system_write', 'true', true);
  update coils
     set closing_adjust_weight = closing_adjust_weight + leftover,
         status          = 'closed',
         closed_at       = now(),
         closed_by       = auth.uid(),
         closing_reason  = coalesce(p_reason, 'other'),
         closing_remarks = p_remarks
   where id = p_coil_id;
  perform set_config('app.system_write', 'false', true);

  perform log_manual_audit('coils', p_coil_id, c.coil_serial, 'coil_closed',
    jsonb_build_object('closing_adjustment_kg', leftover,
                       'reason', coalesce(p_reason, 'other'),
                       'remarks', p_remarks));

  select coalesce(coil_finish_threshold_kg, 200) into threshold from cutting_settings where id = 1;

  return jsonb_build_object(
    'status', 'closed',
    'coil_serial', c.coil_serial,
    'closing_adjustment_kg', leftover,
    'threshold_kg', threshold,
    'was_above_threshold', leftover > threshold
  );
end;
$function$;

-- Band coil dobara kholna (ghalti se band ho gayi ho)
create or replace function public.reopen_coil(p_coil_id uuid, p_remarks text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare c record; adj numeric;
begin
  if not (is_app_admin() or has_perm('cutting_coil_close')) then
    raise exception 'Permission denied: cutting_coil_close zaroori hai';
  end if;

  select * into c from coils where id = p_coil_id for update;
  if not found then raise exception 'Coil mojood nahi'; end if;
  if c.status <> 'closed' then
    return jsonb_build_object('status', 'not_closed', 'coil_serial', c.coil_serial);
  end if;

  adj := c.closing_adjust_weight;

  perform set_config('app.system_write', 'true', true);
  update coils
     set closing_adjust_weight = 0,
         status          = 'active',
         closed_at       = null,
         closed_by       = null,
         closing_reason  = null,
         closing_remarks = null
   where id = p_coil_id;
  perform set_config('app.system_write', 'false', true);

  perform log_manual_audit('coils', p_coil_id, c.coil_serial, 'coil_reopened',
    jsonb_build_object('reversed_adjustment_kg', adj, 'remarks', p_remarks));

  return jsonb_build_object('status', 'reopened', 'coil_serial', c.coil_serial,
                            'restored_balance_kg', adj);
end;
$function$;

-- ---------- Service Invoice ke totals (server side par) ----------

create or replace function public.recalc_service_invoice_totals(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_sub numeric; v_tax numeric; inv record;
begin
  select * into inv from service_invoices where id = p_invoice_id;
  if not found then return; end if;

  select coalesce(sum(round(qty * rate, 2)), 0) into v_sub
    from service_invoice_lines where invoice_id = p_invoice_id;

  if inv.tax_on then
    select coalesce(sum(round(round(qty * rate, 2) * tax_pct / 100, 2)), 0) into v_tax
      from service_invoice_lines where invoice_id = p_invoice_id;
  else
    v_tax := 0;
  end if;

  perform set_config('app.system_write', 'true', true);
  update service_invoices
     set sub_total   = v_sub,
         tax_total   = v_tax,
         grand_total = round(v_sub - coalesce(discount, 0) + v_tax, 2)
   where id = p_invoice_id;
  perform set_config('app.system_write', 'false', true);
end;
$function$;

-- BEFORE: line ka amount khud bhar do (frontend par bharosa nahi)
create or replace function public.trg_service_line_amount()
returns trigger
language plpgsql
as $function$
begin
  NEW.amount := round(NEW.qty * NEW.rate, 2);
  return NEW;
end;
$function$;

-- AFTER: header ke totals dobara jama karo
create or replace function public.trg_service_invoice_totals()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform recalc_service_invoice_totals(coalesce(NEW.invoice_id, OLD.invoice_id));
  return coalesce(NEW, OLD);
end;
$function$;

create or replace function public.trg_service_invoice_header_totals()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if NEW.discount is not distinct from OLD.discount
     and NEW.tax_on is not distinct from OLD.tax_on then
    return NEW;
  end if;
  perform recalc_service_invoice_totals(NEW.id);
  return NEW;
end;
$function$;
