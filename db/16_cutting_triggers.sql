-- ============================================================
--  16 — Cutting / Processing: Triggers
-- ============================================================

-- ---------- Masters: audit + version + permissions ----------

drop trigger if exists trg_audit_machines   on machines;
drop trigger if exists trg_log_machines     on machines;
drop trigger if exists trg_version_machines on machines;
drop trigger if exists trg_perm_machines    on machines;

create trigger trg_audit_machines   before insert or update           on machines for each row execute function stamp_audit_fields();
create trigger trg_log_machines     after  insert or update or delete on machines for each row execute function log_audit_event();
create trigger trg_version_machines before update                     on machines for each row execute function bump_version();
create trigger trg_perm_machines    before update                     on machines for each row execute function enforce_perm_on_update('cutting_machine_manage','cutting_machine_manage','recycle_bin');

drop trigger if exists trg_audit_operators   on operators;
drop trigger if exists trg_log_operators     on operators;
drop trigger if exists trg_version_operators on operators;
drop trigger if exists trg_perm_operators    on operators;

create trigger trg_audit_operators   before insert or update           on operators for each row execute function stamp_audit_fields();
create trigger trg_log_operators     after  insert or update or delete on operators for each row execute function log_audit_event();
create trigger trg_version_operators before update                     on operators for each row execute function bump_version();
create trigger trg_perm_operators    before update                     on operators for each row execute function enforce_perm_on_update('cutting_operator_manage','cutting_operator_manage','recycle_bin');

drop trigger if exists trg_audit_service_categories   on service_categories;
drop trigger if exists trg_log_service_categories     on service_categories;
drop trigger if exists trg_version_service_categories on service_categories;
drop trigger if exists trg_perm_service_categories    on service_categories;

create trigger trg_audit_service_categories   before insert or update           on service_categories for each row execute function stamp_audit_fields();
create trigger trg_log_service_categories     after  insert or update or delete on service_categories for each row execute function log_audit_event();
create trigger trg_version_service_categories before update                     on service_categories for each row execute function bump_version();
create trigger trg_perm_service_categories    before update                     on service_categories for each row execute function enforce_perm_on_update('cutting_service_category_manage','cutting_service_category_manage','recycle_bin');

-- ---------- Material Inward ----------

drop trigger if exists trg_no_material_inwards      on material_inwards;
drop trigger if exists trg_audit_material_inwards   on material_inwards;
drop trigger if exists trg_log_material_inwards     on material_inwards;
drop trigger if exists trg_version_material_inwards on material_inwards;
drop trigger if exists trg_perm_material_inwards    on material_inwards;

create trigger trg_no_material_inwards      before insert                     on material_inwards for each row execute function assign_cutting_number('ino');
create trigger trg_audit_material_inwards   before insert or update           on material_inwards for each row execute function stamp_audit_fields();
create trigger trg_log_material_inwards     after  insert or update or delete on material_inwards for each row execute function log_audit_event();
create trigger trg_version_material_inwards before update                     on material_inwards for each row execute function bump_version();
create trigger trg_perm_material_inwards    before update                     on material_inwards for each row execute function enforce_perm_on_update('cutting_inward_edit','cutting_inward_cancel','recycle_bin');

-- ---------- Coils ----------

drop trigger if exists trg_serial_coils  on coils;
drop trigger if exists trg_audit_coils   on coils;
drop trigger if exists trg_log_coils     on coils;
drop trigger if exists trg_version_coils on coils;
drop trigger if exists trg_perm_coils    on coils;

create trigger trg_serial_coils  before insert                     on coils for each row execute function assign_coil_serial();
create trigger trg_audit_coils   before insert or update           on coils for each row execute function stamp_audit_fields();
create trigger trg_log_coils     after  insert or update or delete on coils for each row execute function log_audit_event();
create trigger trg_version_coils before update                     on coils for each row execute function bump_version();
create trigger trg_perm_coils    before update                     on coils for each row execute function enforce_perm_on_update('cutting_coil_adjust','cutting_coil_adjust','recycle_bin');

-- ---------- Cutting Jobs ----------

