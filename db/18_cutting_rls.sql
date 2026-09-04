-- ============================================================
--  18 — Cutting / Processing: Row Level Security
--
--  Wahi usool jo baqi system mein hai: parhna har logged-in user
--  ke liye, likhna sirf permission ke saath. Hard delete sirf admin.
--  Aam users cancel / soft delete karte hain.
-- ============================================================

alter table cutting_settings         enable row level security;
alter table machines                 enable row level security;
alter table operators                enable row level security;
alter table service_categories       enable row level security;
alter table material_inwards         enable row level security;
alter table coils                    enable row level security;
alter table cutting_jobs             enable row level security;
alter table cutting_job_inputs       enable row level security;
alter table cutting_job_outputs      enable row level security;
alter table delivery_challans        enable row level security;
alter table delivery_challan_lines   enable row level security;
alter table material_returns         enable row level security;
alter table material_return_lines    enable row level security;
alter table service_invoices         enable row level security;
alter table service_invoice_lines    enable row level security;
alter table service_invoice_jobs     enable row level security;
alter table service_invoice_challans enable row level security;

-- ---------- Settings ----------
drop policy if exists "cutting_settings select" on cutting_settings;
drop policy if exists "cutting_settings update" on cutting_settings;

create policy "cutting_settings select" on cutting_settings for select using (auth.role() = 'authenticated');
create policy "cutting_settings update" on cutting_settings for update
  using (auth.role() = 'authenticated')
  with check (is_app_admin() or has_perm('cutting_settings_manage'));

-- ---------- Machines ----------
drop policy if exists "machines select" on machines;
drop policy if exists "machines insert" on machines;
drop policy if exists "machines update" on machines;
drop policy if exists "machines delete" on machines;

create policy "machines select" on machines for select using (auth.role() = 'authenticated');
create policy "machines insert" on machines for insert with check (is_app_admin() or has_perm('cutting_machine_manage'));
create policy "machines update" on machines for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "machines delete" on machines for delete using (is_app_admin());

-- ---------- Operators ----------
drop policy if exists "operators select" on operators;
drop policy if exists "operators insert" on operators;
drop policy if exists "operators update" on operators;
drop policy if exists "operators delete" on operators;

create policy "operators select" on operators for select using (auth.role() = 'authenticated');
create policy "operators insert" on operators for insert with check (is_app_admin() or has_perm('cutting_operator_manage'));
create policy "operators update" on operators for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "operators delete" on operators for delete using (is_app_admin());

-- ---------- Service Categories ----------
drop policy if exists "service_categories select" on service_categories;
drop policy if exists "service_categories insert" on service_categories;
drop policy if exists "service_categories update" on service_categories;
drop policy if exists "service_categories delete" on service_categories;

create policy "service_categories select" on service_categories for select using (auth.role() = 'authenticated');
create policy "service_categories insert" on service_categories for insert with check (is_app_admin() or has_perm('cutting_service_category_manage'));
create policy "service_categories update" on service_categories for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "service_categories delete" on service_categories for delete using (is_app_admin());

-- ---------- Material Inward ----------
drop policy if exists "material_inwards select" on material_inwards;
drop policy if exists "material_inwards insert" on material_inwards;
drop policy if exists "material_inwards update" on material_inwards;
drop policy if exists "material_inwards delete" on material_inwards;

create policy "material_inwards select" on material_inwards for select
  using (is_app_admin() or has_perm('cutting_inward_view') or has_perm('cutting_stock_view'));
create policy "material_inwards insert" on material_inwards for insert with check (is_app_admin() or has_perm('cutting_inward_create'));
create policy "material_inwards update" on material_inwards for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "material_inwards delete" on material_inwards for delete using (is_app_admin());

-- ---------- Coils ----------
drop policy if exists "coils select" on coils;
drop policy if exists "coils insert" on coils;
drop policy if exists "coils update" on coils;
drop policy if exists "coils delete" on coils;

create policy "coils select" on coils for select
  using (is_app_admin() or has_perm('cutting_stock_view') or has_perm('cutting_inward_view')
         or has_perm('reports_view'));
