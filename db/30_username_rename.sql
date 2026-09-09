-- ============================================================
--  30 — Username badalna theek se (9 September 2026)
--
--  MASLA
--
--  Username do jagah rehta hai:
--
--    app_users.username   — app ki apni list (Masters → Users)
--    auth.users.email      — Supabase ka asal login record
--
--  Login hamesha email se hota hai. App user ka likha hua naam le kar
--  "<naam>@<domain>" bana kar Supabase ko bhejti hai (app-config.js
--  mein loginEmail dekhein).
--
--  Masters → Users se naam badalne par sirf app_users.username badalti
--  thi. auth.users.email purani hi reh jati thi. Nateeja:
--
--    * App mein naya naam nazar aata hai
--    * Magar login purane naam se hi hota hai
--    * Naye naam se koshish karo to "username and password did not
--      match" — aur banda samajhta hai ke password ghalat hai
--
--  Yani wo shakhs apne hi system se bahar ho jata, aur wajah kahin
--  likhi hui nahi thi.
--
--  App yeh khud theek nahi kar sakti: auth.users ko browser se badalna
--  mumkin nahi (us ke liye secret key chahiye, jo kabhi browser mein
--  nahi honi chahiye). Is liye yeh kaam server par karna parta hai.
--
--  27 wali file ke usool par: anon ko kuch nahi, sirf signed-in admin.
-- ============================================================

create or replace function public.rename_app_user(p_id uuid, p_new_username text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_old_email text;
  v_domain    text;
  v_new_email text;
  v_clean     text;
begin
  if not is_app_admin() then
    raise exception 'Sirf admin username badal sakta hai';
  end if;

  -- Wahi safai jo app karti hai: chhote harf, darmiyan ki jagah khatam
  v_clean := lower(regexp_replace(coalesce(p_new_username, ''), '\s+', '', 'g'));

  if v_clean = '' then
    raise exception 'Username khali nahi ho sakta';
  end if;
  if position('@' in v_clean) > 0 then
    raise exception 'Username mein @ nahi ho sakta — sirf naam likhein';
  end if;

  select email into v_old_email from auth.users where id = p_id;
  if v_old_email is null then
    raise exception 'Yeh user nahi mila';
  end if;

  /* Domain wahi rehta hai jo pehle se hai. Is tarah yeh function
     app-config.js ke authDomain par munhasir nahi — jo bhi domain us
     user ka pehle se hai, wohi chalta rahega. */
  v_domain    := split_part(v_old_email, '@', 2);
  v_new_email := v_clean || '@' || v_domain;

  -- Naam wahi hai — sirf app wali list theek kar do
  if v_new_email = v_old_email then
    update app_users set username = v_clean where id = p_id;
    return jsonb_build_object('status', 'ok', 'changed', false, 'username', v_clean);
  end if;

  if exists (select 1 from auth.users where email = v_new_email and id <> p_id) then
    raise exception 'Yeh username pehle se kisi aur ka hai';
  end if;
  if exists (select 1 from app_users where username = v_clean and id <> p_id) then
    raise exception 'Yeh username pehle se kisi aur ka hai';
  end if;

  -- Teenon jagah ek saath. Koi ek fail ho to poora rollback.
  update app_users  set username = v_clean     where id = p_id;
  update auth.users set email    = v_new_email where id = p_id;
  update auth.identities
     set identity_data = jsonb_set(identity_data, '{email}', to_jsonb(v_new_email))
   where user_id = p_id and provider = 'email';

  return jsonb_build_object('status', 'ok', 'changed', true,
                            'username', v_clean, 'login_email', v_new_email);
end;
$function$;

revoke all on function public.rename_app_user(uuid, text) from public, anon;
grant execute on function public.rename_app_user(uuid, text) to authenticated;


-- ============================================================
--  Purane users ki jaanch
--
--  Agar pehle kabhi kisi ka naam badla gaya ho to us ka login abhi bhi
--  purane naam par atka hoga. Yeh chala kar dekh lein — koi row aaye to
--  us user ka login us "login_naam" se hota hai jo yahan likha hai, na
--  ke us naam se jo app mein nazar aata hai.
-- ============================================================

-- select u.username as app_ka_naam,
--        split_part(au.email, '@', 1) as login_naam,
--        'in dono ka aik hona chahiye' as note
--   from app_users u
--   join auth.users au on au.id = u.id
--  where u.username <> split_part(au.email, '@', 1);

-- Theek karne ke liye (admin se login hone ke baad, app se ya SQL se):
--   select rename_app_user('<user ki id>', '<naya naam>');
