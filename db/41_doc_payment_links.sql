-- ============================================================
--  41 — Daily Ledger ki entry ko Invoice / Bill se jorna (optional)
--
--  Ab invoice ya bill mein "Paid" nahi likhte. Paisa sirf Daily Ledger mein likhte
--  hain, aur chahein to us line ko ek invoice / bill se jor dete hain. Isse:
--    * paisa party ke khate mein sirf EK dafa ginta hai (double entry nahi),
--    * invoice par Paid / Partial / Unpaid aur Baqi khud nikalta hai.
--
--  Daily Ledger ki sheet (sheets.rows) ko BILKUL nahi chheda jata — jor alag table
--  doc_payment_links mein rehta hai, line ki pakki pehchan (row[8]) se.
--  Purane bills ka `paid` jyun ka tyun; naye bill par 0 rehta hai.
--  Dobara chalana mehfooz hai. Koi purana data nahi badalta.
-- ============================================================

create table if not exists public.doc_payment_links (
  id          uuid        not null default gen_random_uuid() primary key,
  doc_kind    text        not null check (doc_kind in ('voucher', 'service')),   -- voucher = Sale / Purchase bill
  doc_id      uuid        not null,
  sheet_date  date        not null,
  row_id      text        not null,                                              -- sheets.rows[n][8]
  side        text        not null check (side in ('cr', 'dr')),                 -- cr = paisa aaya, dr = paisa gaya
  created_at  timestamptz not null default now(),
  created_by  uuid        default auth.uid(),
  unique (sheet_date, row_id, side)
);
create index if not exists doc_payment_links_doc_idx  on public.doc_payment_links (doc_kind, doc_id);
create index if not exists doc_payment_links_date_idx on public.doc_payment_links (sheet_date);

alter table public.doc_payment_links enable row level security;

drop policy if exists "doc_payment_links select" on public.doc_payment_links;
drop policy if exists "doc_payment_links write"  on public.doc_payment_links;
drop policy if exists "active user only"         on public.doc_payment_links;

create policy "doc_payment_links select" on public.doc_payment_links for select
  using (auth.role() = 'authenticated');
create policy "doc_payment_links write" on public.doc_payment_links for all
  using (is_app_admin() or has_perm('ledger_create'))
  with check (is_app_admin() or has_perm('ledger_create'));
create policy "active user only" on public.doc_payment_links as restrictive for all to authenticated
  using ((select is_active_app_user()))
  with check ((select is_active_app_user()));

revoke all on public.doc_payment_links from anon;
revoke all on public.doc_payment_links from public;
grant select, insert, update, delete on public.doc_payment_links to authenticated;
grant all on public.doc_payment_links to service_role;

-- Jori hui lines ki asal raqam — hamesha sheet se taaza (line badle / mite to khud badal jata hai).
-- Sirf wahi line gini jati hai jis ki party wahi hai jo bill ki hai.
create or replace view public.doc_payments as
select l.id           as link_id,
       l.doc_kind,
       l.doc_id,
       l.sheet_date,
       l.row_id,
       l.side,
       case l.side when 'cr' then public.clean_num(r.row_data ->> 2)
                              else public.clean_num(r.row_data ->> 0) end as amount
  from public.doc_payment_links l
  join public.sheets s on s.sheet_date = l.sheet_date and s.deleted_at is null
 cross join lateral jsonb_array_elements(s.rows) as r(row_data)
 where r.row_data ->> 8 = l.row_id
   and (case l.side when 'cr' then r.row_data ->> 6 else r.row_data ->> 7 end) =
       (case l.doc_kind
          when 'voucher' then (select v.party_id::text from public.vouchers v where v.id = l.doc_id)
          else               (select si.party_id::text from public.service_invoices si where si.id = l.doc_id)
        end);

alter view public.doc_payments set (security_invoker = on);
grant select on public.doc_payments to authenticated;
grant select on public.doc_payments to service_role;

-- ============================================================
--  Jaanch (sirf parhne wali)
--  select to_regclass('public.doc_payment_links') is not null as table_ok,
--         to_regclass('public.doc_payments')      is not null as view_ok;      -- true, true
-- ============================================================
