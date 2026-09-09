-- ============================================================
--  27 — Security hardening (9 September 2026)
--
--  Supabase ke apne security linter ne teen masle nikale. Do asli hain.
--
--  ─── MASLA 1: bina login ke database ko haath lagaya ja sakta tha ───
--
--  Postgres har nayi function par by default "PUBLIC" ko chalane ki
--  ijazat de deta hai. Supabase mein PUBLIC ka matlab `anon` role bhi
--  hai — yani wo shakhs bhi jis ne login hi nahi kiya.
--
--  Aur publishable (anon) key koi raaz nahi hai. Wo har browser mein
--  khuli parhi hai — kisi bhi user ke phone par "View Source" karne se
--  mil jati hai. Yehi us ka maqsad hai; usay RLS rokti hai.
--
--  Magar SECURITY DEFINER wali function RLS ko nahi maanti — wo owner
--  (postgres) ban kar chalti hai. Nateeja: 14 aisi functions thin jinhein
--  bina login ke chalaya ja sakta tha, aur wo RLS ke ooper se guzar jatin.
--
--  Sab se buri do:
--
--    apply_merge(p_table, p_id, merged)
--      Koi bhi table, koi bhi row, koi bhi column — jo marzi update kar
--      dein. Na table ki koi list, na permission ka koi check. Sirf
--      publishable key se koi bhi shakhs kisi bhi bill, party balance ya
--      stock ko badal sakta tha.
--
--    fetch_lines_json(p_line_table, p_fk_col, p_fk_id)
--      Kisi bhi table ka data parh kar bahar nikal sakti thi.
--
--  Yeh dono app kabhi call hi nahi karti — sirf smart_merge_* ke andar
--  se chalti hain. Is liye inhein bahar se bilkul band kar dena mehfooz
--  hai, aur zaroori bhi.
--
--  ─── MASLA 2: search_path khula tha ───
--
--  12 functions par search_path set nahi tha. Aisi function ko dhoka
--  dena mumkin hota hai — usay asal ke bajaye koi aur table dikha kar.
--
--  ─── Kya NAHI toota ───
--
--  App har RPC login ke BAAD chalati hai (teenon files mein login gate
--  pehle aata hai). Is liye `authenticated` ki ijazat jyun ki tyun rakhi
--  gayi hai. is_app_admin() aur has_perm() ko bhi — yeh RLS policies ke
--  andar chalti hain, in ki ijazat chhin lein to poora system band ho
--  jaye.
--
--  Sab se aakhir mein chalayein — 26 ke baad.
-- ============================================================


-- ============================================================
--  HISSA 1 — Bina login wale (anon) ke liye sab band
--
--  Pehle PUBLIC aur anon se sab kuch wapas lete hain, phir signed-in
--  users ko wapas de dete hain. Sirf revoke ... from anon kaafi NAHI
--  hota — ijazat PUBLIC ke raaste bhi aati hai, aur wo alag se hatani
--  parti hai.
--
--  Trigger wali functions ko haath nahi lagate: unhein RPC se chalaya
--  hi nahi ja sakta (Postgres kehta hai "can only be called as trigger"),
--  aur trigger chalte waqt ijazat dobara nahi dekhi jati.
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
      and p.prorettype <> 'trigger'::regtype
  loop
    execute 'revoke all on function ' || f.sig || ' from public';
    execute 'revoke all on function ' || f.sig || ' from anon';
    execute 'grant execute on function ' || f.sig || ' to authenticated';
  end loop;
end $$;


-- ============================================================
--  HISSA 2 — Andar ke helper bahar se bilkul band
--
--  Yeh teenon app kabhi call nahi karti. apply_merge aur
--  fetch_lines_json sirf smart_merge_update / smart_merge_lines ke andar
--  se chalti hain — aur wo SECURITY DEFINER hain, is liye andar ka call
--  owner ban kar chalta hai. Bahar se ijazat khatam karne se andar ka
--  raasta band NAHI hota.
-- ============================================================

