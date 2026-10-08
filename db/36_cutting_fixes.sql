-- ============================================================
--  36 — Cutting / Processing: hisaab aur hifazat ki islahat (8 Oktober 2026)
--
--  Deep test (REPORT.md) mein cutting ke yeh masle nikle the. Har hal ke
--  upar "MASLA / HAL" likha hai. Khulasa:
--
--    C4   cutting_job_outputs.width — app yeh column likhti/parhti hai,
--         repo sirf width_mm banata tha.
--    H4   Service invoice ke totals browser ki baat par chalte the.
--    H12  Delivery tayyar (completed job ke) maal se zyada ho jati thi.
--    H13  Do challan ek saath → coil ka delivered_weight ghalat.
--    H14  Delivered / billed job cancel, inward cancel, lines ki edit
--         waghera par koi rok nahi thi.
--    M3   Cancel invoice ka job dobara bill nahi ho sakta tha.
--    M12  Conversion mein stock se zyada maal kharch ho jata tha, aur
--         source ki cost badalne par output ki cost purani rehti thi.
--    Low  Coil close scrap ki jagah raw_balance likhta tha; job cancel
--         ki ijazat ghalat dekhi jati thi; coil ledger mein 'mm' pakka.
--
--  Yeh file dobara chalane par bhi mehfooz hai (create or replace,
--  if exists / if not exists). 33 ke baad chalayein.
--
--  PURANA DATA: yeh file koi purani row nahi badalti. Jo pehle se ghalat
--  hai (maslan delivery tayyar maal se zyada, ya invoice ke totals lines
--  se mel nahi khate) wo waisa hi rehta hai — file ke aakhir mein "Jaanch"
--  wali queries se dhoondh kar haath se theek karein. Naye rok sirf naye
--  kaam par lagte hain (purani ghalti ko chhone wale kaam par bhi).
-- ============================================================


-- ============================================================
--  HISSA 1 — C4: cutting_job_outputs.width
--
--  MASLA  App (client1-cutting.html) `width` likhti/parhti hai, magar
--         13 wali file `width_mm` banati hai. Naye install par size wala
--         job save hi nahi hota ("Could not find the 'width' column").
--  HAL    width_mm ka naam width — sirf tab jab width mojood na ho (live
--         par shayad haath se ban chuka hai). Views naam badalne ke saath
--         khud chalti hain; koi plpgsql function is column ko nahi parhti
--         (jaanch li). coils.width_mm aur stock_conversion_outputs.width_mm
--         ko haath NAHI lagaya — app wahan width_mm hi istemaal karti hai.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'cutting_job_outputs'
                    and column_name = 'width')
     and exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'cutting_job_outputs'
                    and column_name = 'width_mm') then
    alter table public.cutting_job_outputs rename column width_mm to width;
  end if;
end $$;


-- ============================================================
--  HISSA 2 — Chhote helper (sirf andar se chalte hain)
-- ============================================================

-- Tolerance: wohi qaida jo trg_check_coil_limits (26) ka hai —
-- base ka balance_tolerance_pct %, ya kam se kam delivery_variance_min_kg.
create or replace function public.cutting_tolerance_kg(p_base numeric)
returns numeric
language sql
stable
security definer
set search_path to 'public'
as $function$
  select greatest(
    coalesce(p_base, 0) * coalesce((select balance_tolerance_pct from cutting_settings where id = 1), 10) / 100,
    coalesce((select delivery_variance_min_kg from cutting_settings where id = 1), 25));
$function$;

-- Job kisi zinda challan par gaya hai?
create or replace function public.cutting_job_is_delivered(p_job uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (
    select 1 from delivery_challan_lines l
      join delivery_challans d on d.id = l.challan_id
     where l.job_id = p_job and d.deleted_at is null and d.status <> 'cancelled');
$function$;

-- Job kis zinda invoice par bill hai (null = kisi par nahi).
-- p_except: is invoice ko na gino (usi invoice ki apni line).
create or replace function public.cutting_job_invoice_no(p_job uuid, p_except uuid default null)
returns text
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(si.sino, '(bina number)')
    from service_invoice_jobs sij
    join service_invoices si on si.id = sij.invoice_id
   where sij.job_id = p_job
     and si.deleted_at is null and si.status <> 'cancelled'
     and si.id is distinct from p_except
   limit 1;
$function$;

-- Challan kisi zinda invoice se jura hai — seedha (service_invoice_challans)
-- ya us ki kisi line ka job bill ho chuka hai.
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
    (select cutting_job_invoice_no(l.job_id)
       from delivery_challan_lines l
      where l.challan_id = p_challan and l.job_id is not null
        and cutting_job_invoice_no(l.job_id) is not null
      limit 1));
$function$;


-- ============================================================
--  HISSA 3 — H13: coil ka balance — pehle row lock, phir ginti
--
--  MASLA  recalc_coil_balances (23) pehle jama karta tha, phir likhta tha.
--         Do challan ek saath save hon to dono apni apni (purani) tasveer
--         se ginte — 10 + 20 ki jagah 20 likha gaya.
--  HAL    Ginti se pehle coil ki row FOR UPDATE. Doosri transaction
--         intezar karti hai aur pehli ke commit ke baad nayi tasveer se
--         ginti hai (READ COMMITTED mein har statement nayi tasveer leta hai).
--         Baqi hisaab bilkul 23 jaisa.
-- ============================================================

