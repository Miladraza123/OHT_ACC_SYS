-- ============================================================
--  40 — Service Invoice: har charge ki line kisi job se jur sakti hai
--
--  Invoice ki print mein ab har job ki tafseel (challan, coil, material, thickness)
--  ke neeche usi job ke charges aate hain. Is ke liye service_invoice_lines mein
--  job_id (aur sub_order_id) — dono khali ho sakte hain (purani lines / alag charge).
--  Koi data nahi badalta. Dobara chalana mehfooz hai.
-- ============================================================

alter table public.service_invoice_lines add column if not exists job_id uuid;
alter table public.service_invoice_lines add column if not exists sub_order_id uuid;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'service_invoice_lines_job_fkey') then
    alter table public.service_invoice_lines add constraint service_invoice_lines_job_fkey
      foreign key (job_id) references public.cutting_jobs(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'service_invoice_lines_sub_fkey') then
    alter table public.service_invoice_lines add constraint service_invoice_lines_sub_fkey
      foreign key (sub_order_id) references public.cutting_sub_orders(id);
  end if;
end $$;

create index if not exists service_invoice_lines_job_idx on public.service_invoice_lines (job_id);

-- ============================================================
--  Jaanch (sirf parhne wali)
--  select column_name from information_schema.columns
--   where table_name = 'service_invoice_lines' and column_name in ('job_id', 'sub_order_id');   -- 2 rows
-- ============================================================