drop trigger if exists trg_no_cutting_jobs      on cutting_jobs;
drop trigger if exists trg_audit_cutting_jobs   on cutting_jobs;
drop trigger if exists trg_log_cutting_jobs     on cutting_jobs;
drop trigger if exists trg_version_cutting_jobs on cutting_jobs;
drop trigger if exists trg_perm_cutting_jobs    on cutting_jobs;
drop trigger if exists trg_recalc_job_coils     on cutting_jobs;
drop trigger if exists trg_job_complete_perm    on cutting_jobs;

create trigger trg_no_cutting_jobs      before insert                     on cutting_jobs for each row execute function assign_cutting_number('jno');
create trigger trg_job_complete_perm    before insert or update           on cutting_jobs for each row execute function trg_check_job_complete();
create trigger trg_audit_cutting_jobs   before insert or update           on cutting_jobs for each row execute function stamp_audit_fields();
create trigger trg_log_cutting_jobs     after  insert or update or delete on cutting_jobs for each row execute function log_audit_event();
create trigger trg_version_cutting_jobs before update                     on cutting_jobs for each row execute function bump_version();
create trigger trg_perm_cutting_jobs    before update                     on cutting_jobs for each row execute function enforce_perm_on_update('cutting_job_edit','cutting_job_cancel','recycle_bin');
-- job cancel/restore hone par us ki tamam coils ka balance dobara gino
create trigger trg_recalc_job_coils     after  update                     on cutting_jobs for each row execute function trg_recalc_coils_from_header('cutting_job_inputs','job_id');

-- ---------- Cutting Job inputs (raw maal coil se nikalna) ----------

drop trigger if exists trg_coil_usable_job_input on cutting_job_inputs;
drop trigger if exists trg_same_party_job_input  on cutting_job_inputs;
drop trigger if exists trg_recalc_job_input      on cutting_job_inputs;

create trigger trg_coil_usable_job_input before insert or update           on cutting_job_inputs for each row execute function trg_check_coil_usable();
create trigger trg_same_party_job_input  before insert or update           on cutting_job_inputs for each row execute function trg_check_same_party('cutting_jobs','job_id');
create trigger trg_recalc_job_input      after  insert or update or delete on cutting_job_inputs for each row execute function trg_recalc_coil_from_line();

-- ---------- Cutting Job outputs (cutting sizes) ----------

drop trigger if exists trg_output_coil_check on cutting_job_outputs;
drop trigger if exists trg_recalc_job_output on cutting_job_outputs;

create trigger trg_output_coil_check before insert or update           on cutting_job_outputs for each row execute function trg_check_output_coil();
create trigger trg_recalc_job_output after  insert or update or delete on cutting_job_outputs for each row execute function trg_recalc_coil_from_line();

-- ---------- Delivery Challans ----------

drop trigger if exists trg_no_delivery_challans      on delivery_challans;
drop trigger if exists trg_audit_delivery_challans   on delivery_challans;
drop trigger if exists trg_log_delivery_challans     on delivery_challans;
drop trigger if exists trg_version_delivery_challans on delivery_challans;
drop trigger if exists trg_perm_delivery_challans    on delivery_challans;
drop trigger if exists trg_recalc_challan_coils      on delivery_challans;

create trigger trg_no_delivery_challans      before insert                     on delivery_challans for each row execute function assign_cutting_number('dno');
create trigger trg_audit_delivery_challans   before insert or update           on delivery_challans for each row execute function stamp_audit_fields();
create trigger trg_log_delivery_challans     after  insert or update or delete on delivery_challans for each row execute function log_audit_event();
create trigger trg_version_delivery_challans before update                     on delivery_challans for each row execute function bump_version();
create trigger trg_perm_delivery_challans    before update                     on delivery_challans for each row execute function enforce_perm_on_update('cutting_challan_edit','cutting_challan_cancel','recycle_bin');
create trigger trg_recalc_challan_coils      after  update                     on delivery_challans for each row execute function trg_recalc_coils_from_header('delivery_challan_lines','challan_id');

