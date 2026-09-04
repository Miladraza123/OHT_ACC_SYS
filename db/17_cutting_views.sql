-- ============================================================
--  17 — Cutting / Processing: Views (ledgers & reports)
--
--  Ledger views hain, tables nahi — is liye kabhi balance se
--  bahar nahi ja sakte. Jo asal documents mein hai, wohi ledger
--  mein dikhta hai.
-- ============================================================

-- ---------- Coil Ledger (requirement 37) ----------
-- Har coil ki poori operational history ek jagah.

create or replace view coil_ledger_v as
  -- 1. Maal aaya
  select c.id                        as coil_id,
         c.coil_serial,
         c.party_id,
         c.received_date             as entry_date,
         1                           as sort_order,
         'inward'                    as entry_type,
         mi.ino                      as doc_no,
         mi.id                       as doc_id,
         'material_inwards'          as doc_table,
         c.received_weight           as in_kg,
         0::numeric                  as out_kg,
         null::uuid                  as job_id,
         c.remarks                   as remarks
    from coils c
    left join material_inwards mi on mi.id = c.inward_id
   where c.deleted_at is null

  union all
  -- 2. Cutting job mein raw maal gaya
  select i.coil_id, c.coil_serial, c.party_id, j.jdate, 2,
         'job_input', j.jno, j.id, 'cutting_jobs',
         0::numeric, i.input_weight, j.id, j.remarks
    from cutting_job_inputs i
    join cutting_jobs j on j.id = i.job_id
    join coils c on c.id = i.coil_id
   where j.deleted_at is null and j.status <> 'cancelled'

  union all
  -- 3. Job se maal bana (delivery ke liye tayyar)
  select o.coil_id, c.coil_serial, c.party_id, j.jdate, 3,
         'job_output', j.jno, j.id, 'cutting_jobs',
         o.output_weight, 0::numeric, j.id,
         coalesce(o.width_mm::text || ' mm x ' || o.pieces::text || ' pcs', o.remarks)
    from cutting_job_outputs o
    join cutting_jobs j on j.id = o.job_id
    join coils c on c.id = o.coil_id
   where j.deleted_at is null and j.status <> 'cancelled'

  union all
  -- 4. Delivery challan se maal gaya (ACTUAL tola gaya weight)
  select l.coil_id, c.coil_serial, c.party_id, d.ddate, 4,
         'delivery', d.dno, d.id, 'delivery_challans',
         0::numeric, l.delivered_weight, l.job_id,
         case when l.variance_kg <> 0
              then 'Variance ' || l.variance_kg::text || ' KG'
                   || coalesce(' (' || l.variance_reason || ')', '')
              else l.remarks end
    from delivery_challan_lines l
    join delivery_challans d on d.id = l.challan_id
    join coils c on c.id = l.coil_id
   where d.deleted_at is null and d.status <> 'cancelled'

  union all
  -- 5. Raw maal wapas
  select l.coil_id, c.coil_serial, c.party_id, r.rdate, 5,
         'return', r.rno, r.id, 'material_returns',
         0::numeric, l.return_weight, null::uuid, l.remarks
    from material_return_lines l
    join material_returns r on r.id = l.return_id
    join coils c on c.id = l.coil_id
   where r.deleted_at is null and r.status <> 'cancelled'

  union all
  -- 6. Coil band karte waqt closing adjustment / variance
  select c.id, c.coil_serial, c.party_id, c.closed_at::date, 6,
         'closing_adjustment', c.coil_serial, c.id, 'coils',
         0::numeric, c.closing_adjust_weight, null::uuid,
         coalesce(c.closing_reason, 'other')
         || coalesce(' — ' || c.closing_remarks, '')
    from coils c
   where c.deleted_at is null and c.status = 'closed' and c.closing_adjust_weight <> 0;

-- ---------- Party Coil Stock (requirement 8) ----------

create or replace view party_coil_stock_v as
select c.id                  as coil_id,
       c.coil_serial,
       c.party_id,
       p.name                as party_name,
       c.party_coil_ref,
       c.material_type,
       c.grade,
       c.thickness_mm,
       c.width_mm,
       c.warehouse_id,
       w.name                as warehouse_name,
       c.received_date,
       c.received_weight,
       c.raw_balance,
       c.consumed_weight     as processed_weight,
       c.finished_weight,
       c.pending_delivery    as finished_pending_delivery,
       c.delivered_weight,
       c.returned_weight,
       c.closing_adjust_weight as variance_weight,
       c.status,
       c.closed_at,
       c.closing_reason,
       c.closing_remarks,
       (current_date - c.received_date) as age_days
  from coils c
  join parties p    on p.id = c.party_id
  join warehouses w on w.id = c.warehouse_id
 where c.deleted_at is null
   and c.ownership = 'party'
   and c.status <> 'cancelled';

-- ---------- Party-wise Material Ledger (requirement 38) ----------
-- Yeh QUANTITY ledger hai — party ka financial ledger alag hai.

