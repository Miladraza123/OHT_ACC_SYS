-- ============================================================
--  33 — Cutting size ke alag alag unit (10 September 2026)
--
--  MASLA
--
--  Ab tak har cutting size ka SIRF EK unit hota tha (size_unit) —
--  width aur length dono usi mein. Magar workshop mein aksar aisa hota
--  hai ke chaurai millimeter mein hoti hai aur lambai feet mein:
--
--      1220mm × 50ft
--      4ft × 300mm
--
--  Purane dhanche mein yeh likha hi nahi ja sakta tha.
--
--  Doosri baat: ginti kabhi kilo mein hoti hai, kabhi pieces mein, aur
--  kabhi running feet mein. Pehle sirf pieces aur KG thay.
--
--  HAL — chaar naye column
--
--    width_unit   width ka apna unit   (mm / inch / ft)
--    length_unit  length ka apna unit  (mm / inch / ft)
--    qty          receipt par chhapne wali ginti
--    qty_unit     us ginti ka unit     (Kg / Pcs / Ft — aur jo aage chahiye)
--
--  AHEM BAATEIN
--
--  * output_weight (KG) jaise ka waisa hai. Coil ka balance, cutting
--    loss aur costing — sab usi par chalte hain. Us ko haath nahi lagaya.
--  * pieces bhi jaise ka waisa. Reports usi se banti hain.
--  * qty khali bhi ho sakti hai. Us soorat mein receipt khud KG ya
--    pieces se ginti utha leti hai — dobara likhne ki zaroorat nahi.
--  * size_unit purani rows ke liye rehne diya hai (purani reports usay
--    parhti hain). Nayi rows mein wo width_unit ke barabar likha jata hai.
--  * qty_unit par koi sakht rok NAHI lagai — aage koi naya unit chahiye
--    (Meter, Ton, Bundle) to bas app mein add kar dein, SQL badalne ki
--    zaroorat nahi paregi.
--
--  32 ke baad chalayein.
-- ============================================================

alter table cutting_job_outputs add column if not exists width_unit  text;
alter table cutting_job_outputs add column if not exists length_unit text;
alter table cutting_job_outputs add column if not exists qty         numeric;
alter table cutting_job_outputs add column if not exists qty_unit    text;

-- ---------- Purani rows: dono unit wahi jo pehle tha ----------

update cutting_job_outputs
   set width_unit = coalesce(nullif(width_unit, ''), nullif(size_unit, ''), 'mm')
 where width_unit is null or width_unit = '';

update cutting_job_outputs
   set length_unit = coalesce(nullif(length_unit, ''), nullif(size_unit, ''), 'mm')
 where length_unit is null or length_unit = '';

update cutting_job_outputs
   set qty_unit = 'Kg'
 where qty_unit is null or qty_unit = '';

-- ---------- Ab default aur "khali na ho" ka usool ----------

alter table cutting_job_outputs alter column width_unit  set default 'mm';
alter table cutting_job_outputs alter column length_unit set default 'mm';
alter table cutting_job_outputs alter column qty_unit    set default 'Kg';

alter table cutting_job_outputs alter column width_unit  set not null;
alter table cutting_job_outputs alter column length_unit set not null;
alter table cutting_job_outputs alter column qty_unit    set not null;

-- ---------- Sirf naap ke unit par rok ----------
--  Ginti (qty_unit) par jaan boojh kar koi rok nahi — taake aage naya
--  unit sirf app mein add karna paray, database chhedna na paray.

do $$ begin
  alter table cutting_job_outputs add constraint cutting_job_outputs_width_unit_check
    check (width_unit in ('mm', 'inch', 'ft'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table cutting_job_outputs add constraint cutting_job_outputs_length_unit_check
    check (length_unit in ('mm', 'inch', 'ft'));
exception when duplicate_object then null; end $$;


-- ============================================================
--  Jaanch
--
--  Yeh chala kar dekhein — har purani row ke dono unit wahi hone
--  chahiyen jo pehle size_unit mein thay:
--
--    select size_unit, width_unit, length_unit, qty, qty_unit, count(*)
--      from cutting_job_outputs
--     group by 1,2,3,4,5
--     order by 1,2,3;
--
--  App mein: Cutting Job kholein → koi size → Width aur Length ke apne
--  apne unit. Phir Print → "Receipt Print" — mila kar dekh lein.
--
--  Yeh file chalane se PEHLE bhi app chalti rehti hai: wo pehle dekh
--  leti hai ke naye column mojood hain ya nahi, aur na hon to purane
--  tareeqe par kaam karti hai. Is liye koi jaldi nahi — magar naye unit
--  aur Receipt Print isi ke baad kaam karenge.
-- ============================================================