drop trigger if exists trg_same_party_challan_line on delivery_challan_lines;
drop trigger if exists trg_delivery_available      on delivery_challan_lines;
drop trigger if exists trg_recalc_challan_line     on delivery_challan_lines;

create trigger trg_same_party_challan_line before insert or update           on delivery_challan_lines for each row execute function trg_check_same_party('delivery_challans','challan_id');
create trigger trg_delivery_available      before insert or update           on delivery_challan_lines for each row execute function trg_check_delivery_available();
create trigger trg_recalc_challan_line     after  insert or update or delete on delivery_challan_lines for each row execute function trg_recalc_coil_from_line();

-- ---------- Material Returns ----------

drop trigger if exists trg_no_material_returns      on material_returns;
drop trigger if exists trg_audit_material_returns   on material_returns;
drop trigger if exists trg_log_material_returns     on material_returns;
drop trigger if exists trg_version_material_returns on material_returns;
drop trigger if exists trg_perm_material_returns    on material_returns;
drop trigger if exists trg_recalc_return_coils      on material_returns;

create trigger trg_no_material_returns      before insert                     on material_returns for each row execute function assign_cutting_number('rno');
create trigger trg_audit_material_returns   before insert or update           on material_returns for each row execute function stamp_audit_fields();
create trigger trg_log_material_returns     after  insert or update or delete on material_returns for each row execute function log_audit_event();
create trigger trg_version_material_returns before update                     on material_returns for each row execute function bump_version();
create trigger trg_perm_material_returns    before update                     on material_returns for each row execute function enforce_perm_on_update('cutting_return_create','cutting_return_cancel','recycle_bin');
create trigger trg_recalc_return_coils      after  update                     on material_returns for each row execute function trg_recalc_coils_from_header('material_return_lines','return_id');

drop trigger if exists trg_coil_usable_return_line on material_return_lines;
drop trigger if exists trg_same_party_return_line  on material_return_lines;
drop trigger if exists trg_recalc_return_line      on material_return_lines;

create trigger trg_coil_usable_return_line before insert or update           on material_return_lines for each row execute function trg_check_coil_usable();
create trigger trg_same_party_return_line  before insert or update           on material_return_lines for each row execute function trg_check_same_party('material_returns','return_id');
create trigger trg_recalc_return_line      after  insert or update or delete on material_return_lines for each row execute function trg_recalc_coil_from_line();

-- ---------- Service Invoices ----------

drop trigger if exists trg_no_service_invoices      on service_invoices;
drop trigger if exists trg_audit_service_invoices   on service_invoices;
drop trigger if exists trg_log_service_invoices     on service_invoices;
drop trigger if exists trg_version_service_invoices on service_invoices;
drop trigger if exists trg_perm_service_invoices    on service_invoices;
drop trigger if exists trg_totals_service_invoices  on service_invoices;

create trigger trg_no_service_invoices      before insert                     on service_invoices for each row execute function assign_cutting_number('sino');
create trigger trg_audit_service_invoices   before insert or update           on service_invoices for each row execute function stamp_audit_fields();
create trigger trg_log_service_invoices     after  insert or update or delete on service_invoices for each row execute function log_audit_event();
create trigger trg_version_service_invoices before update                     on service_invoices for each row execute function bump_version();
create trigger trg_perm_service_invoices    before update                     on service_invoices for each row execute function enforce_perm_on_update('service_invoice_edit','service_invoice_cancel','recycle_bin');
create trigger trg_totals_service_invoices  after  update                     on service_invoices for each row execute function trg_service_invoice_header_totals();

drop trigger if exists trg_amount_service_lines on service_invoice_lines;
drop trigger if exists trg_totals_service_lines on service_invoice_lines;

create trigger trg_amount_service_lines before insert or update           on service_invoice_lines for each row execute function trg_service_line_amount();
create trigger trg_totals_service_lines after  insert or update or delete on service_invoice_lines for each row execute function trg_service_invoice_totals();

drop trigger if exists trg_job_not_billed on service_invoice_jobs;
create trigger trg_job_not_billed before insert or update on service_invoice_jobs for each row execute function trg_check_job_not_billed();