create or replace view party_material_ledger_v as
select c.party_id,
       p.name                                as party_name,
       count(*)                              as coil_count,
       count(*) filter (where c.status = 'active') as active_coils,
       sum(c.received_weight)                as received_weight,
       sum(c.raw_balance)                    as raw_balance,
       sum(c.consumed_weight)                as processed_weight,
       sum(c.pending_delivery)               as finished_pending_delivery,
       sum(c.delivered_weight)               as delivered_weight,
       sum(c.returned_weight)                as returned_weight,
       sum(c.closing_adjust_weight)          as variance_weight,
       sum(c.raw_balance + c.pending_delivery) as physical_balance
  from coils c
  join parties p on p.id = c.party_id
 where c.deleted_at is null and c.ownership = 'party' and c.status <> 'cancelled'
 group by c.party_id, p.name;

-- ---------- Unbilled Jobs (requirement 26) ----------

create or replace view unbilled_jobs_v as
select j.id            as job_id,
       j.jno,
       j.jdate,
       j.party_id,
       p.name          as party_name,
       j.warehouse_id,
       j.status,
       coalesce((select sum(i.input_weight) from cutting_job_inputs  i where i.job_id = j.id), 0) as input_weight,
       coalesce((select sum(o.output_weight) from cutting_job_outputs o where o.job_id = j.id), 0) as output_weight,
       coalesce((select sum(o.pieces)        from cutting_job_outputs o where o.job_id = j.id), 0) as total_pieces
  from cutting_jobs j
  join parties p on p.id = j.party_id
 where j.deleted_at is null
   and j.status = 'completed'
   and not exists (
     select 1 from service_invoice_jobs sij
      join service_invoices si on si.id = sij.invoice_id
     where sij.job_id = j.id and si.deleted_at is null and si.status <> 'cancelled'
   );

-- ---------- Ready for Delivery (requirement 39) ----------

create or replace view ready_for_delivery_v as
select o.id             as output_id,
       o.job_id,
       j.jno,
       o.coil_id,
       c.coil_serial,
       c.party_id,
       p.name           as party_name,
       c.warehouse_id,
       o.width_mm,
       o.pieces,
       o.output_weight,
       coalesce((select sum(l.delivered_weight)
                   from delivery_challan_lines l
                   join delivery_challans d on d.id = l.challan_id
                  where l.output_id = o.id and d.deleted_at is null and d.status <> 'cancelled'), 0)
         as delivered_weight,
       o.output_weight - coalesce((select sum(l.delivered_weight)
                   from delivery_challan_lines l
                   join delivery_challans d on d.id = l.challan_id
                  where l.output_id = o.id and d.deleted_at is null and d.status <> 'cancelled'), 0)
         as pending_weight
  from cutting_job_outputs o
  join cutting_jobs j on j.id = o.job_id
  join coils c        on c.id = o.coil_id
  join parties p      on p.id = c.party_id
 where j.deleted_at is null and j.status <> 'cancelled' and c.deleted_at is null;

-- ---------- Service Revenue by Category (requirement 30) ----------

create or replace view service_revenue_v as
select si.id            as invoice_id,
       si.sino,
       si.sidate,
       si.party_id,
       p.name           as party_name,
       sl.service_category_id,
       coalesce(sc.name, sl.description, 'Other') as category_name,
       sl.calc_method,
       sl.qty,
       sl.rate,
       sl.amount
  from service_invoice_lines sl
  join service_invoices si on si.id = sl.invoice_id
  join parties p on p.id = si.party_id
  left join service_categories sc on sc.id = sl.service_category_id
 where si.deleted_at is null and si.status <> 'cancelled';

-- ---------- Own Stock: Coil / Sheet / General (requirement 2) ----------
-- Mojooda items table par hi bana hai — koi doosra inventory engine nahi.

create or replace view own_stock_v as
select i.id,
       i.name,
       i.item_form,
       i.unit,
       i.stock_qty,
       i.avg_cost,
       round(i.stock_qty * i.avg_cost, 2) as stock_value,
       i.reorder_level,
       i.active
  from items i
 where i.deleted_at is null;

-- ---------- Weight Variance Report (requirement 39) ----------

create or replace view weight_variance_v as
  select 'delivery'::text as source,
         d.ddate          as vdate,
         d.dno            as doc_no,
         c.coil_serial,
         c.party_id,
         p.name           as party_name,
         l.expected_weight,
         l.delivered_weight as actual_weight,
         l.variance_kg,
         l.variance_reason,
         l.remarks
    from delivery_challan_lines l
    join delivery_challans d on d.id = l.challan_id
    join coils c   on c.id = l.coil_id
    join parties p on p.id = c.party_id
   where d.deleted_at is null and d.status <> 'cancelled' and l.variance_kg <> 0

  union all
  select 'coil_closing',
         c.closed_at::date,
         c.coil_serial,
         c.coil_serial,
         c.party_id,
         p.name,
         c.closing_adjust_weight,
         0::numeric,
         -c.closing_adjust_weight,
         c.closing_reason,
         c.closing_remarks
    from coils c
    join parties p on p.id = c.party_id
   where c.deleted_at is null and c.status = 'closed' and c.closing_adjust_weight <> 0;
