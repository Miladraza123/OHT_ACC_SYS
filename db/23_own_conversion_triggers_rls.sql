-- ============================================================
--  23 — Own Conversion: Triggers, guards, RLS
-- ============================================================

-- ---------- Number: CV-0001 ----------

create or replace function public.assign_conversion_number()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare prefix text;
begin
  if NEW.cno is not null and trim(NEW.cno) <> '' then return NEW; end if;
  select coalesce(conversion_prefix, 'CV') into prefix from cutting_settings where id = 1;
  NEW.cno := coalesce(prefix, 'CV') || '-' || lpad(nextval('cv_seq')::text, 4, '0');
  return NEW;
end;
$function$;

-- ---------- Guard: input coil company ki apni honi chahiye ----------

create or replace function public.trg_check_own_coil()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare c record;
begin
  if NEW.coil_id is null then return NEW; end if;

  select * into c from coils where id = NEW.coil_id;
  if not found then raise exception 'Coil mojood nahi'; end if;
  if c.deleted_at is not null then raise exception 'Coil % delete ho chuki hai', c.coil_serial; end if;

  if c.ownership <> 'own' then
    raise exception 'Coil % party ka maal hai — Own Conversion mein istemaal nahi ho sakti. Cutting Job banayein.',
      c.coil_serial;
  end if;
  if c.status <> 'active' then
    raise exception 'Coil % ka status "%" hai', c.coil_serial, c.status;
  end if;
  if c.item_id is distinct from NEW.item_id then
    raise exception 'Coil % ka item aur input line ka item alag hain', c.coil_serial;
  end if;

  return NEW;
end;
$function$;

-- ---------- Guard: conversion mein kam se kam ek output ho ----------
-- (input line delete hone par bhi hisaab durust rahe)

create or replace function public.trg_conversion_recalc()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare cid uuid;
begin
  -- RECURSION GUARD: engine khud cost_amount likhta hai — us likhai
  -- se dobara hisaab shuru na ho. Cost sirf qty/item/coil se badalti hai.
  if TG_OP = 'UPDATE'
     and NEW.item_id is not distinct from OLD.item_id
     and NEW.qty     is not distinct from OLD.qty
     and (to_jsonb(NEW) ->> 'coil_id') is not distinct from (to_jsonb(OLD) ->> 'coil_id') then
    return NEW;
  end if;

  cid := coalesce(NEW.conversion_id, OLD.conversion_id);
  perform recalc_conversion(cid);

  -- item badla to purana item bhi dobara gino
  if TG_OP = 'UPDATE' and OLD.item_id is distinct from NEW.item_id then
    perform recompute_item_cost(OLD.item_id);
  elsif TG_OP = 'DELETE' then
    perform recompute_item_cost(OLD.item_id);
  end if;

  return coalesce(NEW, OLD);
end;
$function$;

-- ---------- Header badle to poora conversion dobara ----------

create or replace function public.trg_conversion_header_recalc()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if NEW.cdate           is not distinct from OLD.cdate
     and NEW.status          is not distinct from OLD.status
     and NEW.deleted_at      is not distinct from OLD.deleted_at
     and NEW.conversion_cost is not distinct from OLD.conversion_cost then
    return NEW;
  end if;
  perform recalc_conversion(NEW.id);
  return NEW;
end;
$function$;

-- ---------- Own coil ka balance: conversion se kharch hua maal ----------
-- recalc_coil_balances ko badal rahe hain taake own coils ka
-- consumption stock_conversion_inputs se aaye. Party coils ka
-- hisaab bilkul pehle jaisa rehta hai.

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
  select * into c from coils where id = p_coil_id;
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
--  Triggers
-- ============================================================

drop trigger if exists trg_no_stock_conversions      on stock_conversions;
drop trigger if exists trg_audit_stock_conversions   on stock_conversions;
drop trigger if exists trg_log_stock_conversions     on stock_conversions;
drop trigger if exists trg_version_stock_conversions on stock_conversions;
drop trigger if exists trg_perm_stock_conversions    on stock_conversions;
drop trigger if exists trg_recalc_stock_conversions  on stock_conversions;

create trigger trg_no_stock_conversions      before insert                     on stock_conversions for each row execute function assign_conversion_number();
create trigger trg_audit_stock_conversions   before insert or update           on stock_conversions for each row execute function stamp_audit_fields();
create trigger trg_log_stock_conversions     after  insert or update or delete on stock_conversions for each row execute function log_audit_event();
create trigger trg_version_stock_conversions before update                     on stock_conversions for each row execute function bump_version();
create trigger trg_perm_stock_conversions    before update                     on stock_conversions for each row execute function enforce_perm_on_update('own_conversion_edit','own_conversion_cancel','recycle_bin');
create trigger trg_recalc_stock_conversions  after  update                     on stock_conversions for each row execute function trg_conversion_header_recalc();

drop trigger if exists trg_own_coil_check      on stock_conversion_inputs;
drop trigger if exists trg_recalc_conv_input   on stock_conversion_inputs;

