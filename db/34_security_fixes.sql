-- ============================================================
--  34 — Security fixes (8 October 2026 ka deep test)
--
--  Sab se aakhir mein chalayein — 33 ke baad. Do baar chalana mehfooz
--  hai (create or replace / drop policy if exists). Koi data nahi
--  badalta, koi purani row dobara nahi likhi jati.
--
--  ─── C1: apply_merged_lines se koi bhi user admin ban sakta tha ───
--
--  MASLA: apply_merged_lines SECURITY DEFINER thi, na table ki list na
--  permission ka check. Sirf bill_create wala user
--    rpc/apply_merged_lines {p_line_table:'app_users', ... is_admin:true}
--  chala kar khud admin ban jata tha, aur kisi bhi table ki rows mita
--  sakta tha. smart_merge_lines (fetch_lines_json ke zariye) har table
--  parh leti thi — audit_log bhi, jo sirf admin dekh sakta hai.
--  smart_merge_update 'conflict' ke jawab mein kisi bhi table ki row
--  wapas bhej deti thi.
--
--  HAL: teenon par wahi deewar jo 27 ne apply_merge par lagayi —
--  login + active user + sirf billing ki 5 line tables, aur har table
--  ka apna fk column. apply_merged_lines ab SECURITY INVOKER hai, yani
--  RLS us par bhi lagti hai, aur andar edit ki permission maangti hai
--  (bill_edit / quotation_edit / po_edit) — app is function ko sirf
--  PURANE document ki edit par chalati hai; naya document seedha
--  REST insert se banta hai. Line ki update ab sirf usi document ki
--  line par hoti hai jis ka id diya gaya.
--
--  Saath mein: line tables par UPDATE/DELETE ab edit ki permission
--  maangte hain (pehle bill_create wala bhi purane bill ki line PATCH
--  kar sakta tha). INSERT jaisa tha — create ya edit.
--
--  Purana chhupa hua masla bhi isi function mein tha: purane bill/
--  quotation/PO/return/transfer ki edit mein NAYI line daalne par
--  "null value in column id / voucher_id" ka error aata tha (id null
--  jata tha aur fk column bhara hi nahi jata tha). Ab nayi line ko
--  default id, sahi fk aur agla line_no milta hai, aur jo key table
--  mein column hi nahi (misal sale_qty in quotation_lines) wo chhor di
--  jati hai.
--
--  ─── C2: 27 naye install par poori rollback ho jati thi ───
--
--  27:95 rls_auto_enable() ka revoke karti thi jo kisi repo file mein
--  nahi banti. 27 ab us line ko guard karti hai. Jo database 27 ke
--  baghair chal rahe hain un ke liye 27 ki asal hifazat yahan dobara
--  (HISSA 7).
--
--  ─── M1: recompute_all_item_costs koi bhi chala sakta tha ───
--
--  MASLA: item_cost_snapshot (period lock ki buniyad) mita kar dobara
--  likh deti thi — har logged-in user ke liye khuli.
--  HAL: sirf admin ya period_lock wala. Andar ke 6 helper (app kabhi
--  direct call nahi karti, sirf triggers) bahar se band.
--  log_manual_audit ab sirf active user.
--
--  ─── M2: band (inactive) user sab kuch parh sakta tha ───
--
--  MASLA: is_active sirf likhne par dekha jata tha. Purana token — ya
--  naya login — se sara business data parha ja sakta tha.
--  HAL: har public table par ek RESTRICTIVE policy: user active ho tab
--  hi kuch dikhe (app_users mein apni row phir bhi dikhti hai, taake
--  app "account band hai" bata sake). Aur jab admin kisi ko band kare
--  to us ke auth.sessions / auth.refresh_tokens mita diye jate hain.
--
--  ─── M16: masters_edit wala Setup (currency, prefix, maali saal) badal sakta tha ───
--
--  HAL: app_settings ki update sirf admin. App mein Setup button ab bhi
--  masters_edit par dikhta hai (client1-masters.html:5725) — wahan
--  (me && me.isAdmin) hona chahiye, warna non-admin ko save par error
--  milega (data phir bhi mehfooz hai).
-- ============================================================


-- ============================================================
--  HISSA 1 — Active user ka helper
-- ============================================================

create or replace function public.is_active_app_user()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(
    (select is_active from app_users where id = auth.uid()),
    false
  );
$function$;


-- ============================================================
--  HISSA 2 — C1: merge functions par deewar
-- ============================================================

-- ---------- fetch_lines_json: sirf billing ki line tables ----------

