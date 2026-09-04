-- ============================================================
--  07 — Period Lock enforcement & voucher numbering
-- ============================================================

-- ---------- Sequential voucher number: S-0001 / P-0001 ----------

create or replace function public.assign_voucher_number()
returns trigger
language plpgsql
as $function$
begin
  if NEW.vno is null or trim(NEW.vno) = '' then
    if NEW.vtype = 'sale' then
      NEW.vno := 'S-' || lpad(nextval('voucher_sale_seq')::text, 4, '0');
    else
      NEW.vno := 'P-' || lpad(nextval('voucher_purchase_seq')::text, 4, '0');
    end if;
  end if;
  return NEW;
end;
$function$;

-- ---------- Period Lock: vouchers ----------
--  Lock date se pehle ka bill na banaye ja sake, na badla ja sake.
--  Sirf soft-delete / restore (deleted_at badalna) ki ijazat hai.

create or replace function public.check_period_lock_vouchers()
returns trigger
language plpgsql
as $function$
declare
  lock_date  date;
  check_date date;
begin
  select locked_before into lock_date from period_lock where id = 1;
  if lock_date is null then
    return coalesce(NEW, OLD);   -- koi lock set hi nahi — sab normal
  end if;

  check_date := coalesce(NEW.vdate, OLD.vdate);

  if TG_OP = 'UPDATE' and check_date < lock_date then
    if to_jsonb(NEW) - 'deleted_at' - 'updated_at' = to_jsonb(OLD) - 'deleted_at' - 'updated_at' then
      return NEW;   -- sirf soft-delete/restore tha, ijazat hai
    end if;
    raise exception 'Yeh bill % se pehle ka hai, jo band ho chuka hai (locked before %). Change nahi ho sakta.',
      check_date, lock_date;
  end if;

  if TG_OP in ('DELETE', 'INSERT') and check_date < lock_date then
    raise exception 'Yeh tareekh (%) band ho chuki hai (locked before %). Naya bill nahi ban sakta ya permanently delete nahi ho sakta.',
      check_date, lock_date;
  end if;

  return coalesce(NEW, OLD);
end;
$function$;

-- ---------- Period Lock: daily ledger sheets ----------

create or replace function public.check_period_lock_sheets()
returns trigger
language plpgsql
as $function$
declare
  lock_date  date;
  check_date date;
begin
  select locked_before into lock_date from period_lock where id = 1;
  if lock_date is null then
    return coalesce(NEW, OLD);
  end if;

  check_date := coalesce(NEW.sheet_date, OLD.sheet_date);

  if TG_OP = 'UPDATE' and check_date < lock_date then
    if to_jsonb(NEW) - 'deleted_at' - 'version' = to_jsonb(OLD) - 'deleted_at' - 'version' then
      return NEW;
    end if;
    raise exception 'Yeh din (%) band ho chuka hai (locked before %). Change nahi ho sakta.',
      check_date, lock_date;
  end if;

  if TG_OP in ('DELETE', 'INSERT') and check_date < lock_date then
    raise exception 'Yeh tareekh (%) band ho chuki hai (locked before %).',
      check_date, lock_date;
  end if;

  return coalesce(NEW, OLD);
end;
$function$;

-- ---------- Lock date badle to opening balance snapshots saaf kar do ----------

create or replace function public.invalidate_opening_balances()
returns trigger
language plpgsql
as $function$
begin
  delete from party_opening_balances where true;
  return NEW;
end;
$function$;