create trigger trg_own_coil_check    before insert or update           on stock_conversion_inputs for each row execute function trg_check_own_coil();
create trigger trg_recalc_conv_input after  insert or update or delete on stock_conversion_inputs for each row execute function trg_conversion_recalc();

drop trigger if exists trg_recalc_conv_output on stock_conversion_outputs;
create trigger trg_recalc_conv_output after insert or update or delete on stock_conversion_outputs for each row execute function trg_conversion_recalc();

-- ============================================================
--  RLS
-- ============================================================

alter table stock_conversions        enable row level security;
alter table stock_conversion_inputs  enable row level security;
alter table stock_conversion_outputs enable row level security;

drop policy if exists "stock_conversions select" on stock_conversions;
drop policy if exists "stock_conversions insert" on stock_conversions;
drop policy if exists "stock_conversions update" on stock_conversions;
drop policy if exists "stock_conversions delete" on stock_conversions;

create policy "stock_conversions select" on stock_conversions for select
  using (is_app_admin() or has_perm('own_conversion_view') or has_perm('reports_view'));
create policy "stock_conversions insert" on stock_conversions for insert
  with check (is_app_admin() or has_perm('own_conversion_create'));
create policy "stock_conversions update" on stock_conversions for update
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "stock_conversions delete" on stock_conversions for delete using (is_app_admin());

drop policy if exists "stock_conversion_inputs select" on stock_conversion_inputs;
drop policy if exists "stock_conversion_inputs write"  on stock_conversion_inputs;

create policy "stock_conversion_inputs select" on stock_conversion_inputs for select
  using (is_app_admin() or has_perm('own_conversion_view') or has_perm('reports_view'));
create policy "stock_conversion_inputs write" on stock_conversion_inputs for all
  using (is_app_admin() or has_perm('own_conversion_create') or has_perm('own_conversion_edit'))
  with check (is_app_admin() or has_perm('own_conversion_create') or has_perm('own_conversion_edit'));

drop policy if exists "stock_conversion_outputs select" on stock_conversion_outputs;
drop policy if exists "stock_conversion_outputs write"  on stock_conversion_outputs;

create policy "stock_conversion_outputs select" on stock_conversion_outputs for select
  using (is_app_admin() or has_perm('own_conversion_view') or has_perm('reports_view'));
create policy "stock_conversion_outputs write" on stock_conversion_outputs for all
  using (is_app_admin() or has_perm('own_conversion_create') or has_perm('own_conversion_edit'))
  with check (is_app_admin() or has_perm('own_conversion_create') or has_perm('own_conversion_edit'));

-- ============================================================
--  Conversion ledger view
-- ============================================================

create or replace view conversion_ledger_v as
  select sc.id            as conversion_id,
         sc.cno,
         sc.cdate,
         'input'::text    as direction,
         ci.item_id,
         i.name           as item_name,
         ci.coil_id,
         c.coil_serial,
         ci.qty,
         ci.cost_amount,
         (case when ci.qty > 0 then round(ci.cost_amount / ci.qty, 4) else 0 end) as per_unit_cost,
         sc.conversion_cost,
         sc.status,
         ci.remarks
    from stock_conversion_inputs ci
    join stock_conversions sc on sc.id = ci.conversion_id
    join items i on i.id = ci.item_id
    left join coils c on c.id = ci.coil_id
   where sc.deleted_at is null

  union all
  select sc.id, sc.cno, sc.cdate, 'output',
         co.item_id, i.name, null::uuid, null::text,
         co.qty, co.cost_amount,
         (case when co.qty > 0 then round(co.cost_amount / co.qty, 4) else 0 end),
         sc.conversion_cost, sc.status, co.remarks
    from stock_conversion_outputs co
    join stock_conversions sc on sc.id = co.conversion_id
    join items i on i.id = co.item_id
   where sc.deleted_at is null;

alter view conversion_ledger_v set (security_invoker = on);

-- ---------- Own coil stock view ----------

create or replace view own_coil_stock_v as
select c.id            as coil_id,
       c.coil_serial,
       c.item_id,
       i.name          as item_name,
       i.item_form,
       c.warehouse_id,
       w.name          as warehouse_name,
       c.material_type,
       c.grade,
       c.thickness_mm,
       c.width_mm,
       c.received_weight,
       c.consumed_weight,
       c.raw_balance,
       i.avg_cost,
       round(c.raw_balance * i.avg_cost, 2) as balance_value,
       c.status,
       c.received_date,
       (current_date - c.received_date) as age_days
  from coils c
  join items i      on i.id = c.item_id
  join warehouses w on w.id = c.warehouse_id
 where c.deleted_at is null and c.ownership = 'own' and c.status <> 'cancelled';

alter view own_coil_stock_v set (security_invoker = on);

-- ---------- Seed: conversion prefix ----------

update cutting_settings set conversion_prefix = 'CV' where id = 1 and conversion_prefix is null;
