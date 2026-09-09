-- ============================================================
--  32 — Apna password khud badalna (9 September 2026)
--
--  MASLA
--
--  Sidebar → "Change Password" dabane par app kehti thi
--  "Password badal diya gaya" — magar password badalta nahi tha.
--  Agli dafa login purane hi password se hota tha.
--
--  Wajah: app Supabase ke apne `auth.updateUser()` par bharosa kar
--  rahi thi. Us call ka jawab "theek hai" aa jata tha, lekin
--  auth.users mein password ki koi tabdeeli nahi hoti thi — yani
--  kaamyabi ka paighaam jhoota tha. auth.users.updated_at gawah hai:
--  wo sirf login ke waqt badla, password badalne ke waqt bilkul nahi.
--
--  Aisi khamoshi sab se khatarnak cheez hai: banda samajhta hai ke
--  us ne password mehfooz kar liya, halanke purana password abhi bhi
--  chal raha hota hai.
--
--  HAL
--
--  Password badalna ab server par hota hai — bilkul usi tarah jaise
--  create_app_user aur set_app_user_password (file 31) karte hain,
--  jo chal rahe hain aur jinka nateeja sach hota hai.
--
--  Yeh function:
--
--    * Sirf usi shakhs ka password badalta hai jo abhi login hai
--      (auth.uid()) — kisi aur ka nahi, admin ho ya na ho.
--    * Pehle MOJOODA password ki tasdeeq karta hai. Yani khuli hui
--      device par baith kar koi aur aap ka password nahi badal sakta.
--    * Naya password purane jaisa ho to mana kar deta hai.
--    * Row asal mein badli ya nahi — yeh ginn kar batata hai. Is liye
--      "ok" ka matlab waqai "ho gaya" hai.
--    * Baaqi devices ke session band kar deta hai; jis device par abhi
--      kaam ho raha hai wo chalta rehta hai.
--
--  27 wali file ka usool wahi: anon ko kuch nahi, sirf signed-in user.
--
--  31 ke baad chalayein.
-- ============================================================

create or replace function public.change_my_password(p_current text, p_new text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id      uuid := auth.uid();
  v_email   text;
  v_hash    text;
  v_sid     uuid;
  v_rows    int;
  v_updated timestamptz;
begin
  if v_id is null then
    raise exception 'Aap logged in nahi hain — dobara login karein';
  end if;

  select email, encrypted_password into v_email, v_hash
    from auth.users where id = v_id;

  if v_email is null then
    raise exception 'Aap ka login record nahi mila';
  end if;

  /* Mojooda password ki tasdeeq. crypt() aur gen_salt() "extensions"
     schema mein hain, "public" mein nahi — poora naam zaroori hai. */
  if coalesce(v_hash, '') = '' or v_hash <> extensions.crypt(coalesce(p_current, ''), v_hash) then
    raise exception 'Mojooda password ghalat hai';
  end if;

  if length(coalesce(p_new, '')) < 6 then
    raise exception 'Naya password kam se kam 6 harf ka hona chahiye';
  end if;

  if v_hash = extensions.crypt(p_new, v_hash) then
    raise exception 'Naya password purane se mukhtalif hona chahiye';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_new, extensions.gen_salt('bf')),
         updated_at         = now(),
         recovery_token     = '',
         recovery_sent_at   = null
   where id = v_id
   returning updated_at into v_updated;

  /* Yehi wo jaanch hai jo pehle nahi thi: agar koi row nahi badli to
     "ho gaya" kehna jhoot hoga. */
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'Password mehfooz nahi hua — dobara koshish karein';
  end if;

  /* Jis device par abhi kaam ho raha hai us ka session bacha lein,
     baaqi sab band. session_id access-token mein hota hai; kisi wajah
     se na mile to ehtiyatan saare session band kar dete hain. */
  begin
    v_sid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception when others then
    v_sid := null;
  end;

  delete from auth.sessions
   where user_id = v_id
     and (v_sid is null or id <> v_sid);

  /* Purane (session se juday hue nahi) refresh token bhi saaf. Jo
     session se juday hain wo upar wale delete ke saath khud chale
     jate hain (cascade). */
  if v_sid is null then
    delete from auth.refresh_tokens where user_id = v_id::text;
  end if;

  return jsonb_build_object('status', 'ok', 'changed', true,
                            'login_email', v_email,
                            'updated_at', v_updated);
end;
$function$;

revoke all on function public.change_my_password(text, text) from public, anon;
grant execute on function public.change_my_password(text, text) to authenticated;


-- ============================================================
--  Jaanch
--
--  App se: Masters → Change Password → mojooda + naya password.
--  "Password badal diya gaya" tabhi likha aayega jab waqai badal chuka
--  ho. Us ke baad sign out kar ke naye password se login karein —
--  purana password ab nahi chalega.
--
--  Yeh dekhne ke liye ke password waqai badla:
--
--    select email, updated_at from auth.users order by email;
--
--  updated_at abhi ka waqt dikhana chahiye.
-- ============================================================
