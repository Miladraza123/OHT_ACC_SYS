-- ============================================================
--  11 — Seed data
--
--  Sirf wo records jo system ko chalne ke liye chahiye.
--  Koi party, item, voucher, ledger sheet, user ya company nahi —
--  client apna data khud daalega.
-- ============================================================

-- ---------- Period Lock ki single row ----------
-- (period_lock_id_check ki wajah se hamesha id = 1 hi hoti hai)

insert into period_lock (id, locked_before)
values (1, null)
on conflict (id) do nothing;

-- ---------- Party categories ----------
-- YAHAN KUCH NAHI DAALNA.
--
-- Customer, Supplier, Customer & Supplier, Expense head, Bank aur Other
-- app ke andar pehle se bane hue hain. party_kinds table sirf UN
-- categories ke liye hai jo user khud Masters se add kare.
--
-- Agar yahan wohi chaar daal diye jayein to dropdown mein har category
-- do-do dafa dikhti hai.

-- ---------- Default warehouse ----------
-- Kam se kam aik warehouse hona zaroori hai, warna bill par
-- warehouse select nahi ho payega. Naam client apni marzi se
-- Masters → Warehouses se badal sakta hai.

insert into warehouses (name, is_default, active)
select 'Main Store', true, true
where not exists (select 1 from warehouses where deleted_at is null);
