-- Bank statement import and matching, Tally export, document expiry alerts, and device connections
-- (weighbridge scale, biometric machine, GPS / fuel sensor).

-- ---------------------------------------------------------------------------
-- Bank statements
-- ---------------------------------------------------------------------------

-- Import rows [{date, narration, reference, debit, credit, balance}]; duplicates are skipped.
create function public.bank_import(p_company uuid, p_bank_ledger uuid, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r jsonb;
  n int := 0;
  dup int := 0;
  v_tenant uuid := (select tenant_id from company where id = p_company);
begin
  if not public.user_can('finance.bank_reconciliation', 'create', p_company, null) then
    raise exception 'You are not allowed to import bank statements.' using errcode = '42501';
  end if;
  if not exists (select 1 from finance_ledger where id = p_bank_ledger and company_id = p_company and is_bank) then
    raise exception 'Choose one of this company''s bank accounts.';
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if exists (select 1 from finance_bank_txn t where t.bank_ledger_id = p_bank_ledger and t.doc_date = (r ->> 'date')::date
               and t.debit = coalesce((r ->> 'debit')::numeric, 0) and t.credit = coalesce((r ->> 'credit')::numeric, 0)
               and coalesce(t.reference, '') = coalesce(r ->> 'reference', '') and coalesce(t.narration, '') = coalesce(r ->> 'narration', '')) then
      dup := dup + 1;
      continue;
    end if;
    insert into finance_bank_txn (tenant_id, company_id, doc_date, bank_ledger_id, narration, reference, debit, credit, balance)
    values (v_tenant, p_company, (r ->> 'date')::date, p_bank_ledger, r ->> 'narration', r ->> 'reference',
            coalesce((r ->> 'debit')::numeric, 0), coalesce((r ->> 'credit')::numeric, 0), (r ->> 'balance')::numeric);
    n := n + 1;
  end loop;
  return jsonb_build_object('imported', n, 'duplicates', dup, 'matched', public.bank_auto_match(p_company));
end;
$$;

-- Match unmatched statement lines to receipts (credits) and payments (debits):
-- same amount, within 3 days; the UTR / cheque number in the narration makes it certain.
create function public.bank_auto_match(p_company uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  t record;
  m record;
  n int := 0;
begin
  for t in select * from finance_bank_txn where company_id = p_company and match_status in ('unmatched', 'suggested') loop
    if t.credit > 0 then
      select 'finance.receipt' as entity, r.id, case when r.reference_no is not null and t.narration ilike '%' || r.reference_no || '%' then 100
             when r.doc_date = t.doc_date then 85 else 70 end as conf
        into m
      from finance_receipt r
      where r.company_id = p_company and r.amount = t.credit and abs(r.doc_date - t.doc_date) <= 3 and r.mode <> 'cash'
        and not exists (select 1 from finance_bank_txn x where x.matched_id = r.id::text and x.id <> t.id)
      order by 3 desc, abs(r.doc_date - t.doc_date) limit 1;
    else
      select 'finance.payment' as entity, p.id, case when p.reference_no is not null and t.narration ilike '%' || p.reference_no || '%' then 100
             when p.doc_date = t.doc_date then 85 else 70 end as conf
        into m
      from finance_payment p
      where p.company_id = p_company and p.amount = t.debit and abs(p.doc_date - t.doc_date) <= 3 and p.mode <> 'cash'
        and p.status = 'approved'
        and not exists (select 1 from finance_bank_txn x where x.matched_id = p.id::text and x.id <> t.id)
      order by 3 desc, abs(p.doc_date - t.doc_date) limit 1;
    end if;
    if m.id is not null then
      update finance_bank_txn set matched_entity = m.entity, matched_id = m.id::text, match_confidence = m.conf,
        match_status = case when m.conf >= 85 then 'matched' else 'suggested' end
      where id = t.id;
      n := n + 1;
    end if;
    m := null;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tally export (XML vouchers for Tally's Import Data)
-- ---------------------------------------------------------------------------
create function public.tally_export(p_company uuid, p_from date, p_to date) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v xml;
begin
  if not public.user_can('finance.tally_export', 'export', p_company, null) and not public.is_tenant_admin() then
    raise exception 'You are not allowed to export to Tally.' using errcode = '42501';
  end if;
  select xmlelement(name "ENVELOPE",
    xmlelement(name "HEADER", xmlelement(name "TALLYREQUEST", 'Import Data')),
    xmlelement(name "BODY", xmlelement(name "IMPORTDATA",
      xmlelement(name "REQUESTDESC", xmlelement(name "REPORTNAME", 'Vouchers'),
        xmlelement(name "STATICVARIABLES", xmlelement(name "SVCURRENTCOMPANY", (select legal_name from company where id = p_company)))),
      xmlelement(name "REQUESTDATA", xmlagg(
        xmlelement(name "TALLYMESSAGE",
          xmlelement(name "VOUCHER", xmlattributes(initcap(j.voucher_type) as "VCHTYPE", 'Create' as "ACTION"),
            xmlelement(name "DATE", to_char(j.doc_date, 'YYYYMMDD')),
            xmlelement(name "VOUCHERTYPENAME", case j.voucher_type when 'payroll' then 'Journal' when 'stock' then 'Journal' else initcap(replace(j.voucher_type, '_', ' ')) end),
            xmlelement(name "VOUCHERNUMBER", j.doc_no),
            xmlelement(name "NARRATION", j.narration),
            (select xmlagg(xmlelement(name "ALLLEDGERENTRIES.LIST",
                       xmlelement(name "LEDGERNAME", coalesce(p.display_name, fl.name)),
                       xmlelement(name "ISDEEMEDPOSITIVE", case when l.debit > 0 then 'Yes' else 'No' end),
                       xmlelement(name "AMOUNT", case when l.debit > 0 then -l.debit else l.credit end)) order by l.line_no)
             from finance_journal_lines l join finance_ledger fl on fl.id = l.ledger_id left join party p on p.id = l.party_id
             where l.parent_id = j.id)))
        order by j.doc_date, j.doc_no))))) into v
  from finance_journal j
  where j.company_id = p_company and j.status = 'approved' and j.doc_date between p_from and p_to;
  return '<?xml version="1.0" encoding="UTF-8"?>' || coalesce(v::text, '<ENVELOPE/>');
end;
$$;

-- ---------------------------------------------------------------------------
-- Devices
-- ---------------------------------------------------------------------------
create table public.device (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenant,
  company_id   uuid not null references public.company,
  location_id  uuid references public.location,
  kind         text not null check (kind in ('weighbridge', 'biometric', 'gps', 'atg')),
  name         text not null,
  serial       text not null unique,
  key_hash     text not null,
  config       jsonb not null default '{}',     -- e.g. {"ticket_type": "purchase_inward", "min_stable_seconds": 3}
  is_active    boolean not null default true,
  last_seen_at timestamptz,
  created_at   timestamptz not null default now()
);
alter table public.device enable row level security;
create policy device_read on public.device for select using (public.is_tenant_admin(tenant_id));
create policy device_write on public.device for update using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));
create policy device_delete on public.device for delete using (public.is_tenant_admin(tenant_id));
select audit.track('public.device');

create table public.vehicle_position (
  id          bigint generated always as identity primary key,
  tenant_id   uuid not null references public.tenant,
  vehicle_id  uuid not null references public.vehicle on delete cascade,
  at          timestamptz not null,
  lat         numeric(9, 6),
  lng         numeric(9, 6),
  speed_kmph  numeric(6, 1),
  odometer    numeric(10, 1),
  fuel_l      numeric(8, 1),
  ignition    boolean
);
create index on public.vehicle_position (vehicle_id, at desc);
alter table public.vehicle_position enable row level security;
create policy position_read on public.vehicle_position for select using (tenant_id = public.auth_tenant_id());

create table public.fuel_drop_alert (
  id         bigint generated always as identity primary key,
  tenant_id  uuid not null references public.tenant,
  vehicle_id uuid not null references public.vehicle on delete cascade,
  at         timestamptz not null,
  litres     numeric(8, 1) not null,
  lat        numeric(9, 6),
  lng        numeric(9, 6)
);
alter table public.fuel_drop_alert enable row level security;
create policy fuel_drop_read on public.fuel_drop_alert for select using (tenant_id = public.auth_tenant_id());

-- Admin registers a device; the secret key is shown once and stored only as a hash.
create function public.device_register(p_company uuid, p_location uuid, p_kind text, p_name text, p_config jsonb default '{}')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_key text := encode(extensions.gen_random_bytes(24), 'hex');
  v_serial text := lower(p_kind) || '-' || encode(extensions.gen_random_bytes(4), 'hex');
  v_id uuid;
begin
  if not public.is_tenant_admin((select tenant_id from company where id = p_company)) then
    raise exception 'Only admins can add devices.' using errcode = '42501';
  end if;
  insert into device (tenant_id, company_id, location_id, kind, name, serial, key_hash, config)
  values ((select tenant_id from company where id = p_company), p_company, p_location, p_kind, p_name, v_serial,
          encode(extensions.digest(v_key, 'sha256'), 'hex'), coalesce(p_config, '{}'))
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'serial', v_serial, 'key', v_key);
end;
$$;