revoke all on function public.apply_merge(text, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.fetch_lines_json(text, text, uuid) from public, anon, authenticated;
revoke all on function public.rls_auto_enable() from public, anon, authenticated;


-- ------------------------------------------------------------
--  Do function anon ko wapas — jaan boojh kar
--
--  is_app_admin() aur has_perm() lagbhag har RLS policy ke andar
--  chalti hain. Agar session khatam ho chuka ho aur koi query chali
--  jaye, to bina ijazat ke Postgres "permission denied for function"
--  ka error deta — jo user ko samajh hi nahi aata.
--
--  Ijazat dena mehfooz hai: dono auth.uid() dekhti hain. Login na ho to
--  auth.uid() khali hota hai, app_users mein koi row nahi milti, aur
--  coalesce false laut'ta hai. Na koi data bahar jata hai, na koi
--  ijazat milti hai — bas saaf "nahi" milta hai.
-- ------------------------------------------------------------

grant execute on function public.is_app_admin()   to anon;
grant execute on function public.has_perm(text)   to anon;


-- ============================================================
--  HISSA 3 — apply_merge ke andar bhi taala
--
--  Ooper wala revoke asal hifazat hai. Yeh doosri deewar hai — agar
--  kabhi ghalti se ijazat wapas de di jaye (misal ke tor par koi
--  "grant all on all functions" chala de) to bhi ahem tables mehfooz
--  rahein.
--
--  Function ka kaam bilkul wahi hai jo pehle tha — sirf shuru mein do
--  check aur us ki apni table ki list barh gayi hai. smart_merge_update
--  isi list ke saath chalti hai, is liye app par koi farq nahi parta.
-- ============================================================

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
  /* Wahi list jo smart_merge_update mein hai. Nayi table wahan daalein
     to yahan bhi daalein — warna us ka merge kaam nahi karega. */
  MERGE_TABLES text[] := array[
    'vouchers', 'sales_returns', 'stock_transfers',
    'quotations', 'purchase_orders',
    'parties', 'items', 'companies'
  ];
begin
  -- Bina login ke koi nahi
  if auth.uid() is null then
    raise exception 'Pehle login karein';
  end if;

  -- Sirf yehi tables — app_users, period_lock, app_settings waghera kabhi nahi
  if not (p_table = any (MERGE_TABLES)) then
    raise exception 'apply_merge is table par nahi chal sakta: %', p_table;
  end if;

  for kv in select key, value from jsonb_each_text(merged) loop
    parts := array_append(parts, format('%I = %L', kv.key, kv.value));
  end loop;

  set_clause := array_to_string(parts, ', ');
  if set_clause is null or set_clause = '' then
    return null;
  end if;

  execute format(
    'update %I set %s, version = coalesce(version,1)+1, updated_at = now(), updated_by = $1 where id = $2 returning to_jsonb(%I.*)',
    p_table, set_clause, p_table)
    into updated_row using auth.uid(), p_id;

  return updated_row;
end;
$function$;

revoke all on function public.apply_merge(text, uuid, jsonb) from public, anon, authenticated;


-- ============================================================
--  HISSA 4 — search_path har function par set
--
--  Jin par pehle se set hai unhein chhorta hai.
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
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, '{}')) c
        where c like 'search_path=%'
      )
  loop
    execute 'alter function ' || f.sig || ' set search_path to ''public''';
  end loop;
end $$;


-- ============================================================
--  HISSA 5 — Haath se karne wali ek cheez
--
--  Supabase Dashboard → Authentication → Policies (ya Providers →
--  Email) mein "Leaked password protection" chalu kar dein. Is se
--  Supabase naya password HaveIBeenPwned ki list se milata hai aur
--  chura hua password rakhne nahi deta. Yeh SQL se nahi hota.
-- ============================================================
