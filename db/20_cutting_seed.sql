-- ============================================================
--  20 — Cutting / Processing: Seed data
--
--  Sirf wo records jo system ko chalne ke liye chahiye.
--  Koi coil, koi job, koi invoice, koi party — kuch nahi.
-- ============================================================

-- ---------- Cutting Settings ki single row ----------
-- Coil finish threshold 200 KG default hai, magar hard-coded NAHI —
-- admin isay Settings se kabhi bhi badal sakta hai (requirement 17).

insert into cutting_settings (id, coil_finish_threshold_kg)
values (1, 200)
on conflict (id) do nothing;

-- ---------- Service Categories ----------
-- Yeh sirf shuruati list hai. User apni categories khud add,
-- edit aur delete kar sakta hai (requirement 22).
--
-- Rate yahan LOCK NAHI hai. default_calc_method sirf yeh tay karta
-- hai ke invoice line par shuru mein kaun sa tareeqa chuna hua aaye —
-- user usay bhi badal sakta hai, aur rate hamesha khud likhta hai
-- (requirement 23).

insert into service_categories (name, default_calc_method) values
  ('Cutting',        'kg'),
  ('Slitting',       'kg'),
  ('Cut-to-Length',  'kg'),
  ('Shearing',       'kg'),
  ('Decoiling',      'kg'),
  ('Leveling',       'kg'),
  ('Straightening',  'kg'),
  ('Bending',        'piece'),
  ('Loading',        'fixed'),
  ('Unloading',      'fixed'),
  ('Labour',         'fixed'),
  ('Transportation', 'fixed'),
  ('Other',          'fixed')
on conflict do nothing;
