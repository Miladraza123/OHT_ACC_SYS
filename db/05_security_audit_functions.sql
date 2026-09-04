-- ============================================================
--  05 — Security, audit & general helper functions
-- ============================================================

-- ---------- Helper: text/jsonb se saaf number nikalna ----------

create or replace function public.clean_num(v anyelement)
returns numeric
language plpgsql
immutable
as $function$
begin
  if v is null then return 0; end if;
  return coalesce(nullif(regexp_replace(v::text, '[^0-9.\-]', '', 'g'), '')::numeric, 0);
exception when others then
  return 0;
end;
$function$;

-- ---------- Kya current user admin hai? ----------

create or replace function public.is_app_admin()
returns boolean
language sql
security definer
set search_path to 'public'
as $function$
  select coalesce(
    (select is_active and is_admin from app_users where id = auth.uid()),
    false
  );
$function$;

-- ---------- Kya current user ke paas ye permission hai? ----------

create or replace function public.has_perm(perm_key text)
returns boolean
language sql
security definer
set search_path to 'public'
as $function$
  select coalesce(
    (select is_active and (is_admin or coalesce((perms->>perm_key)::boolean, false))
       from app_users where id = auth.uid()),
    false
  );
$function$;

-- ---------- created_by / updated_by / updated_at khud bhar dena ----------

create or replace function public.stamp_audit_fields()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if TG_OP = 'INSERT' then
    if NEW.created_by is null then NEW.created_by := auth.uid(); end if;
    NEW.updated_by := auth.uid();
    NEW.updated_at := now();
  elsif TG_OP = 'UPDATE' then
    NEW.updated_by := auth.uid();
    NEW.updated_at := now();
    NEW.created_by := OLD.created_by;   -- created_by kabhi na badle
  end if;
  return NEW;
end;
$function$;

-- ---------- version counter (concurrent-edit detection) ----------

create or replace function public.bump_version()
returns trigger
language plpgsql
as $function$
begin
  NEW.version := coalesce(OLD.version, 1) + 1;
  return NEW;
end;
$function$;

-- ---------- Audit trail: field-level diff logging ----------

create or replace function public.log_audit_event()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  label     text;
  changes   jsonb := '{}'::jsonb;
  key       text;
  old_val   text;
  new_val   text;
  rec_id    uuid;
  ignore_fields text[] := array[
    'updated_at','updated_by','created_at','created_by','version','avg_cost','stock_qty','id'
  ];
begin
  -- costing engine jaise system writes audit log mein nahi jate
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
  end if;

  if TG_OP = 'DELETE' then
    label := case TG_TABLE_NAME
      when 'vouchers'        then to_jsonb(OLD)->>'vno'
      when 'parties'         then to_jsonb(OLD)->>'name'
      when 'items'           then to_jsonb(OLD)->>'name'
      when 'companies'       then to_jsonb(OLD)->>'name'
      when 'quotations'      then to_jsonb(OLD)->>'qno'
      when 'purchase_orders' then to_jsonb(OLD)->>'pono'
      when 'sales_returns'   then to_jsonb(OLD)->>'rno'
      else null end;
    insert into audit_log (table_name, record_id, record_label, action, changed_by, changes)
      values (TG_TABLE_NAME, OLD.id, label, 'delete', auth.uid(), null);
    return OLD;
  end if;

  rec_id := NEW.id;
  label := case TG_TABLE_NAME
    when 'vouchers'        then to_jsonb(NEW)->>'vno'
    when 'parties'         then to_jsonb(NEW)->>'name'
    when 'items'           then to_jsonb(NEW)->>'name'
    when 'companies'       then to_jsonb(NEW)->>'name'
    when 'quotations'      then to_jsonb(NEW)->>'qno'
    when 'purchase_orders' then to_jsonb(NEW)->>'pono'
    when 'sales_returns'   then to_jsonb(NEW)->>'rno'
    else null end;

  if TG_OP = 'INSERT' then
    insert into audit_log (table_name, record_id, record_label, action, changed_by, changes)
      values (TG_TABLE_NAME, rec_id, label, 'create', auth.uid(), null);
    return NEW;
  end if;

  if OLD.deleted_at is null and NEW.deleted_at is not null then
    insert into audit_log (table_name, record_id, record_label, action, changed_by, changes)
      values (TG_TABLE_NAME, rec_id, label, 'delete', auth.uid(), null);
    return NEW;
  elsif OLD.deleted_at is not null and NEW.deleted_at is null then
    insert into audit_log (table_name, record_id, record_label, action, changed_by, changes)
      values (TG_TABLE_NAME, rec_id, label, 'restore', auth.uid(), null);
    return NEW;
  end if;

  for key in select jsonb_object_keys(to_jsonb(NEW)) loop
    if key = any(ignore_fields) then continue; end if;
    old_val := to_jsonb(OLD)->>key;
    new_val := to_jsonb(NEW)->>key;
    if old_val is distinct from new_val then
      changes := changes || jsonb_build_object(key, jsonb_build_array(old_val, new_val));
    end if;
  end loop;

  if changes = '{}'::jsonb then return NEW; end if;

  insert into audit_log (table_name, record_id, record_label, action, changed_by, changes)
    values (TG_TABLE_NAME, rec_id, label, 'update', auth.uid(), changes);
  return NEW;
end;
$function$;

-- ---------- Per-checkbox permission enforcement (DB level) ----------
--  TG_ARGV[0] = edit permission
--  TG_ARGV[1] = delete permission
--  TG_ARGV[2] = restore permission
--  Delete vs restore vs edit ka farq OLD.deleted_at / NEW.deleted_at se hota hai.
--  Costing engine apne writes se pehle app.system_write flag set karta hai,
--  taake system ke apne updates permission check se na atkein.

create or replace function public.enforce_perm_on_update()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  edit_perm    text := TG_ARGV[0];
  delete_perm  text := TG_ARGV[1];
  restore_perm text := TG_ARGV[2];
begin
  if coalesce(current_setting('app.system_write', true), '') = 'true' then
    return NEW;
  end if;

  if is_app_admin() then
    return NEW;
  end if;

  if OLD.deleted_at is null and NEW.deleted_at is not null then
    if not has_perm(delete_perm) then
      raise exception 'Permission denied: % zaroori hai delete ke liye', delete_perm;
    end if;
  elsif OLD.deleted_at is not null and NEW.deleted_at is null then
    if not has_perm(restore_perm) then
      raise exception 'Permission denied: % zaroori hai restore ke liye', restore_perm;
    end if;
  else
    if not has_perm(edit_perm) then
      raise exception 'Permission denied: % zaroori hai edit ke liye', edit_perm;
    end if;
  end if;

  return NEW;
end;
$function$;

-- ---------- Manual audit entry (frontend se call hoti hai) ----------

create or replace function public.log_manual_audit(
  p_table text, p_record_id uuid, p_label text, p_action text, p_changes jsonb
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  insert into audit_log (table_name, record_id, record_label, action, changed_by, changes)
    values (p_table, p_record_id, p_label, p_action, auth.uid(), p_changes);
end;
$function$;
