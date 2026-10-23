-- ============================================================
--  38 — Coil Transfer: nayi coil ka serial  <asal serial>-T1, -T2 ...
--
--  Sab se aakhir mein chalayein — 37 ke baad. Do baar chalana mehfooz hai.
--  Koi data nahi badalta; sirf create_coil_transfer ka naya version.
--
--  MASLA: 37 ne transfer ki nayi coil ko system ke counter (coil_seq) se
--  bilkul naya serial diya — jaise CUT-2026-000002 ki coil Bilal ko gayi to
--  Bilal ki coil CUT-2026-000003 ban gayi. Is se na pata chalta ke yeh wahi
--  physical coil hai, aur counter ka aik number bhi kharch hota.
--
--  HAL: nayi coil ka serial = asal coil ka serial + "-T" + number:
--       CUT-2026-000002  →  CUT-2026-000002-T1  →  (aage bikne par) -T2
--       Asal coil ka serial pehle jaisa rehta hai. coil_seq istemal nahi
--       hota, is liye counter mein gap nahi banta. Cancelled transfer ka
--       -T<n> dobara istemal nahi hota (agla number milta hai).
--
--  Purane (37 ke tahat bane) transfer ki coil ka serial NAHI badalta.
-- ============================================================

create or replace function public.create_coil_transfer(
  p_from_coil uuid,
  p_to_party  uuid,
  p_weight    numeric,
  p_date      date default current_date,
  p_reference text default '',
  p_remarks   text default ''
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c         record;
  tp        record;
  fp_name   text;
  v_w       numeric;
  v_tid     uuid := gen_random_uuid();
  v_cid     uuid := gen_random_uuid();
  v_tno     text;
  v_serial  text;
  v_base    text;
  v_n       int;
begin
  if auth.uid() is null or not (is_app_admin() or has_perm('cutting_transfer_create')) then
    raise exception 'Permission denied: cutting_transfer_create zaroori hai';
  end if;

  if p_weight is null or p_weight <= 0 then
    raise exception 'Transfer ka wazan 0 se zyada hona chahiye';
  end if;
  v_w := round(p_weight, 3);
  if v_w <= 0 then
    raise exception 'Transfer ka wazan 0 se zyada hona chahiye';
  end if;

  -- FOR UPDATE: do transfer ek saath ek hi coil se zyada maal na nikal saken.
  -- Lock ke baad raw_balance taza parhta hai (READ COMMITTED).
  select * into c from coils where id = p_from_coil for update;
  if not found then raise exception 'Coil mojood nahi'; end if;
  if c.deleted_at is not null then raise exception 'Coil % delete ho chuki hai', c.coil_serial; end if;
  if c.ownership <> 'party' then
    raise exception 'Coil % company ki apni coil hai — sirf party ki coil transfer ho sakti hai', c.coil_serial;
  end if;
  if c.status = 'cancelled' then raise exception 'Coil % cancel ho chuki hai', c.coil_serial; end if;
  if c.status = 'closed' then
    raise exception 'Coil % band ho chuki hai — transfer nahi ho sakta', c.coil_serial;
  end if;

  select * into tp from parties where id = p_to_party;
  if not found or tp.deleted_at is not null then
    raise exception 'Naya malik (party) mojood nahi';
  end if;
  if not tp.active then
    raise exception 'Party % band (inactive) hai — usay coil transfer nahi ho sakti', tp.name;
  end if;
  if tp.id = c.party_id then
    raise exception 'Coil % pehle se isi party (%) ki hai — doosri party chunein', c.coil_serial, tp.name;
  end if;

  if v_w > c.raw_balance then
    raise exception 'Coil % ka bina kata balance sirf % KG hai — % KG transfer nahi ho sakta (kata hua maal challan se jata hai, transfer se nahi)',
      c.coil_serial, c.raw_balance, v_w;
  end if;
  if v_w > c.physical_balance then
    raise exception 'Coil % ka physical balance sirf % KG hai — % KG transfer nahi ho sakta',
      c.coil_serial, c.physical_balance, v_w;
  end if;

  select name into fp_name from parties where id = c.party_id;
  v_tno := next_transfer_no();

  -- Nayi coil ka serial: asal coil ka serial + '-T1', '-T2' ... (coil_seq se naya number NAHI).
  -- Asal serial wahi rehta hai jo pehli dafa inward par bana; agle maalik ki coil mein sirf -T<n> barhta hai
  -- (CUT-2026-000002 → -T1 → -T2; -T1 coil aage bechi jaye to -T1-T1 nahi, balke -T2 / -T3).
  -- Do transfer ek saath hon to advisory lock se dono ko alag number milta hai.
  v_base := regexp_replace(c.coil_serial, '-T[0-9]+$', '');
  perform pg_advisory_xact_lock(hashtextextended('coil_transfer_serial:' || lower(v_base), 0));
  select coalesce(max(substring(k.coil_serial from length(v_base) + 3)::int), 0) + 1
    into v_n
    from coils k
   where lower(left(k.coil_serial, length(v_base) + 2)) = lower(v_base) || '-t'
     and substring(k.coil_serial from length(v_base) + 3) ~ '^[0-9]+$';
  v_serial := v_base || '-T' || v_n;

  insert into coils (id, coil_serial, ownership, party_id, item_id, warehouse_id, party_coil_ref,
                     material_type, grade, thickness_mm, width_mm,
                     received_weight, received_date, inward_id, transfer_id, status, remarks)
  values (v_cid, v_serial, 'party', tp.id, c.item_id, c.warehouse_id, c.party_coil_ref,
          c.material_type, c.grade, c.thickness_mm, c.width_mm,
          v_w, coalesce(p_date, current_date), null, v_tid, 'active',
          'Transfer in ← ' || coalesce(fp_name, '?') || ' (' || v_tno || ')');

  insert into coil_transfers (id, tno, tdate, from_party_id, to_party_id, from_coil_id, to_coil_id,
                              weight, reference, remarks, status)
  values (v_tid, v_tno, coalesce(p_date, current_date), c.party_id, tp.id, c.id, v_cid,
          v_w, coalesce(p_reference, ''), coalesce(p_remarks, ''), 'active');
  -- (after-insert trigger Ahmed ki coil ka balance dobara ginta hai)

  return jsonb_build_object(
    'id', v_tid,
    'tno', v_tno,
    'to_coil_id', v_cid,
    'to_coil_serial', v_serial,
    'from_coil_serial', c.coil_serial,
    'weight', v_w
  );
end;
$function$;

revoke all on function public.create_coil_transfer(uuid, uuid, numeric, date, text, text) from public, anon;
grant execute on function public.create_coil_transfer(uuid, uuid, numeric, date, text, text) to authenticated;
