-- ============================================================
--  31 — User banana aur password badalna, seedha app se
--
--  MASLA
--
--  Ab tak naya user banane ke liye do jagah jana parta tha:
--
--    1. Supabase Dashboard → Authentication → Users → Add user
--       (email banao, password rakho, "Auto Confirm" karo)
--    2. Wahan se UUID copy karo
--    3. App → Masters → Users → wo UUID paste karo, phir permissions
--
--  Yani har naye mulazim ke liye client ko Supabase ka dashboard
--  kholna parta — jahan us ka kaam hai hi nahi, aur jahan wo ghalti se
--  kuch aur bhi badal sakta hai. Aur agar kisi ka password bhool jaye
--  to phir wahi chakkar.
--
--  App yeh khud nahi kar sakti: naya login banane ke liye secret key
--  chahiye, jo kabhi browser mein nahi honi chahiye. Is liye yeh kaam
--  server par hona chahiye — admin ki tasdeeq ke saath.
--
--  HAL — do function
--
--    create_app_user(...)        naya user, ek hi qadam mein
--    set_app_user_password(...)  kisi ka password dobara set karna
--
--  Dono sirf admin ke liye. Bina login wale (anon) ko bilkul nahi —
--  wahi usool jo 27 wali file ne tay kiya.
--
--  30 ke baad chalayein.
-- ============================================================


-- ============================================================
--  HISSA 1 — Naya user banayein
--
--  Password bcrypt se hash hota hai — bilkul waise jaise Supabase khud
--  karta hai. Asal password kahin save nahi hota, na hi kisi report
--  mein aata hai.
--
--  crypt() aur gen_salt() "extensions" schema mein hain, "public" mein
--  nahi — is liye poora naam likhna zaroori hai.
-- ============================================================

create or replace function public.create_app_user(
  p_username text,
  p_password text,
  p_is_admin boolean default false,
  p_perms    jsonb   default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_clean  text;
  v_domain text;
  v_email  text;
  v_id     uuid;
begin
  if not is_app_admin() then
    raise exception 'Sirf admin naya user bana sakta hai';
  end if;

  -- Wahi safai jo app karti hai
  v_clean := lower(regexp_replace(coalesce(p_username, ''), '\s+', '', 'g'));

  if v_clean = '' then
    raise exception 'Username khali nahi ho sakta';
  end if;
  if position('@' in v_clean) > 0 then
    raise exception 'Username mein @ nahi ho sakta — sirf naam likhein';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'Password kam se kam 6 harf ka hona chahiye';
  end if;

  /* Domain us admin ke apne email se leta hai jo abhi yeh kaam kar raha
     hai. Is tarah har client ke apne domain par khud-ba-khud chalta hai
     — kisi setting mein likhne ki zaroorat nahi. */
  select split_part(email, '@', 2) into v_domain from auth.users where id = auth.uid();
  if v_domain is null or v_domain = '' then
    select split_part(email, '@', 2) into v_domain from auth.users order by created_at limit 1;
  end if;
  if v_domain is null or v_domain = '' then
    raise exception 'Login ka domain maloom nahi ho saka';
  end if;

  v_email := v_clean || '@' || v_domain;

  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'Yeh username pehle se mojood hai';
  end if;
  if exists (select 1 from app_users where username = v_clean) then
    raise exception 'Yeh username pehle se mojood hai';
  end if;

  v_id := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change,
    email_change_token_new, email_change_token_current, reauthentication_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    v_email, extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),                                            -- foran confirmed
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"email_verified":true}'::jsonb,
    now(), now(),
    '', '', '', '', '', ''
  );

  insert into auth.identities (
    user_id, provider, provider_id, identity_data, created_at, updated_at
  ) values (
    v_id, 'email', v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', v_email,
                       'email_verified', true, 'phone_verified', false),
    now(), now()
  );

  insert into app_users (id, username, is_admin, is_active, perms)
  values (v_id, v_clean, coalesce(p_is_admin, false), true, coalesce(p_perms, '{}'::jsonb));

  return jsonb_build_object('status', 'ok', 'id', v_id,
                            'username', v_clean, 'login_email', v_email);
end;
$function$;

revoke all on function public.create_app_user(text, text, boolean, jsonb) from public, anon;
grant execute on function public.create_app_user(text, text, boolean, jsonb) to authenticated;


-- ============================================================
--  HISSA 2 — Password dobara set karein
--
--  Kisi ka password bhool jaye to admin app se hi naya rakh de.
--  Purana password janne ki zaroorat nahi — yehi to baat hai.
--
--  Saath hi us shakhs ke saare khule hue session khatam kar dete hain,
--  taake purani device par koi khula na reh jaye.
-- ============================================================

create or replace function public.set_app_user_password(p_id uuid, p_password text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_email text;
begin
  if not is_app_admin() then
    raise exception 'Sirf admin password badal sakta hai';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'Password kam se kam 6 harf ka hona chahiye';
  end if;

  select email into v_email from auth.users where id = p_id;
  if v_email is null then
    raise exception 'Yeh user nahi mila';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
         updated_at         = now(),
         recovery_token     = '',
         recovery_sent_at   = null
   where id = p_id;

  -- Purani device par khula hua session ab kaam na kare
  delete from auth.refresh_tokens where user_id = p_id::text;
  delete from auth.sessions       where user_id = p_id;

  return jsonb_build_object('status', 'ok', 'login_email', v_email);
end;
$function$;

revoke all on function public.set_app_user_password(uuid, text) from public, anon;
grant execute on function public.set_app_user_password(uuid, text) to authenticated;


-- ============================================================
--  DEPLOYMENT par asar
--
--  Is file ke baad DEPLOYMENT.md ka qadam 8 (pehla Super Admin) sirf
--  EK dafa karna parta hai — wo pehla admin abhi bhi Supabase Dashboard
--  se banana hoga, kyunki app mein login karne ke liye pehle se koi
--  admin hona zaroori hai.
--
--  Us ke baad ke SAARE users app se hi bante hain:
--    Masters → Users → + New User → naam, password, permissions
--
--  Client ko Supabase ka dashboard kabhi kholna nahi parega.
-- ============================================================
