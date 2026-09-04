-- ============================================================
--  25 — App Settings (Company Setup)
--
--  Poore system ki wo settings jo kisi ek module ki nahi:
--  currency, financial year, aur sale/purchase ke voucher prefixes.
--  (Cutting module ke apne prefixes cutting_settings mein hain.)
--
--  Hamesha aik hi row rehti hai — id = 1.
-- ============================================================

create table if not exists app_settings (
  id               integer     not null default 1,
  currency_code    text        not null default 'PKR',
  currency_symbol  text        not null default 'Rs',
  fy_start_month   integer     not null default 7,      -- Pakistan mein maali saal July se
  sale_prefix      text        not null default 'S',
  purchase_prefix  text        not null default 'P',
  print_terms      text        default ''::text,        -- bill ke neeche chhapne wali shartein
  updated_at       timestamptz not null default now(),
  updated_by       uuid
);

alter table app_settings add constraint app_settings_pkey primary key (id);
alter table app_settings add constraint app_settings_id_check check (id = 1);
alter table app_settings add constraint app_settings_fy_check
  check (fy_start_month between 1 and 12);
alter table app_settings add constraint app_settings_prefix_check
  check (trim(both from sale_prefix) <> '' and trim(both from purchase_prefix) <> '');
alter table app_settings add constraint app_settings_updated_by_fkey
  foreign key (updated_by) references app_users(id);

-- ---------- RLS ----------

alter table app_settings enable row level security;

drop policy if exists "app_settings select" on app_settings;
drop policy if exists "app_settings update" on app_settings;

create policy "app_settings select" on app_settings for select using (auth.role() = 'authenticated');
create policy "app_settings update" on app_settings for update
  using (auth.role() = 'authenticated')
  with check (is_app_admin() or has_perm('masters_edit'));

-- ---------- Seed ----------

insert into app_settings (id) values (1) on conflict (id) do nothing;

-- ============================================================
--  Voucher numbering ab prefix settings se aata hai
--
--  YEH 07_period_lock_numbering.sql WALE assign_voucher_number() KO BADALTA HAI.
--  Prefix badalne se purane vouchers nahi badalte — sirf naye is prefix se
--  banenge. Sequence wahi rehti hai, is liye number kabhi dohraya nahi jata.
-- ============================================================

create or replace function public.assign_voucher_number()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  sale_p text;
  buy_p  text;
begin
  if NEW.vno is not null and trim(NEW.vno) <> '' then
    return NEW;
  end if;

  select coalesce(sale_prefix, 'S'), coalesce(purchase_prefix, 'P')
    into sale_p, buy_p
    from app_settings where id = 1;

  if NEW.vtype = 'sale' then
    NEW.vno := coalesce(sale_p, 'S') || '-' || lpad(nextval('voucher_sale_seq')::text, 4, '0');
  else
    NEW.vno := coalesce(buy_p, 'P') || '-' || lpad(nextval('voucher_purchase_seq')::text, 4, '0');
  end if;
  return NEW;
end;
$function$;

-- ============================================================
--  Financial year ki tareekhein nikalne ke liye helper
--  Reports aur P&L isay istemaal kar sakte hain.
-- ============================================================

create or replace function public.fy_range(p_date date default current_date)
returns table(fy_start date, fy_end date, fy_label text)
language plpgsql
stable
as $function$
declare
  m      integer;
  y      integer;
  s      date;
begin
  select coalesce(fy_start_month, 7) into m from app_settings where id = 1;
  if m is null then m := 7; end if;

  y := extract(year from p_date)::integer;
  if extract(month from p_date)::integer < m then
    y := y - 1;
  end if;

  s := make_date(y, m, 1);
  return query select s, (s + interval '1 year' - interval '1 day')::date,
                      (case when m = 1 then y::text
                            else y::text || '-' || right((y + 1)::text, 2) end);
end;
$function$;