create or replace function public.fetch_lines_json(p_line_table text, p_fk_col text, p_fk_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare result jsonb;
begin
  if not coalesce((p_line_table, p_fk_col) in (
       ('voucher_lines', 'voucher_id'), ('sales_return_lines', 'return_id'),
       ('stock_transfer_lines', 'transfer_id'), ('quotation_lines', 'quotation_id'),
       ('po_lines', 'po_id')), false) then
    raise exception 'fetch_lines_json is table par nahi chal sakti: %.%', p_line_table, p_fk_col;
  end if;

  execute format(
    'select coalesce(jsonb_agg(to_jsonb(t.*)), ''[]''::jsonb) from %I t where %I = $1',
    p_line_table, p_fk_col
  ) into result using p_fk_id;
  return result;
end;
$function$;

-- ---------- smart_merge_update: login + active + table ki list ----------

create or replace function public.smart_merge_update(
  p_table text, p_id uuid, p_original jsonb, p_new jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  current_row   jsonb;
  diff          jsonb;
  updated_row   jsonb;
  ignore_fields text[] := array[
    'id','created_at','created_by','updated_at','updated_by','version',
    'avg_cost','stock_qty','sub_total','subtotal','tax_total','grand_total'
  ];
  /* Wahi list jo apply_merge (27) mein hai */
  MERGE_TABLES text[] := array[
    'vouchers', 'sales_returns', 'stock_transfers',
    'quotations', 'purchase_orders',
    'parties', 'items', 'companies'
  ];
begin
  if auth.uid() is null then
    raise exception 'Pehle login karein';
  end if;
  if not is_active_app_user() then
    raise exception 'Aap ka account band hai';
  end if;
  -- Pehle list, phir parhna — warna 'conflict' ke jawab mein kisi bhi table ki row bahar jati thi
  if not (p_table = any (MERGE_TABLES)) then
    raise exception 'smart_merge_update is table par nahi chal sakta: %', p_table;
  end if;

  execute format('select to_jsonb(t.*) from %I t where id = $1 for update', p_table)
    into current_row using p_id;

  if current_row is null then
    return jsonb_build_object('status', 'missing');
  end if;

  diff := merge_diff(p_original, p_new, current_row, ignore_fields);

  if (diff->>'conflict')::boolean then
    return jsonb_build_object('status', 'conflict', 'fields', diff->'fields', 'current', current_row);
  end if;

  -- Edit ki permission trg_perm_<table> (enforce_perm_on_update) dekhta hai
  updated_row := apply_merge(p_table, p_id, diff->'merged');
  if updated_row is null then
    return jsonb_build_object('status', 'ok', 'row', current_row);
  end if;
  return jsonb_build_object('status', 'ok', 'row', updated_row);
end;
$function$;

-- ---------- smart_merge_lines: login + active + line table ki list ----------

create or replace function public.smart_merge_lines(
  p_line_table text, p_fk_col text, p_fk_id uuid,
  p_original_lines jsonb, p_new_lines jsonb, p_ignore_fields text[]
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  current_lines  jsonb;
  orig_map       jsonb;
  cur_map        jsonb;
  final_lines    jsonb := '[]'::jsonb;
  conflict_items text[] := array[]::text[];
  handled_ids    text[] := array[]::text[];
  elem           jsonb;
  lid            text;
  orig_line      jsonb;
  cur_line       jsonb;
  one_result     jsonb;
begin
  if auth.uid() is null then
    raise exception 'Pehle login karein';
  end if;
  if not is_active_app_user() then
    raise exception 'Aap ka account band hai';
  end if;
  -- table/fk ki list fetch_lines_json khud dekhti hai

  current_lines := fetch_lines_json(p_line_table, p_fk_col, p_fk_id);

  select coalesce(jsonb_object_agg(e->>'id', e), '{}'::jsonb) into orig_map
    from jsonb_array_elements(p_original_lines) e where e->>'id' is not null;

  select coalesce(jsonb_object_agg(e->>'id', e), '{}'::jsonb) into cur_map
    from jsonb_array_elements(current_lines) e where e->>'id' is not null;

  for elem in select * from jsonb_array_elements(p_new_lines) loop
    lid := elem->>'id';

    if lid is null then                       -- bilkul nayi line
      final_lines := final_lines || jsonb_build_array(elem - 'id');
      continue;
    end if;

    handled_ids := array_append(handled_ids, lid);
    orig_line := orig_map -> lid;
    cur_line  := cur_map  -> lid;

    if cur_line is null then                  -- kisi aur ne delete kar di
      continue;
    end if;

    if orig_line is null then                 -- user ke paas thi hi nahi
      final_lines := final_lines || jsonb_build_array(cur_line);
      continue;
    end if;

    one_result := merge_one_line(orig_line, elem, cur_line, p_ignore_fields);
    if (one_result->>'conflict')::boolean then
      conflict_items := array_append(conflict_items, coalesce(cur_line->>'item_id', 'item'));
    else
      final_lines := final_lines || jsonb_build_array(one_result->'merged');
    end if;
  end loop;

  -- jo lines kisi aur ne add ki hain, unhein bhi rakho
  for elem in select * from jsonb_array_elements(current_lines) loop
    lid := elem->>'id';
    if lid is not null and not (orig_map ? lid) and not (lid = any(handled_ids)) then
      final_lines := final_lines || jsonb_build_array(elem);
    end if;
  end loop;

  if array_length(conflict_items, 1) > 0 then
    return jsonb_build_object('status', 'conflict', 'items', to_jsonb(conflict_items));
  end if;

  return jsonb_build_object('status', 'ok', 'lines', final_lines);
end;
$function$;

-- ---------- apply_merged_lines: INVOKER + list + edit permission ----------

create or replace function public.apply_merged_lines(
  p_line_table text, p_fk_col text, p_fk_id uuid, p_final_lines jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  elem       jsonb;
  lid        text;
  keep_ids   text[] := array[]::text[];
  parts      text[];
  set_clause text;
  kv         record;
  v_fk       text;
  v_perm     text;
  v_cols     text[];
  v_ins      text[];
  v_list     text;
  v_next     integer;
begin
  if auth.uid() is null then
    raise exception 'Pehle login karein';
  end if;

  -- Har line table ka apna fk aur apni edit permission (09 ke trg_perm_* wali)
  select t.fk, t.perm into v_fk, v_perm
    from (values ('voucher_lines',        'voucher_id',   'bill_edit'),
                 ('sales_return_lines',   'return_id',    'bill_edit'),
                 ('stock_transfer_lines', 'transfer_id',  'bill_edit'),
                 ('quotation_lines',      'quotation_id', 'quotation_edit'),
                 ('po_lines',             'po_id',        'po_edit')) t(tbl, fk, perm)
   where t.tbl = p_line_table;

  if v_fk is null or v_fk <> p_fk_col then
    raise exception 'apply_merged_lines is table par nahi chal sakta: %.%', p_line_table, p_fk_col;
  end if;

  -- App yeh sirf purane document ki edit par chalati hai — is liye edit ki ijazat
  if not (is_app_admin() or has_perm(v_perm)) then
    raise exception 'Permission denied: % zaroori hai edit ke liye', v_perm;
  end if;

  select array_agg(a.attname::text) into v_cols
    from pg_attribute a
   where a.attrelid = format('public.%I', p_line_table)::regclass
     and a.attnum > 0 and not a.attisdropped;

  for elem in select * from jsonb_array_elements(p_final_lines) loop
    lid := elem->>'id';
    if lid is not null then
      keep_ids := array_append(keep_ids, lid);
      parts := array[]::text[];
      for kv in select key, value from jsonb_each_text(elem - 'id' - p_fk_col) loop
        if kv.key = any (v_cols) then
          parts := array_append(parts, format('%I = %L', kv.key, kv.value));
        end if;
      end loop;
      set_clause := array_to_string(parts, ', ');
      if set_clause is not null and set_clause != '' then
        -- sirf isi document ki line — kisi aur bill ki line ka id de kar usay nahi badla ja sakta
        execute format('update %I set %s where id = %L::uuid and %I = $1',
                       p_line_table, set_clause, lid, p_fk_col) using p_fk_id;
      end if;
    end if;
  end loop;

  if array_length(keep_ids, 1) > 0 then
    execute format('delete from %I where %I = $1 and not (id = any($2::uuid[]))', p_line_table, p_fk_col)
      using p_fk_id, keep_ids;
  else
    execute format('delete from %I where %I = $1', p_line_table, p_fk_col) using p_fk_id;
  end if;

  -- Nayi lines: id default se, fk yahan se, line_no aakhri ke baad
  execute format('select coalesce(max(line_no), 0) from %I where %I = $1', p_line_table, p_fk_col)
    into v_next using p_fk_id;

  for elem in select * from jsonb_array_elements(p_final_lines) e where e->>'id' is null loop
    elem := (elem - 'id') || jsonb_build_object(p_fk_col, p_fk_id);
    if not (elem ? 'line_no') or elem->>'line_no' is null then
      v_next := v_next + 1;
      elem := elem || jsonb_build_object('line_no', v_next);
    end if;
    select array_agg(k) into v_ins from jsonb_object_keys(elem) k where k = any (v_cols);
    select string_agg(format('%I', c), ', ') into v_list from unnest(v_ins) c;
    execute format('insert into %I (%s) select %s from jsonb_populate_record(null::%I, $1)',
                   p_line_table, v_list, v_list, p_line_table) using elem;
  end loop;

  return jsonb_build_object('status', 'ok');
end;
$function$;


-- ============================================================
--  HISSA 3 — Line tables: purani line badalna/mitana = edit permission
--
--  Pehle "create YA edit" se line ki update/delete ho jati thi, yani
--  sirf bill_create wala bhi purane bill ki line PATCH kar sakta tha.
--  Header par yeh pehle se edit maangta hai (trg_perm_*). Naya document
--  sirf INSERT karta hai — wo jaisa tha waisa.
-- ============================================================

drop policy if exists "voucher_lines update" on voucher_lines;
drop policy if exists "voucher_lines delete" on voucher_lines;
create policy "voucher_lines update" on voucher_lines for update
  using (is_app_admin() or has_perm('bill_edit'))
  with check (is_app_admin() or has_perm('bill_edit'));
create policy "voucher_lines delete" on voucher_lines for delete
  using (is_app_admin() or has_perm('bill_edit'));

do $$
declare
  t record;
begin
  for t in select * from (values
      ('sales_return_lines',   'bill_create',      'bill_edit'),
      ('stock_transfer_lines', 'bill_create',      'bill_edit'),
      ('quotation_lines',      'quotation_create', 'quotation_edit'),
      ('po_lines',             'po_create',        'po_edit')) v(tbl, cperm, eperm)
  loop
    execute format('drop policy if exists %I on %I', t.tbl || ' write',  t.tbl);
    execute format('drop policy if exists %I on %I', t.tbl || ' insert', t.tbl);
    execute format('drop policy if exists %I on %I', t.tbl || ' update', t.tbl);
    execute format('drop policy if exists %I on %I', t.tbl || ' delete', t.tbl);
    execute format('create policy %I on %I for insert with check (is_app_admin() or has_perm(%L) or has_perm(%L))',
                   t.tbl || ' insert', t.tbl, t.cperm, t.eperm);
    execute format('create policy %I on %I for update using (is_app_admin() or has_perm(%L)) with check (is_app_admin() or has_perm(%L))',
                   t.tbl || ' update', t.tbl, t.eperm, t.eperm);
    execute format('create policy %I on %I for delete using (is_app_admin() or has_perm(%L))',
                   t.tbl || ' delete', t.tbl, t.eperm);
  end loop;
end $$;


-- ============================================================
--  HISSA 4 — M1: recompute_all_item_costs sirf admin / period_lock
--
--  Body bilkul 22 wali — sirf shuru mein check.
-- ============================================================

create or replace function public.recompute_all_item_costs(lock_date date)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  it_id uuid;
  cv_id uuid;
  pass  integer;
begin
  if not (is_app_admin() or has_perm('period_lock')) then
    raise exception 'Permission denied: period_lock zaroori hai';
  end if;

  delete from item_cost_snapshot where true;

  for pass in 1..3 loop
    for it_id in select id from items loop
      perform recompute_item_cost(it_id);
    end loop;

    for cv_id in select id from stock_conversions
                  where deleted_at is null and status <> 'cancelled' order by cdate, id
    loop
      perform allocate_conversion_cost(cv_id);
    end loop;
  end loop;

  -- aakhri chakkar: allocation ke baad averages dobara
  for it_id in select id from items loop
    perform recompute_item_cost(it_id);
  end loop;

  if lock_date is not null then
    insert into item_cost_snapshot (item_id, as_of_date, avg_cost, stock_qty)
      select id, lock_date, avg_cost, stock_qty from items;
  end if;
end;
$function$;

-- ---------- log_manual_audit: sirf active user ----------

create or replace function public.log_manual_audit(
  p_table text, p_record_id uuid, p_label text, p_action text, p_changes jsonb
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not is_active_app_user() then
    raise exception 'Aap ka account band hai';
  end if;
  insert into audit_log (table_name, record_id, record_label, action, changed_by, changes)
    values (p_table, p_record_id, p_label, p_action, auth.uid(), p_changes);
end;
$function$;


-- ============================================================
--  HISSA 5 — M2: band user kuch nahi parhta, aur us ke sessions khatam
-- ============================================================

-- Har public table jis par RLS chalu hai (live par haath se bani bhi)
do $$
declare t record;
begin
  for t in
    select c.relname
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p') and c.relrowsecurity
  loop
    execute format('drop policy if exists %I on %I', 'active user only', t.relname);
    if t.relname = 'app_users' then
      -- apni row dikhti rahe — app usi se "account band hai" batati hai
      execute format('create policy %I on %I as restrictive for all to authenticated
                        using ((select is_active_app_user()) or id = (select auth.uid()))
                        with check ((select is_active_app_user()))', 'active user only', t.relname);
    else
      execute format('create policy %I on %I as restrictive for all to authenticated
                        using ((select is_active_app_user()))
                        with check ((select is_active_app_user()))', 'active user only', t.relname);
    end if;
  end loop;
end $$;

-- Band karte hi login khatam (31 ki set_app_user_password wala tareeqa)
create or replace function public.trg_revoke_sessions_on_deactivate()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  begin
    delete from auth.refresh_tokens where user_id = NEW.id::text;
    delete from auth.sessions       where user_id = NEW.id;
  exception when insufficient_privilege or undefined_table then
    -- sessions na mit sakein to bhi user band ho jaye; RLS ooper se data rok deti hai
    raise warning 'Sessions nahi mit sakay: %', sqlerrm;
  end;
  return NEW;
end;
$function$;

drop trigger if exists trg_revoke_sessions_on_deactivate on app_users;
create trigger trg_revoke_sessions_on_deactivate
  after update of is_active on app_users
  for each row
  when (OLD.is_active is distinct from false and NEW.is_active is false)
  execute function trg_revoke_sessions_on_deactivate();


-- ============================================================
--  HISSA 6 — M16: Setup (app_settings) sirf admin
--
--  using wahi rakha — is tarah non-admin ko chup-chaap "0 rows" ke
--  bajaye saaf error milta hai.
-- ============================================================

drop policy if exists "app_settings update" on app_settings;
create policy "app_settings update" on app_settings for update
  using (auth.role() = 'authenticated')
  with check (is_app_admin());


-- ============================================================
--  HISSA 7 — C2: 27 ki hifazat dobara (jin DBs mein 27 rollback hui)
-- ============================================================

do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.prorettype not in ('trigger'::regtype, 'event_trigger'::regtype)
  loop
    execute 'revoke all on function ' || f.sig || ' from public';
    execute 'revoke all on function ' || f.sig || ' from anon';
    execute 'grant execute on function ' || f.sig || ' to authenticated';
  end loop;
end $$;

-- Andar ke helper — app kabhi direct call nahi karti; triggers/definer functions owner ban kar chalate hain
revoke all on function public.apply_merge(text, uuid, jsonb)            from public, anon, authenticated;
revoke all on function public.fetch_lines_json(text, text, uuid)        from public, anon, authenticated;
revoke all on function public.recompute_item_cost(uuid)                 from public, anon, authenticated;
revoke all on function public.allocate_conversion_cost(uuid)            from public, anon, authenticated;
revoke all on function public.recalc_coil_balances(uuid)                from public, anon, authenticated;
revoke all on function public.recalc_conversion(uuid, integer)          from public, anon, authenticated;
revoke all on function public.recalc_service_invoice_totals(uuid)       from public, anon, authenticated;
revoke all on function public.returnable_qty(uuid)                      from public, anon, authenticated;
do $$ begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke all on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end $$;

-- RLS policies ke andar chalti hain — anon ko bhi (27 ki wajah wahi)
grant execute on function public.is_app_admin()       to anon;
grant execute on function public.has_perm(text)       to anon;
grant execute on function public.is_active_app_user() to anon;

-- search_path har function par
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, '{}')) c
        where c like 'search_path=%'
      )
  loop
    execute 'alter function ' || f.sig || ' set search_path to ''public''';
  end loop;
end $$;


-- ============================================================
--  TASDEEQ (chala kar dekhein)
--
--  select has_function_privilege('anon', 'public.apply_merge(text,uuid,jsonb)', 'execute');      -- false
--  select has_function_privilege('authenticated', 'public.recompute_item_cost(uuid)', 'execute'); -- false
--  select count(*) from pg_policies where policyname = 'active user only';                        -- har RLS table
-- ============================================================
