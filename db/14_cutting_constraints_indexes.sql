-- ============================================================
--  14 — Cutting / Processing: Constraints & Indexes
-- ============================================================

-- ---------- Primary keys ----------

alter table cutting_settings         add constraint cutting_settings_pkey         primary key (id);
alter table machines                 add constraint machines_pkey                 primary key (id);
alter table operators                add constraint operators_pkey                primary key (id);
alter table service_categories       add constraint service_categories_pkey       primary key (id);
alter table material_inwards         add constraint material_inwards_pkey         primary key (id);
alter table coils                    add constraint coils_pkey                    primary key (id);
alter table cutting_jobs             add constraint cutting_jobs_pkey             primary key (id);
alter table cutting_job_inputs       add constraint cutting_job_inputs_pkey       primary key (id);
alter table cutting_job_outputs      add constraint cutting_job_outputs_pkey      primary key (id);
alter table delivery_challans        add constraint delivery_challans_pkey        primary key (id);
alter table delivery_challan_lines   add constraint delivery_challan_lines_pkey   primary key (id);
alter table material_returns         add constraint material_returns_pkey         primary key (id);
alter table material_return_lines    add constraint material_return_lines_pkey    primary key (id);
alter table service_invoices         add constraint service_invoices_pkey         primary key (id);
alter table service_invoice_lines    add constraint service_invoice_lines_pkey    primary key (id);
alter table service_invoice_jobs     add constraint service_invoice_jobs_pkey     primary key (id);
alter table service_invoice_challans add constraint service_invoice_challans_pkey primary key (id);

-- ---------- Settings: hamesha aik hi row ----------

alter table cutting_settings add constraint cutting_settings_id_check check (id = 1);
alter table cutting_settings add constraint cutting_settings_threshold_nonneg
  check (coil_finish_threshold_kg >= 0);

-- ============================================================
--  OWNERSHIP RULE — sab se ahem constraint
--
--  Party ka maal aur company ka apna maal kabhi mix nahi ho sakte.
--  Yeh sirf UI ka wada nahi — database khud rok deta hai.
-- ============================================================

alter table coils add constraint coils_ownership_check
  check (ownership in ('party', 'own'));

alter table coils add constraint coils_ownership_fields_check
  check (
    (ownership = 'party' and party_id is not null and item_id is null)
    or
    (ownership = 'own'   and item_id  is not null and party_id is null)
  );

-- ---------- Coil balance kabhi minus nahi ho sakta ----------
-- Do users ek saath ek hi coil se maal nikalne ki koshish karein to
-- doosra transaction yahin fail ho jayega — over-consumption namumkin.

alter table coils add constraint coils_raw_balance_nonneg
  check (received_weight - consumed_weight - returned_weight - closing_adjust_weight >= 0);

alter table coils add constraint coils_pending_delivery_nonneg
  check (finished_weight - delivered_weight >= 0);

alter table coils add constraint coils_weights_nonneg
  check (received_weight >= 0 and consumed_weight >= 0 and returned_weight >= 0
     and closing_adjust_weight >= 0 and finished_weight >= 0 and delivered_weight >= 0);

alter table coils add constraint coils_status_check
  check (status in ('active', 'closed', 'cancelled'));

alter table coils add constraint coils_serial_required
  check (coil_serial is not null and trim(both from coil_serial) <> '');

-- ---------- Status / method value checks ----------

alter table material_inwards   add constraint material_inwards_status_check   check (status in ('active','cancelled'));
alter table delivery_challans  add constraint delivery_challans_status_check  check (status in ('active','cancelled'));
alter table material_returns   add constraint material_returns_status_check   check (status in ('active','cancelled'));
alter table service_invoices   add constraint service_invoices_status_check   check (status in ('active','cancelled'));
alter table cutting_jobs       add constraint cutting_jobs_status_check       check (status in ('draft','completed','cancelled'));

alter table service_invoice_lines add constraint service_invoice_lines_method_check
  check (calc_method in ('kg','ton','piece','meter','foot','cut','fixed'));

alter table service_categories add constraint service_categories_method_check
  check (default_calc_method in ('kg','ton','piece','meter','foot','cut','fixed'));

-- ---------- Weight / amount sanity ----------

alter table cutting_job_inputs     add constraint cutting_job_inputs_weight_pos     check (input_weight > 0);
alter table cutting_job_outputs    add constraint cutting_job_outputs_weight_nonneg check (output_weight >= 0 and pieces >= 0);
alter table material_return_lines  add constraint material_return_lines_weight_pos  check (return_weight > 0);
alter table delivery_challan_lines add constraint delivery_challan_lines_nonneg     check (delivered_weight >= 0 and expected_weight >= 0);
alter table service_invoice_lines  add constraint service_invoice_lines_nonneg      check (qty >= 0 and rate >= 0);

alter table machines           add constraint machines_name_required           check (trim(both from name) <> '');
alter table operators          add constraint operators_name_required          check (trim(both from name) <> '');
alter table service_categories add constraint service_categories_name_required check (trim(both from name) <> '');

-- ---------- Foreign keys ----------

