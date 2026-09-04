-- ============================================================
--  08 — RPCs: smart concurrent-edit merge, trial balance, test-data wipe
--
--  Smart merge ka usool:
--    - user ne field badli nahi  → DB wali value rakho
--    - DB mein field badli nahi  → user wali value rakho
--    - dono ne aik hi nayi value di → koi masla nahi
--    - dono ne alag alag badli    → conflict, user ko taaza data dikhao
-- ============================================================

-- ---------- Aik row ka field-by-field merge ----------

create or replace function public.merge_diff(
  p_original jsonb, p_new jsonb, p_current jsonb, p_ignore text[]
)
returns jsonb
language plpgsql
as $function$
declare
  merged    jsonb := '{}'::jsonb;
  conflicts text[] := array[]::text[];
  key_name  text;
  orig_val  text;
  new_val   text;
  cur_val   text;
begin
  for key_name in select jsonb_object_keys(p_new) loop
    if key_name = any(p_ignore) then continue; end if;

    orig_val := p_original ->> key_name;
    new_val  := p_new      ->> key_name;
    cur_val  := p_current  ->> key_name;

    if new_val is not distinct from orig_val then
      merged := merged || jsonb_build_object(key_name, p_current -> key_name);
    elsif cur_val is not distinct from orig_val then
      merged := merged || jsonb_build_object(key_name, p_new -> key_name);
    elsif new_val is not distinct from cur_val then
      merged := merged || jsonb_build_object(key_name, p_new -> key_name);
    else
      conflicts := array_append(conflicts, key_name);
    end if;
  end loop;

  if array_length(conflicts, 1) > 0 then
    return jsonb_build_object('conflict', true, 'fields', to_jsonb(conflicts));
  end if;
  return jsonb_build_object('conflict', false, 'merged', merged);
end;
$function$;

-- ---------- Aik line ka merge (line tables ke liye) ----------

create or replace function public.merge_one_line(
  p_original jsonb, p_new jsonb, p_current jsonb, p_ignore text[]
)
returns jsonb
language plpgsql
as $function$
declare
  merged       jsonb := '{}'::jsonb;
  key_name     text;
  orig_val     text;
  new_val      text;
  cur_val      text;
  has_conflict boolean := false;
begin
  for key_name in select jsonb_object_keys(p_new) loop
    if key_name = any(p_ignore) then continue; end if;

    orig_val := p_original ->> key_name;
    new_val  := p_new      ->> key_name;
    cur_val  := p_current  ->> key_name;

    if new_val is not distinct from orig_val then
      merged := merged || jsonb_build_object(key_name, p_current -> key_name);
    elsif cur_val is not distinct from orig_val then
      merged := merged || jsonb_build_object(key_name, p_new -> key_name);
    elsif new_val is not distinct from cur_val then
      merged := merged || jsonb_build_object(key_name, p_new -> key_name);
    else
      has_conflict := true;
    end if;
  end loop;

  if has_conflict then
    return jsonb_build_object('conflict', true);
  end if;
  return jsonb_build_object('conflict', false, 'merged', merged);
end;
$function$;

-- ---------- Merge shuda values DB par likhna ----------