-- Devices call this directly with the public API key plus their own serial and secret.
create function public.device_ingest(p_serial text, p_key text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  d device;
  t weighbridge_ticket;
  r jsonb;
  emp hr_employee;
  v vehicle;
  prev vehicle_position;
  v_at timestamptz;
  n int := 0;
  v_out jsonb := '{}';
begin
  select * into d from device where serial = p_serial and is_active
    and key_hash = encode(extensions.digest(coalesce(p_key, ''), 'sha256'), 'hex');
  if not found then
    raise exception 'unknown device or wrong key' using errcode = '42501';
  end if;
  update device set last_seen_at = now() where id = d.id;
  perform audit.set_context(p_source => 'hardware', p_actor_type => 'hardware', p_device_id => d.serial);

  if d.kind = 'weighbridge' then
    -- {weight_kg, stable_seconds, vehicle_no, images[]}: second weighment if the vehicle has an open ticket, else a new one
    if coalesce((p_payload ->> 'stable_seconds')::numeric, 0) < coalesce((d.config ->> 'min_stable_seconds')::numeric, 3) then
      raise exception 'weight not stable yet';
    end if;
    select * into t from weighbridge_ticket
    where location_id = d.location_id and ticket_status = 'first_done'
      and vehicle_no = upper(regexp_replace(p_payload ->> 'vehicle_no', '[^A-Za-z0-9]', '', 'g'))
    order by created_at desc limit 1;
    if found then
      update weighbridge_ticket set second_weight_kg = (p_payload ->> 'weight_kg')::numeric, second_mode = 'scale', second_weight_at = now(),
        second_images = array(select jsonb_array_elements_text(coalesce(p_payload -> 'images', '[]')))
      where id = t.id;
      v_out := jsonb_build_object('ticket_id', t.id, 'weighment', 'second');
    else
      insert into weighbridge_ticket (tenant_id, company_id, location_id, doc_no, doc_date, ticket_type, vehicle_no, vehicle_source,
                                      first_weight_kg, first_mode, first_weight_at, first_images)
      values (d.tenant_id, d.company_id, d.location_id, public.doc_number_internal(d.company_id, d.location_id, 'weighbridge.ticket', current_date),
              current_date, coalesce(d.config ->> 'ticket_type', 'purchase_inward'),
              upper(regexp_replace(p_payload ->> 'vehicle_no', '[^A-Za-z0-9]', '', 'g')), coalesce(p_payload ->> 'vehicle_source', 'anpr'),
              (p_payload ->> 'weight_kg')::numeric, 'scale', now(), array(select jsonb_array_elements_text(coalesce(p_payload -> 'images', '[]'))))
      returning * into t;
      v_out := jsonb_build_object('ticket_id', t.id, 'doc_no', t.doc_no, 'weighment', 'first');
    end if;

  elsif d.kind = 'biometric' then
    -- {records: [{emp_code, time}]}: first punch of the day = in, last = out
    for r in select * from jsonb_array_elements(coalesce(p_payload -> 'records', '[]')) loop
      select * into emp from hr_employee where company_id = d.company_id and emp_code = r ->> 'emp_code';
      continue when not found;
      v_at := (r ->> 'time')::timestamptz;
      insert into hr_attendance (tenant_id, company_id, location_id, doc_date, employee_id, mark, in_time, out_time, source, device_serial)
      values (d.tenant_id, d.company_id, coalesce(d.location_id, emp.location_id), (v_at at time zone 'Asia/Kolkata')::date, emp.id,
              'present', v_at, null, 'biometric', d.serial)
      on conflict (employee_id, doc_date) do update
        set in_time = least(hr_attendance.in_time, excluded.in_time),
            out_time = case when excluded.in_time > coalesce(hr_attendance.in_time, excluded.in_time) then greatest(coalesce(hr_attendance.out_time, excluded.in_time), excluded.in_time)
                            else hr_attendance.out_time end,
            mark = case when hr_attendance.mark in ('absent', 'leave') then 'present' else hr_attendance.mark end;
      n := n + 1;
    end loop;
    v_out := jsonb_build_object('punches', n);

  elsif d.kind = 'gps' then
    -- {vehicle_no, at, lat, lng, speed_kmph, odometer, fuel_l, ignition}
    select * into v from vehicle where tenant_id = d.tenant_id
      and (reg_no = upper(regexp_replace(p_payload ->> 'vehicle_no', '[^A-Za-z0-9]', '', 'g')) or gps_device_id = p_payload ->> 'gps_id');
    if not found then
      raise exception 'vehicle not registered';
    end if;
    select * into prev from vehicle_position where vehicle_id = v.id order by at desc limit 1;
    insert into vehicle_position (tenant_id, vehicle_id, at, lat, lng, speed_kmph, odometer, fuel_l, ignition)
    values (d.tenant_id, v.id, coalesce((p_payload ->> 'at')::timestamptz, now()), (p_payload ->> 'lat')::numeric, (p_payload ->> 'lng')::numeric,
            (p_payload ->> 'speed_kmph')::numeric, (p_payload ->> 'odometer')::numeric, (p_payload ->> 'fuel_l')::numeric,
            (p_payload ->> 'ignition')::boolean);
    if (p_payload ->> 'odometer') is not null then
      update vehicle set current_odometer = greatest(coalesce(current_odometer, 0), (p_payload ->> 'odometer')::numeric) where id = v.id;
    end if;
    -- fuel falling while the vehicle stands still: possible theft
    if prev.fuel_l is not null and (p_payload ->> 'fuel_l') is not null
       and prev.fuel_l - (p_payload ->> 'fuel_l')::numeric >= coalesce((d.config ->> 'theft_litres')::numeric, 8)
       and coalesce((p_payload ->> 'speed_kmph')::numeric, 0) < 3 and coalesce(prev.speed_kmph, 0) < 3 then
      insert into fuel_drop_alert (tenant_id, vehicle_id, at, litres, lat, lng)
      values (d.tenant_id, v.id, coalesce((p_payload ->> 'at')::timestamptz, now()), prev.fuel_l - (p_payload ->> 'fuel_l')::numeric,
              (p_payload ->> 'lat')::numeric, (p_payload ->> 'lng')::numeric);
      v_out := jsonb_build_object('alert', 'fuel_drop');
    end if;
  end if;
  return v_out || jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.device_ingest(text, text, jsonb) to anon;

-- Leakage board: add expiring licences and fuel drops (replaces the earlier version).
create or replace function public.leakage_board_extra(p_company uuid)
returns table (kind text, severity text, title text, detail text, entity text, record_id uuid, location_id uuid, amount numeric, doc_date date)
language sql stable security definer set search_path = public as $$
  select 'licence_expiry', case when d.expires_on < current_date then 'high' else 'medium' end,
         'Licence ' || case when d.expires_on < current_date then 'expired' else 'expiring' end,
         format('%s %s', d.title, coalesce(d.doc_number, '')), 'core.document', d.id, null::uuid, d.amount, d.expires_on
  from core_document d
  where d.company_id = p_company and d.expires_on is not null and d.expires_on <= current_date + coalesce(d.remind_days, 30)
  union all
  select 'fuel_drop', 'high', 'Fuel fell while the vehicle stood still', format('%s: %s L', v.reg_no, trim_scale(a.litres)),
         null, a.vehicle_id, null, a.litres, (a.at at time zone 'Asia/Kolkata')::date
  from fuel_drop_alert a join vehicle v on v.id = a.vehicle_id
  where v.owning_company_id = p_company and a.at > now() - interval '30 days'
$$;