alter table cutting_settings add constraint cutting_settings_updated_by_fkey foreign key (updated_by) references app_users(id);

alter table machines add constraint machines_created_by_fkey foreign key (created_by) references app_users(id);
alter table machines add constraint machines_updated_by_fkey foreign key (updated_by) references app_users(id);

alter table operators add constraint operators_created_by_fkey foreign key (created_by) references app_users(id);
alter table operators add constraint operators_updated_by_fkey foreign key (updated_by) references app_users(id);

alter table service_categories add constraint service_categories_created_by_fkey foreign key (created_by) references app_users(id);
alter table service_categories add constraint service_categories_updated_by_fkey foreign key (updated_by) references app_users(id);

alter table material_inwards add constraint material_inwards_party_fkey      foreign key (party_id)     references parties(id);
alter table material_inwards add constraint material_inwards_warehouse_fkey  foreign key (warehouse_id) references warehouses(id);
alter table material_inwards add constraint material_inwards_created_by_fkey foreign key (created_by)   references app_users(id);
alter table material_inwards add constraint material_inwards_updated_by_fkey foreign key (updated_by)   references app_users(id);

alter table coils add constraint coils_party_fkey      foreign key (party_id)     references parties(id);
alter table coils add constraint coils_item_fkey       foreign key (item_id)      references items(id);
alter table coils add constraint coils_inward_fkey     foreign key (inward_id)    references material_inwards(id);
alter table coils add constraint coils_warehouse_fkey  foreign key (warehouse_id) references warehouses(id);
alter table coils add constraint coils_closed_by_fkey  foreign key (closed_by)    references app_users(id);
alter table coils add constraint coils_created_by_fkey foreign key (created_by)   references app_users(id);
alter table coils add constraint coils_updated_by_fkey foreign key (updated_by)   references app_users(id);

alter table cutting_jobs add constraint cutting_jobs_party_fkey        foreign key (party_id)     references parties(id);
alter table cutting_jobs add constraint cutting_jobs_warehouse_fkey    foreign key (warehouse_id) references warehouses(id);
alter table cutting_jobs add constraint cutting_jobs_machine_fkey      foreign key (machine_id)   references machines(id);
alter table cutting_jobs add constraint cutting_jobs_operator_fkey     foreign key (operator_id)  references operators(id);
alter table cutting_jobs add constraint cutting_jobs_completed_by_fkey foreign key (completed_by) references app_users(id);
alter table cutting_jobs add constraint cutting_jobs_created_by_fkey   foreign key (created_by)   references app_users(id);
alter table cutting_jobs add constraint cutting_jobs_updated_by_fkey   foreign key (updated_by)   references app_users(id);

alter table cutting_job_inputs add constraint cutting_job_inputs_job_fkey
  foreign key (job_id) references cutting_jobs(id) on delete cascade;
alter table cutting_job_inputs add constraint cutting_job_inputs_coil_fkey foreign key (coil_id) references coils(id);

alter table cutting_job_outputs add constraint cutting_job_outputs_job_fkey
  foreign key (job_id) references cutting_jobs(id) on delete cascade;
alter table cutting_job_outputs add constraint cutting_job_outputs_coil_fkey foreign key (coil_id) references coils(id);

alter table delivery_challans add constraint delivery_challans_party_fkey      foreign key (party_id)     references parties(id);
alter table delivery_challans add constraint delivery_challans_warehouse_fkey  foreign key (warehouse_id) references warehouses(id);
alter table delivery_challans add constraint delivery_challans_created_by_fkey foreign key (created_by)   references app_users(id);
alter table delivery_challans add constraint delivery_challans_updated_by_fkey foreign key (updated_by)   references app_users(id);

alter table delivery_challan_lines add constraint delivery_challan_lines_challan_fkey
  foreign key (challan_id) references delivery_challans(id) on delete cascade;
alter table delivery_challan_lines add constraint delivery_challan_lines_job_fkey    foreign key (job_id)    references cutting_jobs(id);
alter table delivery_challan_lines add constraint delivery_challan_lines_coil_fkey   foreign key (coil_id)   references coils(id);
alter table delivery_challan_lines add constraint delivery_challan_lines_output_fkey foreign key (output_id) references cutting_job_outputs(id);

alter table material_returns add constraint material_returns_party_fkey      foreign key (party_id)     references parties(id);
alter table material_returns add constraint material_returns_warehouse_fkey  foreign key (warehouse_id) references warehouses(id);
alter table material_returns add constraint material_returns_created_by_fkey foreign key (created_by)   references app_users(id);
alter table material_returns add constraint material_returns_updated_by_fkey foreign key (updated_by)   references app_users(id);

alter table material_return_lines add constraint material_return_lines_return_fkey
  foreign key (return_id) references material_returns(id) on delete cascade;
alter table material_return_lines add constraint material_return_lines_coil_fkey foreign key (coil_id) references coils(id);

alter table service_invoices add constraint service_invoices_party_fkey      foreign key (party_id)   references parties(id);
alter table service_invoices add constraint service_invoices_company_fkey    foreign key (company_id) references companies(id);
alter table service_invoices add constraint service_invoices_created_by_fkey foreign key (created_by) references app_users(id);
alter table service_invoices add constraint service_invoices_updated_by_fkey foreign key (updated_by) references app_users(id);