create or replace function public.recalc_coil_balances(p_coil_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c           record;
  v_consumed  numeric;
  v_returned  numeric;
  v_finished  numeric;
  v_delivered numeric;
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

    v_returned := 0; v_finished := 0; v_delivered := 0;
  else
    -- Party ki coil: cutting jobs, returns aur delivery challans
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

    select coalesce(sum(l.delivered_weight), 0) into v_delivered
      from delivery_challan_lines l
      join delivery_challans d on d.id = l.challan_id
     where l.coil_id = p_coil_id and d.deleted_at is null and d.status <> 'cancelled';
  end if;

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


-- ============================================================
--  HISSA 4 — H12: delivery tayyar maal se zyada nahi
--
--  MASLA  26 ne trg_delivery_available hata diya. Ab sirf "received +
--         10%" dekha jata tha — 290 KG ke job par 490 KG ka challan
--         (TESTING 3.8, +200 KG) qabool ho gaya.
--  HAL    Har coil par: zinda challans ka kul delivered ≤ COMPLETED jobs
--         ka kul output + tolerance (trg_check_coil_limits wali settings,
--         output weight par). Job ke baghair wali delivery line bhi isi
--         coil hisaab mein aati hai. Coil row lock ke saath — do challan
--         ek saath hadd paar nahi kar sakte.
--         Aur har job mein: kul output ≤ kul input + tolerance.
-- ============================================================

create or replace function public.check_coil_delivery_cap(p_coil_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c        record;
  v_ready  numeric;
  v_deliv  numeric;
  v_tol    numeric;
begin
  if p_coil_id is null then return; end if;
  select * into c from coils where id = p_coil_id for update;
  if not found or c.ownership <> 'party' then return; end if;

  select coalesce(sum(o.output_weight), 0) into v_ready
    from cutting_job_outputs o
    join cutting_jobs j on j.id = o.job_id
   where o.coil_id = p_coil_id and j.deleted_at is null and j.status = 'completed';

  select coalesce(sum(l.delivered_weight), 0) into v_deliv
    from delivery_challan_lines l
    join delivery_challans d on d.id = l.challan_id
   where l.coil_id = p_coil_id and d.deleted_at is null and d.status <> 'cancelled';

  -- kuch bana hi nahi to tolerance bhi nahi
  v_tol := case when v_ready > 0 then cutting_tolerance_kg(v_ready) else 0 end;

  if v_deliv > v_ready + v_tol then
    raise exception 'Coil % par completed jobs ka sirf % KG maal tayyar hai — % KG delivery nahi ho sakti (weighbridge ki hadd +% KG). Weight dobara dekh lein.',
      c.coil_serial, round(v_ready, 3), round(v_deliv, 3), round(v_tol, 3);
  end if;
end;
$function$;

create or replace function public.check_job_output_cap(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  j      record;
  v_in   numeric;
  v_out  numeric;
  v_tol  numeric;
begin
  if p_job_id is null then return; end if;
  select * into j from cutting_jobs where id = p_job_id for update;
  if not found then return; end if;          -- job hi delete ho raha hai (cascade)

  select coalesce(sum(input_weight), 0)  into v_in  from cutting_job_inputs  where job_id = p_job_id;
  select coalesce(sum(output_weight), 0) into v_out from cutting_job_outputs where job_id = p_job_id;
  v_tol := case when v_in > 0 then cutting_tolerance_kg(v_in) else 0 end;

  if v_out > v_in + v_tol then
    raise exception 'Job % mein % KG maal dala gaya magar % KG bana likha hai (hadd +% KG). Output ya input weight dobara dekh lein.',
      j.jno, round(v_in, 3), round(v_out, 3), round(v_tol, 3);
  end if;
end;
$function$;

-- Challan line: delivery barhi to coil ki hadd dekho
create or replace function public.trg_challan_line_cap()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if TG_OP = 'INSERT'
     or NEW.coil_id is distinct from OLD.coil_id
     or NEW.delivered_weight > OLD.delivered_weight then
    perform check_coil_delivery_cap(NEW.coil_id);
  end if;
  return NEW;
end;
$function$;

drop trigger if exists trg_zz_challan_line_cap on delivery_challan_lines;
create trigger trg_zz_challan_line_cap after insert or update on delivery_challan_lines
  for each row execute function trg_challan_line_cap();

-- Job input/output: output ≤ input. Completed job ka output ghata to us
-- coil ki delivery ki hadd bhi dobara dekho (job ke baghair wali lines).
create or replace function public.trg_job_line_cap()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_status text;
begin
  perform check_job_output_cap(coalesce(NEW.job_id, OLD.job_id));
  if TG_OP = 'UPDATE' and NEW.job_id is distinct from OLD.job_id then
    perform check_job_output_cap(OLD.job_id);
  end if;

  if TG_TABLE_NAME = 'cutting_job_outputs' and TG_OP <> 'INSERT' then
    select status into v_status from cutting_jobs where id = OLD.job_id and deleted_at is null;
    if v_status = 'completed' then
      perform check_coil_delivery_cap(OLD.coil_id);
    end if;
  end if;
  return coalesce(NEW, OLD);
end;
$function$;

drop trigger if exists trg_zz_job_output_cap on cutting_job_outputs;
create trigger trg_zz_job_output_cap after insert or update or delete on cutting_job_outputs
  for each row execute function trg_job_line_cap();

drop trigger if exists trg_zz_job_input_cap on cutting_job_inputs;
create trigger trg_zz_job_input_cap after update or delete on cutting_job_inputs
  for each row execute function trg_job_line_cap();


-- ============================================================
--  HISSA 5 — Cancel ki ijazat (job cancel = cutting_job_cancel)
--
--  MASLA  enforce_perm_on_update (05) sirf deleted_at dekhta hai. Status
--         'cancelled' karna "edit" gina jata tha — job cancel ke liye
--         cutting_job_edit maanga jata, cutting_job_cancel wale ko rok.
--         Challan / inward / return / invoice / conversion mein bhi yehi.
--  HAL    Cutting documents ke liye alag function: status cancelled mein
--         jaye ya wahan se wapas aaye to cancel wali ijazat. Sath koi aur
--         field bhi badli ho to edit wali bhi. Baqi qaida 05 jaisa.
--         05 wala function billing waghera ke liye waisa hi hai.
-- ============================================================

create or replace function public.enforce_doc_perm_on_update()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  edit_perm    text := TG_ARGV[0];
  cancel_perm  text := TG_ARGV[1];
  restore_perm text := TG_ARGV[2];
  skip_keys    text[] := array['status','updated_at','updated_by','version',
                               'completed_at','completed_by','sub_total','tax_total','grand_total'];
  other_change boolean;
begin
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    return NEW;
  end if;
  if is_app_admin() then
    return NEW;
  end if;

  if OLD.deleted_at is null and NEW.deleted_at is not null then
    if not has_perm(cancel_perm) then
      raise exception 'Permission denied: % zaroori hai delete ke liye', cancel_perm;
    end if;
  elsif OLD.deleted_at is not null and NEW.deleted_at is null then
    if not has_perm(restore_perm) then
      raise exception 'Permission denied: % zaroori hai restore ke liye', restore_perm;
    end if;
  elsif (NEW.status = 'cancelled') is distinct from (OLD.status = 'cancelled') then
    if not has_perm(cancel_perm) then
      raise exception 'Permission denied: % zaroori hai cancel ke liye', cancel_perm;
    end if;
    other_change := (to_jsonb(NEW) - skip_keys) is distinct from (to_jsonb(OLD) - skip_keys);
    if other_change and not has_perm(edit_perm) then
      raise exception 'Permission denied: % zaroori hai edit ke liye', edit_perm;
    end if;
  else
    if not has_perm(edit_perm) then
      raise exception 'Permission denied: % zaroori hai edit ke liye', edit_perm;
    end if;
  end if;

  return NEW;
end;
$function$;

drop trigger if exists trg_perm_material_inwards  on material_inwards;
drop trigger if exists trg_perm_cutting_jobs      on cutting_jobs;
drop trigger if exists trg_perm_delivery_challans on delivery_challans;
drop trigger if exists trg_perm_material_returns  on material_returns;
drop trigger if exists trg_perm_service_invoices  on service_invoices;
drop trigger if exists trg_perm_stock_conversions on stock_conversions;

create trigger trg_perm_material_inwards  before update on material_inwards  for each row execute function enforce_doc_perm_on_update('cutting_inward_edit','cutting_inward_cancel','recycle_bin');
create trigger trg_perm_cutting_jobs      before update on cutting_jobs      for each row execute function enforce_doc_perm_on_update('cutting_job_edit','cutting_job_cancel','recycle_bin');
create trigger trg_perm_delivery_challans before update on delivery_challans for each row execute function enforce_doc_perm_on_update('cutting_challan_edit','cutting_challan_cancel','recycle_bin');
create trigger trg_perm_material_returns  before update on material_returns  for each row execute function enforce_doc_perm_on_update('cutting_return_create','cutting_return_cancel','recycle_bin');
create trigger trg_perm_service_invoices  before update on service_invoices  for each row execute function enforce_doc_perm_on_update('service_invoice_edit','service_invoice_cancel','recycle_bin');
create trigger trg_perm_stock_conversions before update on stock_conversions for each row execute function enforce_doc_perm_on_update('own_conversion_edit','own_conversion_cancel','recycle_bin');


-- ============================================================
--  HISSA 6 — H14: documents ki halat ke rok (header)
--
--  MASLA  Delivered + billed job cancel / delete ho jata (500 KG wapas raw
--         mein), billed job wapas draft, billed job ka challan cancel,
--         istemaal hui coils wala inward cancel — sab qabool.
--  HAL    Database khud rokta hai (admin ko bhi — yeh hisaab ki sachai
--         hai, ijazat nahi):
--           * job: deliver ya bill ho chuka ho to cancel / delete /
--             completed se wapas / party badalna mana.
--           * challan: us ka job (ya challan khud) zinda invoice par ho to
--             cancel / delete mana. Wapas zinda karne par delivery ki hadd.
--           * inward: coils par koi kaam ho chuka ho to cancel / delete mana.
--           * job / challan: lines hon to party badalna mana.
-- ============================================================

create or replace function public.trg_job_state_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_inv     text;
  v_deliv   boolean;
  v_leaving boolean;
begin
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    return NEW;
  end if;

  if NEW.party_id is distinct from OLD.party_id
     and (exists (select 1 from cutting_job_inputs  where job_id = NEW.id)
       or exists (select 1 from cutting_job_outputs where job_id = NEW.id)) then
    raise exception 'Job % mein coils lag chuki hain — party nahi badal sakti', OLD.jno;
  end if;

  v_leaving := (OLD.status = 'completed' and NEW.status <> 'completed')
            or (OLD.deleted_at is null and NEW.deleted_at is not null);
  if not v_leaving then return NEW; end if;

  v_deliv := cutting_job_is_delivered(NEW.id);
  v_inv   := cutting_job_invoice_no(NEW.id);

  if v_inv is not null then
    raise exception 'Job % invoice % par bill ho chuka hai — cancel / delete / draft nahi ho sakta. Pehle invoice cancel karein.',
      OLD.jno, v_inv;
  end if;
  if v_deliv then
    raise exception 'Job % ka maal challan par ja chuka hai — cancel / delete / draft nahi ho sakta. Pehle challan cancel karein.',
      OLD.jno;
  end if;
  return NEW;
end;
$function$;

-- Job completed se nikla to us ki coils ka "tayyar maal" ghata —
-- job ke baghair wali delivery lines ki hadd dobara dekho.
create or replace function public.trg_job_state_after()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare c uuid;
begin
  if (OLD.status = 'completed' and OLD.deleted_at is null)
     and (NEW.status <> 'completed' or NEW.deleted_at is not null) then
    for c in select distinct coil_id from cutting_job_outputs where job_id = NEW.id loop
      perform check_coil_delivery_cap(c);
    end loop;
  end if;
  return NEW;
end;
$function$;

drop trigger if exists trg_state_cutting_jobs    on cutting_jobs;
drop trigger if exists trg_zz_state_cutting_jobs on cutting_jobs;
create trigger trg_state_cutting_jobs    before update on cutting_jobs for each row execute function trg_job_state_guard();
create trigger trg_zz_state_cutting_jobs after  update on cutting_jobs for each row execute function trg_job_state_after();

create or replace function public.trg_challan_state_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_inv text;
begin
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    return NEW;
  end if;

  if NEW.party_id is distinct from OLD.party_id
     and exists (select 1 from delivery_challan_lines where challan_id = NEW.id) then
    raise exception 'Challan % mein maal lag chuka hai — party nahi badal sakti', OLD.dno;
  end if;

  if (OLD.status <> 'cancelled' and NEW.status = 'cancelled')
     or (OLD.deleted_at is null and NEW.deleted_at is not null) then
    v_inv := cutting_challan_invoice_no(NEW.id);
    if v_inv is not null then
      raise exception 'Challan % ka maal invoice % par bill ho chuka hai — cancel / delete nahi ho sakta. Pehle invoice cancel karein.',
        OLD.dno, v_inv;
    end if;
  end if;
  return NEW;
end;
$function$;

-- Cancel challan wapas zinda hua → delivery phir gini jayegi, hadd dekho
create or replace function public.trg_challan_state_after()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare c uuid;
begin
  if NEW.status <> 'cancelled' and NEW.deleted_at is null
     and (OLD.status = 'cancelled' or OLD.deleted_at is not null) then
    for c in select distinct coil_id from delivery_challan_lines where challan_id = NEW.id loop
      perform check_coil_delivery_cap(c);
    end loop;
  end if;
  return NEW;
end;
$function$;

drop trigger if exists trg_state_delivery_challans    on delivery_challans;
drop trigger if exists trg_zz_state_delivery_challans on delivery_challans;
create trigger trg_state_delivery_challans    before update on delivery_challans for each row execute function trg_challan_state_guard();
create trigger trg_zz_state_delivery_challans after  update on delivery_challans for each row execute function trg_challan_state_after();

create or replace function public.trg_inward_state_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_serial text;
begin
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    return NEW;
  end if;

  if (OLD.status <> 'cancelled' and NEW.status = 'cancelled')
     or (OLD.deleted_at is null and NEW.deleted_at is not null) then
    select coil_serial into v_serial
      from coils
     where inward_id = NEW.id
       and (consumed_weight + returned_weight + delivered_weight + finished_weight + closing_adjust_weight > 0)
     limit 1;
    if v_serial is not null then
      raise exception 'Inward % ki coil % par kaam ho chuka hai — inward cancel / delete nahi ho sakta', OLD.ino, v_serial;
    end if;
  end if;
  return NEW;
end;
$function$;

drop trigger if exists trg_state_material_inwards on material_inwards;
create trigger trg_state_material_inwards before update on material_inwards for each row execute function trg_inward_state_guard();


-- ============================================================
--  HISSA 7 — Coil ke totals sirf trigger likhe (db/16:63)
--
--  MASLA  cutting_coil_adjust wala user coils ki row seedhi PATCH kar ke
--         consumed / delivered / finished ko kuch bhi likh sakta tha, aur
--         received_weight istemaal hue maal se kam kar sakta tha. Istemaal
--         hui coil cancel / delete bhi ho jati.
--  HAL    Yeh columns trigger-owned: system ke ilawa koi likhe to purani
--         value wapas (chupke se — taake Restore ka upsert na tootay).
--         Band / kholna sirf close_coil / reopen_coil se. Received kam karna
--         istemaal se neeche mana. Istemaal hui coil cancel / delete /
--         party ya item badalna mana.
-- ============================================================

create or replace function public.trg_coil_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_used boolean;
begin
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    return NEW;
  end if;

  -- trigger-owned: jo trigger ne likha wohi rahega
  NEW.consumed_weight       := OLD.consumed_weight;
  NEW.finished_weight       := OLD.finished_weight;
  NEW.returned_weight       := OLD.returned_weight;
  NEW.delivered_weight      := OLD.delivered_weight;
  NEW.closing_adjust_weight := OLD.closing_adjust_weight;
  NEW.closed_at             := OLD.closed_at;
  NEW.closed_by             := OLD.closed_by;

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

  return NEW;
end;
$function$;

-- naam "trg_coil_guard" < "trg_coil_limits": pehle yeh chale, phir hadd
drop trigger if exists trg_coil_guard on coils;
create trigger trg_coil_guard before update on coils for each row execute function trg_coil_guard();


-- ============================================================
--  HISSA 8 — H14: lines par bhi header jaisa tala (db/18:117-150, 192-194)
--
--  MASLA  Line tables ki RLS "create YA edit" maangti thi. create-only user
--         completed / billed job ke outputs, challan ka delivered weight,
--         invoice ka rate — sab badal sakta tha. Header par tala tha, lines
--         par nahi.
--  HAL    Har line table par BEFORE trigger:
--           * deliver / bill ho chuke job ke inputs / outputs — koi nahi
--             badal sakta (admin bhi nahi). Pehle challan / invoice cancel.
--           * bill ho chuke job / challan ki challan lines — badal / hata
--             nahi sakte (nayi delivery line ban sakti hai).
--           * cancel / delete document ki lines — sirf admin (Restore).
--           * maujood document ki line badalna / hatana = edit ijazat.
--             Nayi line: edit ijazat, ya apna banaya hua document jo abhi
--             15 minute ke andar bana ho (app pehle header, phir lines
--             bhejti hai — do alag request).
--           * Jo row bilkul nahi badli (Restore ka upsert) usay nahi rokte.
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
begin
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    return coalesce(NEW, OLD);
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
      v_inv := cutting_job_invoice_no(hid);
      if v_inv is not null then
        raise exception 'Job % invoice % par bill ho chuka hai — is ke input / sizes nahi badal sakte. Pehle invoice cancel karein.', h.doc_no, v_inv;
      end if;
      if cutting_job_is_delivered(hid) then
        raise exception 'Job % ka maal challan par ja chuka hai — is ke input / sizes nahi badal sakte. Pehle challan cancel karein.', h.doc_no;
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
    v_inv := cutting_job_invoice_no((to_jsonb(OLD) ->> 'job_id')::uuid);
    if v_inv is not null then
      raise exception 'Is line ka job invoice % par bill ho chuka hai — line nahi badal sakti', v_inv;
    end if;
  end if;

  return coalesce(NEW, OLD);
end;
$function$;

drop trigger if exists trg_guard_job_input      on cutting_job_inputs;
drop trigger if exists trg_guard_job_output     on cutting_job_outputs;
drop trigger if exists trg_guard_challan_line   on delivery_challan_lines;
drop trigger if exists trg_guard_return_line    on material_return_lines;
drop trigger if exists trg_guard_service_line   on service_invoice_lines;
drop trigger if exists trg_guard_service_job    on service_invoice_jobs;
drop trigger if exists trg_guard_service_challan on service_invoice_challans;

create trigger trg_guard_job_input       before insert or update or delete on cutting_job_inputs       for each row execute function trg_cutting_line_guard('job');
create trigger trg_guard_job_output      before insert or update or delete on cutting_job_outputs      for each row execute function trg_cutting_line_guard('job');
create trigger trg_guard_challan_line    before insert or update or delete on delivery_challan_lines   for each row execute function trg_cutting_line_guard('challan');
create trigger trg_guard_return_line     before insert or update or delete on material_return_lines    for each row execute function trg_cutting_line_guard('return');
create trigger trg_guard_service_line    before insert or update or delete on service_invoice_lines    for each row execute function trg_cutting_line_guard('invoice');
create trigger trg_guard_service_job     before insert or update or delete on service_invoice_jobs     for each row execute function trg_cutting_line_guard('invoice');
create trigger trg_guard_service_challan before insert or update or delete on service_invoice_challans for each row execute function trg_cutting_line_guard('invoice');


-- ============================================================
--  HISSA 9 — M3 + H14: job ka bill
--
--  MASLA  service_invoice_jobs(job_id) par poora unique index (db/14:203)
--         — invoice cancel ho jaye to bhi us ka job kabhi dobara bill nahi
--         hota. Aur draft job ya doosri party ka job bhi bill ho jata.
--  HAL    Index hata kar (invoice_id, job_id) — tareekh (cancel invoice ki
--         link) bachi rehti hai. "Ek job ek hi ZINDA invoice par" ab
--         trigger dekhta hai, job ki row lock kar ke — do invoice ek saath
--         ek hi job nahi utha sakte. Job Completed aur usi party ka ho.
--         Cancel invoice wapas zinda ho to yehi jaanch dobara.
-- ============================================================

drop index if exists public.service_invoice_jobs_job_uniq;
create unique index if not exists service_invoice_jobs_inv_job_uniq on service_invoice_jobs (invoice_id, job_id);
create index if not exists service_invoice_jobs_job_idx on service_invoice_jobs (job_id);

create or replace function public.check_job_billable(p_invoice_id uuid, p_job_id uuid)
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

  other := cutting_job_invoice_no(p_job_id, p_invoice_id);
  if other is not null then
    raise exception 'Yeh job pehle hi invoice % par bill ho chuka hai', other;
  end if;
end;
$function$;

create or replace function public.trg_check_job_not_billed()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform check_job_billable(NEW.invoice_id, NEW.job_id);
  return NEW;
end;
$function$;

drop trigger if exists trg_job_not_billed on service_invoice_jobs;
create trigger trg_job_not_billed before insert or update on service_invoice_jobs
  for each row execute function trg_check_job_not_billed();

-- Invoice wapas zinda / party badli → us ke jobs dobara jaancho
create or replace function public.trg_invoice_state_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare jid uuid;
begin
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    return NEW;
  end if;
  if NEW.status = 'cancelled' or NEW.deleted_at is not null then return NEW; end if;

  if OLD.status = 'cancelled' or OLD.deleted_at is not null
     or NEW.party_id is distinct from OLD.party_id then
    for jid in select job_id from service_invoice_jobs where invoice_id = NEW.id loop
      -- NEW abhi table mein nahi — is liye party yahan khud dekhte hain
      if exists (select 1 from cutting_jobs where id = jid and party_id is distinct from NEW.party_id) then
        raise exception 'Is invoice ka ek job kisi aur party ka hai — party nahi badal sakti';
      end if;
      if cutting_job_invoice_no(jid, NEW.id) is not null then
        raise exception 'Is invoice ka job ab invoice % par bill ho chuka hai — yeh invoice wapas zinda nahi ho sakti',
          cutting_job_invoice_no(jid, NEW.id);
      end if;
    end loop;
  end if;
  return NEW;
end;
$function$;

drop trigger if exists trg_state_service_invoices on service_invoices;
create trigger trg_state_service_invoices before update on service_invoices
  for each row execute function trg_invoice_state_guard();


-- ============================================================
--  HISSA 10 — H4: Service invoice ke totals hamesha server ginta hai
--
--  MASLA  sub_total / tax_total / grand_total header mein jo bheja jaye
--         wohi likha jata (lines ke baghair 777,777 TB mein chala gaya).
--         Header trigger sirf discount / tax_on badalne par ginta tha
--         (db/15:485-498, db/16:164). Manfi discount / paid / tax bhi
--         qabool the.
--  HAL    Header par BEFORE INSERT/UPDATE: totals hamesha lines se —
--         wohi formula jo 15 (recalc_service_invoice_totals) aur app
--         (updateInvSum) ka hai:
--             sub   = Σ round(qty × rate, 2)
--             tax   = tax_on ? Σ round(round(qty × rate, 2) × tax_pct / 100, 2) : 0
--             grand = round(sub − discount + tax, 2)
--         discount ≥ 0, paid ≥ 0, line par qty / rate ≥ 0, tax_pct 0–100.
--         discount ≤ subtotal: lines save hone par dekha jata hai (app
--         pehle header bhejti hai, phir lines — header ke waqt naya
--         subtotal maloom hi nahi).
-- ============================================================

create or replace function public.service_invoice_line_totals(p_invoice_id uuid, p_tax_on boolean,
                                                               out o_sub numeric, out o_tax numeric)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(sum(round(qty * rate, 2)), 0),
         case when p_tax_on
              then coalesce(sum(round(round(qty * rate, 2) * tax_pct / 100, 2)), 0)
              else 0 end
    from service_invoice_lines where invoice_id = p_invoice_id;
$function$;

create or replace function public.trg_service_invoice_header_totals()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare t record;
begin
  if coalesce(current_setting('app.system_write', true), '') <> 'true' then
    if coalesce(NEW.discount, 0) < 0
       and (TG_OP = 'INSERT' or NEW.discount is distinct from OLD.discount) then
      raise exception 'Discount manfi nahi ho sakta';
    end if;
    if coalesce(NEW.paid, 0) < 0
       and (TG_OP = 'INSERT' or NEW.paid is distinct from OLD.paid) then
      raise exception 'Paid amount manfi nahi ho sakta';
    end if;
  end if;

  NEW.discount := coalesce(NEW.discount, 0);
  NEW.paid     := coalesce(NEW.paid, 0);
  NEW.tax_on   := coalesce(NEW.tax_on, false);

  select * into t from service_invoice_line_totals(NEW.id, NEW.tax_on);
  NEW.sub_total   := t.o_sub;
  NEW.tax_total   := t.o_tax;
  NEW.grand_total := round(t.o_sub - NEW.discount + t.o_tax, 2);
  return NEW;
end;
$function$;

drop trigger if exists trg_totals_service_invoices on service_invoices;
create trigger trg_totals_service_invoices before insert or update on service_invoices
  for each row execute function trg_service_invoice_header_totals();

-- Lines badlein to header dobara (row lock ke saath — do saves ek saath)
create or replace function public.recalc_service_invoice_totals(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare inv record;
begin
  select * into inv from service_invoices where id = p_invoice_id for update;
  if not found then return; end if;

  -- totals header ka BEFORE trigger khud ginta hai
  perform set_config('app.system_write', 'true', true);
  update service_invoices set sub_total = sub_total where id = p_invoice_id;
  perform set_config('app.system_write', 'false', true);
end;
$function$;

create or replace function public.trg_service_invoice_totals()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare inv record;
begin
  perform recalc_service_invoice_totals(coalesce(NEW.invoice_id, OLD.invoice_id));

  -- line aayi / badli: ab subtotal pata hai — discount us se zyada na ho
  if TG_OP <> 'DELETE' then
    select sino, discount, sub_total into inv from service_invoices where id = NEW.invoice_id;
    if found and inv.discount > inv.sub_total then
      raise exception 'Discount (%) subtotal (%) se zyada nahi ho sakta', inv.discount, inv.sub_total;
    end if;
  end if;
  return coalesce(NEW, OLD);
end;
$function$;

create or replace function public.trg_service_line_amount()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if coalesce(NEW.qty, 0) < 0 or coalesce(NEW.rate, 0) < 0 then
    raise exception 'Qty aur rate manfi nahi ho sakte';
  end if;
  if coalesce(NEW.tax_pct, 0) < 0 or coalesce(NEW.tax_pct, 0) > 100 then
    raise exception 'Tax % 0 se 100 ke darmiyan hona chahiye', '%';
  end if;
  NEW.amount := round(NEW.qty * NEW.rate, 2);
  return NEW;
end;
$function$;


-- ============================================================
--  HISSA 11 — Coil band karna: asal bacha hua maal (db/15:357)
--
--  MASLA  App ka sawal "X KG maal abhi hamare paas hai" physical_balance
--         dikhata hai (db/13:182), magar close_coil raw_balance likhta
--         tha — cutting ka loss (input − output) hisaab se gum ho jata.
--         Party Material report (db/17:136) teesra formula (raw + pending)
--         chalati thi.
--  HAL    Closing adjustment = physical_balance (received − delivered −
--         returned − pehle ka adjustment), manfi ho to 0. Report bhi
--         wohi physical_balance jama karti hai.
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

  leftover := greatest(c.physical_balance, 0);

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


-- ============================================================
--  HISSA 12 — Views
--
--  coil_ledger_v      — size ka likha 'mm' pakka tha (db/17:46). Ab
--                       width_unit / length_unit (33) se: "4 ft × 300 mm × 20 pcs".
--  ready_for_delivery_v — width_mm ki jagah width, length, size_unit,
--                       width_unit, length_unit (app yahi parhti hai:
--                       client1-cutting.html pickReadyMaterial). Sirf
--                       COMPLETED jobs — draft ka maal delivery ke liye
--                       tayyar nahi (26 ka trg_delivery_job_completed bhi
--                       yehi kehta hai). Column ka naam badla, is liye
--                       drop + create.
--  party_material_ledger_v — physical_balance = Σ coils.physical_balance.
-- ============================================================

create or replace view coil_ledger_v as
  -- 1. Maal aaya
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
   where c.deleted_at is null

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
  -- 5. Raw maal wapas
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
   where c.deleted_at is null and c.status = 'closed' and c.closing_adjust_weight <> 0;

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
       sum(c.physical_balance)               as physical_balance
  from coils c
  join parties p on p.id = c.party_id
 where c.deleted_at is null and c.ownership = 'party' and c.status <> 'cancelled'
 group by c.party_id, p.name;

drop view if exists ready_for_delivery_v;
create view ready_for_delivery_v as
select o.id             as output_id,
       o.job_id,
       j.jno,
       o.coil_id,
       c.coil_serial,
       c.party_id,
       p.name           as party_name,
       c.warehouse_id,
       o.width,
       o.length,
       o.size_unit,
       o.width_unit,
       o.length_unit,
       o.pieces,
       o.output_weight,
       coalesce(dl.delivered, 0)                    as delivered_weight,
       o.output_weight - coalesce(dl.delivered, 0)  as pending_weight
  from cutting_job_outputs o
  join cutting_jobs j on j.id = o.job_id
  join coils c        on c.id = o.coil_id
  join parties p      on p.id = c.party_id
  left join lateral (
    select sum(l.delivered_weight) as delivered
      from delivery_challan_lines l
      join delivery_challans d on d.id = l.challan_id
     where l.output_id = o.id and d.deleted_at is null and d.status <> 'cancelled'
  ) dl on true
 where j.deleted_at is null and j.status = 'completed' and c.deleted_at is null;

alter view coil_ledger_v           set (security_invoker = on);
alter view party_material_ledger_v set (security_invoker = on);
alter view ready_for_delivery_v    set (security_invoker = on);
revoke all on ready_for_delivery_v from public, anon;
grant select on ready_for_delivery_v to authenticated;


-- ============================================================
--  HISSA 13 — M12: Own Conversion
--
--  MASLA  (a) Source item ke stock se zyada maal kharch ho jata (−4,600).
--         (b) Own coil se received + 10% tak nikal jata (26 ki party wali
--             tolerance own coil par bhi lagti thi).
--         (c) Source ki cost baad mein badle (pichli tareekh ki purchase,
--             opening rate) to recompute_item_cost input line ki cost to
--             badal deta, magar 23 ka recursion guard us ke baad output par
--             dobara allocation nahi hone deta — output ki cost purani.
--  HAL    (a) Input line aaye / barhe, ya conversion wapas zinda ho: hisaab
--             ke baad source item ka stock_qty manfi ho to rok.
--         (b) Own coil par koi tolerance nahi — raw_balance manfi nahi
--             (sirf tab rokte hain jab halat pehle se bigre; purana data
--             atakta nahi).
--         (c) Input ka cost_amount badle to us conversion ki allocation
--             aur output items ka hisaab dobara (chain mein aage bhi —
--             trigger depth ki hadd chakkar se bachati hai).
--         allocate_conversion_cost bhi conversion ki row lock karta hai.
-- ============================================================

create or replace function public.trg_conversion_stock_check()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  it    record;
  v_ids uuid[];
  sc    record;
begin
  if TG_TABLE_NAME = 'stock_conversion_inputs' then
    if TG_OP = 'UPDATE' and NEW.item_id is not distinct from OLD.item_id and NEW.qty <= OLD.qty then
      return NEW;                         -- kharch barha hi nahi
    end if;
    select status, deleted_at into sc from stock_conversions where id = NEW.conversion_id;
    if not found or sc.status = 'cancelled' or sc.deleted_at is not null then return NEW; end if;
    v_ids := array[NEW.item_id];
  else
    if NEW.status = 'cancelled' or NEW.deleted_at is not null then return NEW; end if;
    if not (OLD.status = 'cancelled' or OLD.deleted_at is not null
            or NEW.cdate is distinct from OLD.cdate) then
      return NEW;
    end if;
    select array_agg(distinct item_id) into v_ids from stock_conversion_inputs where conversion_id = NEW.id;
  end if;

  for it in select name, stock_qty, unit from items where id = any (v_ids) loop
    if it.stock_qty < -0.0005 then
      raise exception 'Item "%" ka stock kaafi nahi — is conversion ke baad stock % % ho jata (manfi). Qty kam karein ya pehle purchase darj karein.',
        it.name, round(it.stock_qty, 3), coalesce(it.unit, '');
    end if;
  end loop;
  return NEW;
end;
$function$;

-- naam "trg_zz_..." — 23 ke recalc triggers ke BAAD chale (stock_qty taaza ho)
drop trigger if exists trg_zz_conv_stock_check on stock_conversion_inputs;
create trigger trg_zz_conv_stock_check after insert or update on stock_conversion_inputs
  for each row execute function trg_conversion_stock_check();

drop trigger if exists trg_zz_conv_stock_check on stock_conversions;
create trigger trg_zz_conv_stock_check after update on stock_conversions
  for each row execute function trg_conversion_stock_check();

-- (c) source ki cost badli → output par dobara baanto
create or replace function public.trg_conversion_input_cost_changed()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare it uuid;
begin
  if pg_trigger_depth() > 12 then return NEW; end if;   -- chakkar se hifazat
  perform allocate_conversion_cost(NEW.conversion_id);
  for it in select distinct item_id from stock_conversion_outputs where conversion_id = NEW.conversion_id loop
    perform recompute_item_cost(it);
  end loop;
  return NEW;
end;
$function$;

drop trigger if exists trg_conv_input_cost on stock_conversion_inputs;
create trigger trg_conv_input_cost after update of cost_amount on stock_conversion_inputs
  for each row when (old.cost_amount is distinct from new.cost_amount)
  execute function trg_conversion_input_cost_changed();

create or replace function public.allocate_conversion_cost(p_conversion_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  sc          record;
  total_cost  numeric;
  total_qty   numeric;
  running     numeric := 0;
  last_id     uuid;
  o           record;
  share       numeric;
begin
  select * into sc from stock_conversions where id = p_conversion_id for update;
  if not found then return; end if;

  select coalesce(sum(cost_amount), 0) into total_cost
    from stock_conversion_inputs where conversion_id = p_conversion_id;
  total_cost := total_cost + coalesce(sc.conversion_cost, 0);

  select coalesce(sum(qty), 0) into total_qty
    from stock_conversion_outputs where conversion_id = p_conversion_id;

  if total_qty <= 0 then return; end if;

  select id into last_id from stock_conversion_outputs
   where conversion_id = p_conversion_id order by line_no desc, id desc limit 1;

  perform set_config('app.system_write', 'true', true);

  for o in select id, qty from stock_conversion_outputs
            where conversion_id = p_conversion_id and id <> last_id
            order by line_no, id
  loop
    share := round(total_cost * o.qty / total_qty, 2);
    running := running + share;
    update stock_conversion_outputs set cost_amount = share where id = o.id;
  end loop;

  -- aakhri line: bacha hua sab kuch, taake jama bilkul barabar ho
  update stock_conversion_outputs set cost_amount = round(total_cost - running, 2)
   where id = last_id;

  perform set_config('app.system_write', 'false', true);
end;
$function$;

-- (b) own coil: koi tolerance nahi. Party coil ka qaida 26 jaisa.
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
  raw_b := NEW.received_weight - NEW.consumed_weight - NEW.returned_weight;
  phy_b := NEW.received_weight - NEW.delivered_weight - NEW.returned_weight
             - NEW.closing_adjust_weight;

  if NEW.ownership = 'own' then
    -- company ka apna maal: jitna aaya us se zyada kharch nahi
    if raw_b < 0 and (TG_OP = 'INSERT'
                      or raw_b < OLD.received_weight - OLD.consumed_weight - OLD.returned_weight) then
      raise exception 'Coil % mein jitna maal hai us se % KG zyada conversion mein ja raha hai — own coil par koi tolerance nahi',
        NEW.coil_serial, round(-raw_b, 3);
    end if;
    return NEW;
  end if;

  select coalesce(balance_tolerance_pct, 10), coalesce(delivery_variance_min_kg, 25)
    into pct, min_kg
    from cutting_settings where id = 1;
  if pct    is null then pct    := 10; end if;
  if min_kg is null then min_kg := 25; end if;

  tol := greatest(coalesce(NEW.received_weight, 0) * pct / 100, min_kg);

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


-- ============================================================
--  HISSA 14 — Ijazatein (27 wala tareeqa)
--
--  Nayi helper functions sirf triggers ke andar se chalti hain — bahar
--  (RPC) se kisi ke liye nahi. close_coil / recalc ki purani ijazat
--  waisi hi.
-- ============================================================

do $$
declare f text;
begin
  foreach f in array array[
    'public.cutting_tolerance_kg(numeric)',
    'public.cutting_job_is_delivered(uuid)',
    'public.cutting_job_invoice_no(uuid, uuid)',
    'public.cutting_challan_invoice_no(uuid)',
    'public.check_coil_delivery_cap(uuid)',
    'public.check_job_output_cap(uuid)',
    'public.check_job_billable(uuid, uuid)',
    'public.service_invoice_line_totals(uuid, boolean)',
    -- andar ke helper: sirf SECURITY DEFINER triggers chalate hain (34 ne bhi band kiye the)
    'public.recalc_coil_balances(uuid)',
    'public.recalc_service_invoice_totals(uuid)',
    'public.allocate_conversion_cost(uuid)'
  ] loop
    execute 'revoke all on function ' || f || ' from public, anon, authenticated';
  end loop;

  foreach f in array array[
    'public.close_coil(uuid, text, text)'
  ] loop
    execute 'revoke all on function ' || f || ' from public, anon';
    execute 'grant execute on function ' || f || ' to authenticated';
  end loop;
end $$;


-- ============================================================
--  Jaanch (sirf parhne wali — chala kar dekh lein)
--
--  1. Delivery tayyar maal se zyada (purana data):
--     select c.coil_serial, c.delivered_weight,
--            (select coalesce(sum(o.output_weight),0) from cutting_job_outputs o
--               join cutting_jobs j on j.id = o.job_id
--              where o.coil_id = c.id and j.deleted_at is null and j.status = 'completed') as ready
--       from coils c where c.ownership = 'party' and c.delivered_weight > 0
--      order by 1;
--
--  2. Invoice ke totals jo lines se mel nahi khate (purana data):
--     select si.sino, si.sub_total, si.tax_total, si.grand_total, t.*
--       from service_invoices si,
--            lateral service_invoice_line_totals(si.id, si.tax_on) t
--      where si.sub_total <> t.o_sub or si.tax_total <> t.o_tax
--         or si.grand_total <> round(t.o_sub - si.discount + t.o_tax, 2);
--     Theek karne ke liye (admin, SQL editor):
--       update service_invoices set sub_total = sub_total where id = '<id>';
--
--  3. App mein: Cutting Job mein size (Width 4 ft, Length 300 mm) → save →
--     Coil Ledger mein "4 ft x 300 mm x 20 pcs".
-- ============================================================