-- Party ki coil Material Inward se banti hai; company ki apni coil
-- Own Stock se. Is liye dono ki ijazat alag hai.
create policy "coils insert" on coils for insert with check (
  (ownership = 'party' and (is_app_admin() or has_perm('cutting_inward_create')))
  or
  (ownership = 'own'   and (is_app_admin() or has_perm('masters_edit')))
);
create policy "coils update" on coils for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "coils delete" on coils for delete using (is_app_admin());

-- ---------- Cutting Jobs ----------
drop policy if exists "cutting_jobs select" on cutting_jobs;
drop policy if exists "cutting_jobs insert" on cutting_jobs;
drop policy if exists "cutting_jobs update" on cutting_jobs;
drop policy if exists "cutting_jobs delete" on cutting_jobs;

create policy "cutting_jobs select" on cutting_jobs for select
  using (is_app_admin() or has_perm('cutting_job_view') or has_perm('service_invoice_view'));
create policy "cutting_jobs insert" on cutting_jobs for insert with check (is_app_admin() or has_perm('cutting_job_create'));
create policy "cutting_jobs update" on cutting_jobs for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "cutting_jobs delete" on cutting_jobs for delete using (is_app_admin());

drop policy if exists "cutting_job_inputs select" on cutting_job_inputs;
drop policy if exists "cutting_job_inputs write"  on cutting_job_inputs;

create policy "cutting_job_inputs select" on cutting_job_inputs for select
  using (is_app_admin() or has_perm('cutting_job_view') or has_perm('service_invoice_view'));
create policy "cutting_job_inputs write" on cutting_job_inputs for all
  using (is_app_admin() or has_perm('cutting_job_create') or has_perm('cutting_job_edit'))
  with check (is_app_admin() or has_perm('cutting_job_create') or has_perm('cutting_job_edit'));

drop policy if exists "cutting_job_outputs select" on cutting_job_outputs;
drop policy if exists "cutting_job_outputs write"  on cutting_job_outputs;

create policy "cutting_job_outputs select" on cutting_job_outputs for select
  using (is_app_admin() or has_perm('cutting_job_view') or has_perm('service_invoice_view')
         or has_perm('cutting_challan_view'));
create policy "cutting_job_outputs write" on cutting_job_outputs for all
  using (is_app_admin() or has_perm('cutting_job_create') or has_perm('cutting_job_edit'))
  with check (is_app_admin() or has_perm('cutting_job_create') or has_perm('cutting_job_edit'));

-- ---------- Delivery Challans ----------
drop policy if exists "delivery_challans select" on delivery_challans;
drop policy if exists "delivery_challans insert" on delivery_challans;
drop policy if exists "delivery_challans update" on delivery_challans;
drop policy if exists "delivery_challans delete" on delivery_challans;

create policy "delivery_challans select" on delivery_challans for select
  using (is_app_admin() or has_perm('cutting_challan_view') or has_perm('service_invoice_view'));
create policy "delivery_challans insert" on delivery_challans for insert with check (is_app_admin() or has_perm('cutting_challan_create'));
create policy "delivery_challans update" on delivery_challans for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "delivery_challans delete" on delivery_challans for delete using (is_app_admin());

drop policy if exists "delivery_challan_lines select" on delivery_challan_lines;
drop policy if exists "delivery_challan_lines write"  on delivery_challan_lines;

create policy "delivery_challan_lines select" on delivery_challan_lines for select
  using (is_app_admin() or has_perm('cutting_challan_view') or has_perm('service_invoice_view'));
create policy "delivery_challan_lines write" on delivery_challan_lines for all
  using (is_app_admin() or has_perm('cutting_challan_create') or has_perm('cutting_challan_edit'))
  with check (is_app_admin() or has_perm('cutting_challan_create') or has_perm('cutting_challan_edit'));

-- ---------- Material Returns ----------
drop policy if exists "material_returns select" on material_returns;
drop policy if exists "material_returns insert" on material_returns;
drop policy if exists "material_returns update" on material_returns;
drop policy if exists "material_returns delete" on material_returns;