alter table service_invoice_lines add constraint service_invoice_lines_invoice_fkey
  foreign key (invoice_id) references service_invoices(id) on delete cascade;
alter table service_invoice_lines add constraint service_invoice_lines_category_fkey
  foreign key (service_category_id) references service_categories(id);

alter table service_invoice_jobs add constraint service_invoice_jobs_invoice_fkey
  foreign key (invoice_id) references service_invoices(id) on delete cascade;
alter table service_invoice_jobs add constraint service_invoice_jobs_job_fkey foreign key (job_id) references cutting_jobs(id);

alter table service_invoice_challans add constraint service_invoice_challans_invoice_fkey
  foreign key (invoice_id) references service_invoices(id) on delete cascade;
alter table service_invoice_challans add constraint service_invoice_challans_challan_fkey
  foreign key (challan_id) references delivery_challans(id);

-- ---------- Unique indexes: numbers kabhi na dohrayein ----------

create unique index if not exists coils_serial_uniq
  on coils (lower(trim(both from coil_serial)));

create unique index if not exists material_inwards_no_uniq
  on material_inwards (lower(trim(both from ino))) where ino is not null and trim(both from ino) <> '';

create unique index if not exists cutting_jobs_no_uniq
  on cutting_jobs (lower(trim(both from jno))) where jno is not null and trim(both from jno) <> '';

create unique index if not exists delivery_challans_no_uniq
  on delivery_challans (lower(trim(both from dno))) where dno is not null and trim(both from dno) <> '';

create unique index if not exists material_returns_no_uniq
  on material_returns (lower(trim(both from rno))) where rno is not null and trim(both from rno) <> '';

create unique index if not exists service_invoices_no_uniq
  on service_invoices (lower(trim(both from sino))) where sino is not null and trim(both from sino) <> '';

-- Ek job sirf ek hi zinda invoice par bill ho sakta hai
create unique index if not exists service_invoice_jobs_job_uniq on service_invoice_jobs (job_id);
create unique index if not exists service_invoice_challans_uniq on service_invoice_challans (invoice_id, challan_id);

-- Masters ke naam unique
create unique index if not exists machines_name_uniq           on machines           (lower(trim(both from name))) where deleted_at is null;
create unique index if not exists operators_name_uniq          on operators          (lower(trim(both from name))) where deleted_at is null;
create unique index if not exists service_categories_name_uniq on service_categories (lower(trim(both from name))) where deleted_at is null;

-- ---------- Performance indexes ----------

create index if not exists coils_party_idx      on coils (party_id);
create index if not exists coils_item_idx       on coils (item_id);
create index if not exists coils_warehouse_idx  on coils (warehouse_id);
create index if not exists coils_inward_idx     on coils (inward_id);
create index if not exists coils_ownership_idx  on coils (ownership, status);
create index if not exists coils_active_idx     on coils (party_id, status) where deleted_at is null and ownership = 'party';
create index if not exists coils_received_idx   on coils (received_date desc);

create index if not exists material_inwards_party_idx on material_inwards (party_id);
create index if not exists material_inwards_date_idx  on material_inwards (idate desc);

create index if not exists cutting_jobs_party_idx  on cutting_jobs (party_id);
create index if not exists cutting_jobs_date_idx   on cutting_jobs (jdate desc);
create index if not exists cutting_jobs_status_idx on cutting_jobs (status) where deleted_at is null;

create index if not exists cutting_job_inputs_job_idx   on cutting_job_inputs  (job_id);
create index if not exists cutting_job_inputs_coil_idx  on cutting_job_inputs  (coil_id);
create index if not exists cutting_job_outputs_job_idx  on cutting_job_outputs (job_id);
create index if not exists cutting_job_outputs_coil_idx on cutting_job_outputs (coil_id);

create index if not exists delivery_challans_party_idx  on delivery_challans (party_id);
create index if not exists delivery_challans_date_idx   on delivery_challans (ddate desc);
create index if not exists delivery_challan_lines_ch_idx   on delivery_challan_lines (challan_id);
create index if not exists delivery_challan_lines_coil_idx on delivery_challan_lines (coil_id);
create index if not exists delivery_challan_lines_job_idx  on delivery_challan_lines (job_id);

create index if not exists material_returns_party_idx    on material_returns (party_id);
create index if not exists material_returns_date_idx     on material_returns (rdate desc);
create index if not exists material_return_lines_ret_idx on material_return_lines (return_id);
create index if not exists material_return_lines_coil_idx on material_return_lines (coil_id);

create index if not exists service_invoices_party_idx on service_invoices (party_id);
create index if not exists service_invoices_date_idx  on service_invoices (sidate desc);
create index if not exists service_invoice_lines_inv_idx on service_invoice_lines (invoice_id);
create index if not exists service_invoice_lines_cat_idx on service_invoice_lines (service_category_id);
create index if not exists service_invoice_jobs_inv_idx  on service_invoice_jobs (invoice_id);

create index if not exists items_item_form_idx on items (item_form) where deleted_at is null;
