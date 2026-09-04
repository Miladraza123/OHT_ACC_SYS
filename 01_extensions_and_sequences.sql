-- ============================================================
--  01 — Extensions & Sequences
--  Naye (khaali) Supabase project par sab se pehle yeh chalayein.
--  Har file alag se chalayein — Supabase SQL Editor poori submission
--  ko ek transaction maanta hai, ek error sab rollback kar deta hai.
-- ============================================================

create extension if not exists pgcrypto;

-- Voucher numbering: S-0001 (sale), P-0001 (purchase)
create sequence if not exists voucher_sale_seq     start with 1 increment by 1;
create sequence if not exists voucher_purchase_seq start with 1 increment by 1;