create policy "material_returns select" on material_returns for select
  using (is_app_admin() or has_perm('cutting_return_view') or has_perm('cutting_stock_view'));
create policy "material_returns insert" on material_returns for insert with check (is_app_admin() or has_perm('cutting_return_create'));
create policy "material_returns update" on material_returns for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "material_returns delete" on material_returns for delete using (is_app_admin());

drop policy if exists "material_return_lines select" on material_return_lines;
drop policy if exists "material_return_lines write"  on material_return_lines;

create policy "material_return_lines select" on material_return_lines for select
  using (is_app_admin() or has_perm('cutting_return_view') or has_perm('cutting_stock_view'));
create policy "material_return_lines write" on material_return_lines for all
  using (is_app_admin() or has_perm('cutting_return_create'))
  with check (is_app_admin() or has_perm('cutting_return_create'));

-- ---------- Service Invoices ----------
drop policy if exists "service_invoices select" on service_invoices;
drop policy if exists "service_invoices insert" on service_invoices;
drop policy if exists "service_invoices update" on service_invoices;
drop policy if exists "service_invoices delete" on service_invoices;

-- reports_view bhi de rakha hai kyunki party ka financial balance
-- aur P&L in invoices ke baghair adhoore rehte hain
create policy "service_invoices select" on service_invoices for select
  using (is_app_admin() or has_perm('service_invoice_view') or has_perm('reports_view'));
create policy "service_invoices insert" on service_invoices for insert with check (is_app_admin() or has_perm('service_invoice_create'));
create policy "service_invoices update" on service_invoices for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "service_invoices delete" on service_invoices for delete using (is_app_admin());

drop policy if exists "service_invoice_lines select" on service_invoice_lines;
drop policy if exists "service_invoice_lines write"  on service_invoice_lines;

create policy "service_invoice_lines select" on service_invoice_lines for select
  using (is_app_admin() or has_perm('service_invoice_view') or has_perm('reports_view'));
create policy "service_invoice_lines write" on service_invoice_lines for all
  using (is_app_admin() or has_perm('service_invoice_create') or has_perm('service_invoice_edit'))
  with check (is_app_admin() or has_perm('service_invoice_create') or has_perm('service_invoice_edit'));

drop policy if exists "service_invoice_jobs select" on service_invoice_jobs;
drop policy if exists "service_invoice_jobs write"  on service_invoice_jobs;

create policy "service_invoice_jobs select" on service_invoice_jobs for select
  using (is_app_admin() or has_perm('service_invoice_view') or has_perm('cutting_job_view'));
create policy "service_invoice_jobs write" on service_invoice_jobs for all
  using (is_app_admin() or has_perm('service_invoice_create') or has_perm('service_invoice_edit'))
  with check (is_app_admin() or has_perm('service_invoice_create') or has_perm('service_invoice_edit'));

drop policy if exists "service_invoice_challans select" on service_invoice_challans;
drop policy if exists "service_invoice_challans write"  on service_invoice_challans;

create policy "service_invoice_challans select" on service_invoice_challans for select
  using (is_app_admin() or has_perm('service_invoice_view') or has_perm('cutting_challan_view'));
create policy "service_invoice_challans write" on service_invoice_challans for all
  using (is_app_admin() or has_perm('service_invoice_create') or has_perm('service_invoice_edit'))
  with check (is_app_admin() or has_perm('service_invoice_create') or has_perm('service_invoice_edit'));

-- ---------- Views ko RLS ke sath chalane ke liye ----------
-- security_invoker = views underlying tables ki RLS ke tehat chalti hain,
-- view banane wale ke haq par nahi. (Postgres 15+ / Supabase)

alter view coil_ledger_v            set (security_invoker = on);
alter view party_coil_stock_v       set (security_invoker = on);
alter view party_material_ledger_v  set (security_invoker = on);
alter view unbilled_jobs_v          set (security_invoker = on);
alter view ready_for_delivery_v     set (security_invoker = on);
alter view service_revenue_v        set (security_invoker = on);
alter view own_stock_v              set (security_invoker = on);
alter view weight_variance_v        set (security_invoker = on);