create or replace function public.apply_merge(p_table text, p_id uuid, merged jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  kv          record;
  parts       text[] := array[]::text[];
  set_clause  text;
  updated_row jsonb;
begin
  for kv in select key, value from jsonb_each_text(merged) loop
    parts := array_append(parts, format('%I = %L', kv.key, kv.value));
  end loop;

  set_clause := array_to_string(parts, ', ');
  if set_clause is null or set_clause = '' then
    return null;
  end if;

  execute format(
    'update %I set %s, version = coalesce(version,1)+1, updated_at = now(), updated_by = $1 '
    'where id = $2 returning to_jsonb(%I.*)',
    p_table, set_clause, p_table
  ) into updated_row using auth.uid(), p_id;

  return updated_row;
end;
$function$;

-- ---------- Kisi table ki lines JSON mein nikalna ----------

create or replace function public.fetch_lines_json(p_line_table text, p_fk_col text, p_fk_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare result jsonb;
begin
  execute format(
    'select coalesce(jsonb_agg(to_jsonb(t.*)), ''[]''::jsonb) from %I t where %I = $1',
    p_line_table, p_fk_col
  ) into result using p_fk_id;
  return result;
end;
$function$;

-- ---------- Header row ka smart merge update ----------

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
begin
  execute format('select to_jsonb(t.*) from %I t where id = $1 for update', p_table)
    into current_row using p_id;

  if current_row is null then
    return jsonb_build_object('status', 'missing');
  end if;

  diff := merge_diff(p_original, p_new, current_row, ignore_fields);

  if (diff->>'conflict')::boolean then
    return jsonb_build_object('status', 'conflict', 'fields', diff->'fields', 'current', current_row);
  end if;

  updated_row := apply_merge(p_table, p_id, diff->'merged');
  if updated_row is null then
    return jsonb_build_object('status', 'ok', 'row', current_row);
  end if;
  return jsonb_build_object('status', 'ok', 'row', updated_row);
end;
$function$;

-- ---------- Lines ka smart merge ----------

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

-- ---------- Merge shuda lines DB par likhna ----------

create or replace function public.apply_merged_lines(
  p_line_table text, p_fk_col text, p_fk_id uuid, p_final_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  elem       jsonb;
  lid        text;
  keep_ids   text[] := array[]::text[];
  parts      text[];
  set_clause text;
  kv         record;
begin
  for elem in select * from jsonb_array_elements(p_final_lines) loop
    lid := elem->>'id';
    if lid is not null then
      keep_ids := array_append(keep_ids, lid);
      parts := array[]::text[];
      for kv in select key, value from jsonb_each_text(elem - 'id') loop
        parts := array_append(parts, format('%I = %L', kv.key, kv.value));
      end loop;
      set_clause := array_to_string(parts, ', ');
      if set_clause is not null and set_clause != '' then
        execute format('update %I set %s where id = %L::uuid', p_line_table, set_clause, lid);
      end if;
    end if;
  end loop;

  if array_length(keep_ids, 1) > 0 then
    execute format('delete from %I where %I = $1 and not (id = any($2::uuid[]))', p_line_table, p_fk_col)
      using p_fk_id, keep_ids;
  else
    execute format('delete from %I where %I = $1', p_line_table, p_fk_col) using p_fk_id;
  end if;

  execute format(
    'insert into %I select * from jsonb_populate_recordset(null::%I, $1) returning to_jsonb(%I.*)',
    p_line_table, p_line_table, p_line_table
  ) using (
    select coalesce(jsonb_agg(e - 'id'), '[]'::jsonb)
      from jsonb_array_elements(p_final_lines) e where e->>'id' is null
  );

  return jsonb_build_object('status', 'ok');
end;
$function$;

-- ============================================================
--  Trial Balance — server side par pura hisaab
--  Party ka balance = opening + bills (sale/purchase, minus paid)
--                     + daily-ledger ki credit/debit rows
--  Daily ledger row layout: [0]=debit amt, [2]=credit amt,
--                           [6]=credit party id, [7]=debit party id
-- ============================================================

create or replace function public.trial_balance()
returns table(party_id uuid, party_name text, balance numeric, side text)
language plpgsql
stable
as $function$
begin
  return query
  with opening as (
    select p.id as pid,
           (case when p.opening_side = 'dr' then 1 else -1 end) * clean_num(p.opening) as amt
      from parties p
     where p.deleted_at is null
  ),
  bills as (
    select v.party_id as pid,
           sum(
             (case when v.vtype = 'sale' then  1 else -1 end) * clean_num(v.grand_total)
           + (case when v.vtype = 'sale' then -1 else  1 end) * clean_num(v.paid)
           ) as amt
      from vouchers v
     where v.deleted_at is null and v.party_id is not null
     group by v.party_id
  ),
  cash_credit as (   -- row[6] = credit party (paisa aaya) → balance ghatta hai
    select nullif(row_data ->> 6, '')::uuid as pid,
           sum(clean_num(row_data ->> 2)) * -1 as amt
      from sheets s, jsonb_array_elements(s.rows) as row_data
     where s.deleted_at is null and row_data ->> 6 is not null and row_data ->> 6 <> ''
     group by row_data ->> 6
  ),
  cash_debit as (    -- row[7] = debit party (paisa gaya) → balance barhta hai
    select nullif(row_data ->> 7, '')::uuid as pid,
           sum(clean_num(row_data ->> 0)) as amt
      from sheets s, jsonb_array_elements(s.rows) as row_data
     where s.deleted_at is null and row_data ->> 7 is not null and row_data ->> 7 <> ''
     group by row_data ->> 7
  ),
  combined as (
    select pid, amt from opening
    union all select pid, amt from bills
    union all select pid, amt from cash_credit
    union all select pid, amt from cash_debit
  ),
  totals as (
    select pid, round(sum(amt), 2) as net
      from combined
     where pid is not null
     group by pid
  )
  select p.id, p.name, abs(t.net), (case when t.net >= 0 then 'dr' else 'cr' end)
    from totals t
    join parties p on p.id = t.pid
   where p.deleted_at is null and t.net <> 0
   order by p.name;
end;
$function$;

-- ============================================================
--  Test data wipe — sirf admin
--  p_include_masters = true ho to parties/items/companies bhi urha deta hai
-- ============================================================

create or replace function public.wipe_test_data(p_include_masters boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not is_app_admin() then
    raise exception 'Sirf admin ye kar sakta hai';
  end if;

  delete from voucher_lines;
  delete from quotation_lines;
  delete from po_lines;
  delete from sales_return_lines;
  delete from stock_transfer_lines;
  delete from stock_adjustments;
  delete from audit_log;
  delete from item_cost_snapshot;
  delete from party_opening_balances;
  delete from vouchers;
  delete from quotations;
  delete from purchase_orders;
  delete from sales_returns;
  delete from stock_transfers;
  delete from sheets;

  update items set avg_cost = 0, stock_qty = 0;
  update period_lock set locked_before = null where id = 1;

  if p_include_masters then
    delete from parties;
    delete from items;
    delete from companies;
  end if;

  return jsonb_build_object('status', 'ok');
end;
$function$;
