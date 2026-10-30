-- Common masters shared by every module: parties, items, vehicles.
-- One record per real-world thing across all companies of a tenant; company-specific terms
-- (credit limit, price category) live in child tables.

-- ---------------------------------------------------------------------------
-- Party: customers, vendors, sub-contractors, transporters, credit customers, group companies
-- ---------------------------------------------------------------------------

create table public.party (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.tenant,
  party_code        text not null,
  display_name      text not null,
  legal_name        text,
  party_types       text[] not null check (party_types <@ array[
                      'customer', 'vendor', 'sub_contractor', 'transporter', 'bunk_credit', 'govt_dept', 'employee_payee']
                      and cardinality(party_types) > 0),
  -- A group company as a party: every sale/purchase with it is tagged inter-company automatically.
  group_company_id  uuid references public.company,
  pan               text check (pan ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'),
  gst_treatment     text not null default 'regular'
                    check (gst_treatment in ('regular', 'composition', 'unregistered', 'consumer', 'sez', 'overseas')),
  msme_udyam_no     text,
  msme_type         text check (msme_type in ('micro', 'small', 'medium')),
  tds_section       text,
  tds_rate          numeric(5, 2),
  mobile            text,
  whatsapp          text,
  email             text,
  status            text not null default 'active' check (status in ('active', 'blocked', 'inactive')),
  blocked_reason    text,
  risk_score        smallint check (risk_score between 0 and 100),   -- computed by the collections job
  created_by        uuid default auth.uid(),
  created_at        timestamptz not null default now(),
  is_intercompany   boolean generated always as (group_company_id is not null) stored,
  unique (tenant_id, party_code),
  check (status <> 'blocked' or blocked_reason is not null)
);
create unique index party_pan_unique on public.party (tenant_id, pan) where pan is not null;
create index party_name_trgm on public.party using gin (display_name extensions.gin_trgm_ops);
create index on public.party (tenant_id, mobile);

create table public.party_gstin (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenant,
  party_id   uuid not null references public.party on delete cascade,
  gstin      text not null check (gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
  state_code char(2) generated always as (left(gstin, 2)) stored,
  legal_name_on_portal text,          -- filled from the GSTIN lookup API
  verified_at timestamptz,
  unique (tenant_id, gstin)
);

create table public.party_address (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenant,
  party_id   uuid not null references public.party on delete cascade,
  kind       text not null check (kind in ('billing', 'shipping', 'site')),
  label      text,                     -- "Gollapudi villa site"
  address    text not null,
  state_code char(2),
  pincode    text check (pincode ~ '^[1-9][0-9]{5}$'),
  lat        numeric(9, 6),
  lng        numeric(9, 6),
  site_contact_name   text,
  site_contact_mobile text
);
create index on public.party_address (party_id);

create table public.party_contact (
  id        uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenant,
  party_id  uuid not null references public.party on delete cascade,
  name      text not null,
  role      text,                      -- accounts / site / purchase / owner
  mobile    text,
  on_whatsapp boolean not null default true,
  email     text
);

-- Terms per company: the same party can be an RMC customer and a bunk credit customer.
create table public.party_company (
  tenant_id      uuid not null references public.tenant,
  party_id       uuid not null references public.party on delete cascade,
  company_id     uuid not null references public.company on delete cascade,
  credit_limit   numeric(14, 2) not null default 0 check (credit_limit >= 0),
  credit_days    integer not null default 0 check (credit_days >= 0),
  price_category text,
  ledger_id      uuid,                 -- set by Finance
  is_active      boolean not null default true,
  primary key (party_id, company_id)
);

-- "Did you mean...?" before a new party is saved. Matches on GSTIN, PAN, mobile and similar name.
create function public.find_similar_parties(
  p_name text, p_mobile text default null, p_pan text default null, p_gstin text default null
) returns table (party_id uuid, display_name text, reason text, score real)
language sql stable security invoker set search_path = public, extensions as $$
  select p.id, p.display_name,
         case when p_gstin is not null and exists (select 1 from party_gstin g where g.party_id = p.id and g.gstin = upper(p_gstin)) then 'same GSTIN'
              when p_pan is not null and p.pan = upper(p_pan) then 'same PAN'
              when p_mobile is not null and (p.mobile = p_mobile or p.whatsapp = p_mobile) then 'same mobile'
              else 'similar name' end,
         greatest(similarity(p.display_name, p_name),
                  case when p_mobile is not null and (p.mobile = p_mobile or p.whatsapp = p_mobile) then 0.95 else 0 end,
                  case when p_pan is not null and p.pan = upper(p_pan) then 1 else 0 end,
                  case when p_gstin is not null and exists (select 1 from party_gstin g where g.party_id = p.id and g.gstin = upper(p_gstin)) then 1 else 0 end)::real as score
  from party p
  where p.tenant_id = public.auth_tenant_id()
    and (similarity(p.display_name, p_name) > 0.4
         or (p_mobile is not null and (p.mobile = p_mobile or p.whatsapp = p_mobile))
         or (p_pan is not null and p.pan = upper(p_pan))
         or (p_gstin is not null and exists (select 1 from party_gstin g where g.party_id = p.id and g.gstin = upper(p_gstin))))
  order by score desc
  limit 5
$$;

-- ---------------------------------------------------------------------------
-- Item / material
-- ---------------------------------------------------------------------------

create table public.item (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.tenant,
  item_code         text not null,
  name              text not null,
  local_name        text,                -- what field staff call it; shown in the mobile app
  photo_url         text,
  category          text not null check (category in (
                      'raw_material', 'finished_good', 'semi_finished', 'consumable', 'spare', 'fuel', 'lube',
                      'service', 'asset', 'scrap')),
  base_uom          text not null,       -- MT, KG, L, M3, NOS, BAG, CFT, BRASS
  hsn_sac           text check (hsn_sac ~ '^[0-9]{4,8}$'),
  gst_rate          numeric(5, 2) check (gst_rate in (0, 0.1, 0.25, 1.5, 3, 5, 12, 18, 28, 40)),
  is_batch_tracked  boolean not null default false,
  is_serial_tracked boolean not null default false,   -- tyres, batteries
  weighbridge_item  boolean not null default false,
  valuation         text not null default 'weighted_avg' check (valuation in ('fifo', 'weighted_avg')),
  standard_cost     numeric(14, 4),
  quality_params    jsonb not null default '[]',      -- [{"name":"penetration","unit":"dmm","min":60,"max":70}]
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  unique (tenant_id, item_code)
);
create index item_name_trgm on public.item using gin (name extensions.gin_trgm_ops);

-- 1 BAG cement = 0.05 MT; 1 BRASS = 100 CFT, etc.
create table public.item_uom (
  item_id   uuid not null references public.item on delete cascade,
  tenant_id uuid not null references public.tenant,
  uom       text not null,
  factor_to_base numeric(18, 8) not null check (factor_to_base > 0),
  primary key (item_id, uom)
);

create table public.item_location (
  tenant_id     uuid not null references public.tenant,
  item_id       uuid not null references public.item on delete cascade,
  location_id   uuid not null references public.location on delete cascade,
  reorder_level numeric(14, 3),
  reorder_qty   numeric(14, 3),
  bin           text,
  primary key (item_id, location_id)
);

-- ---------------------------------------------------------------------------
-- Vehicle / machine (shared by Fleet, Weighbridge, RMC, Bunk, Infra)
-- ---------------------------------------------------------------------------

create table public.vehicle (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenant,
  reg_no              text not null,               -- normalised: upper case, no spaces
  kind                text not null check (kind in (
                        'transit_mixer', 'tipper', 'tanker', 'trailer', 'pump', 'excavator', 'loader', 'roller',
                        'paver', 'grader', 'crane', 'dg_set', 'car', 'two_wheeler', 'tractor', 'other')),
  ownership           text not null default 'own' check (ownership in ('own', 'hired', 'customer', 'vendor')),
  owning_company_id   uuid references public.company,
  owner_party_id      uuid references public.party,  -- for hired / customer vehicles
  make_model          text,
  capacity            numeric(10, 2),
  capacity_uom        text,                          -- M3 / MT / KL
  standard_tare_kg    numeric(10, 1),
  rfid_tag            text,
  fastag_id           text,
  gps_device_id       text,
  fuel_sensor_id      text,
  fuel_type           text check (fuel_type in ('diesel', 'petrol', 'cng', 'electric')),
  tank_capacity_l     numeric(8, 1),
  meter_type          text not null default 'km' check (meter_type in ('km', 'hours', 'both')),
  norm_km_per_l       numeric(6, 2),
  norm_l_per_hour     numeric(6, 2),
  current_odometer    numeric(10, 1),
  current_hours       numeric(10, 1),
  assigned_driver_id  uuid references public.app_user,
  current_location_id uuid references public.location,
  status              text not null default 'active' check (status in ('active', 'breakdown', 'idle', 'sold', 'inactive')),
  created_at          timestamptz not null default now(),
  unique (tenant_id, reg_no),
  check (reg_no = upper(regexp_replace(reg_no, '[^A-Za-z0-9]', '', 'g')))
);
create unique index vehicle_rfid_unique on public.vehicle (tenant_id, rfid_tag) where rfid_tag is not null;

create table public.vehicle_document (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenant,
  vehicle_id  uuid not null references public.vehicle on delete cascade,
  doc_type    text not null check (doc_type in ('rc', 'insurance', 'fitness', 'permit', 'national_permit',
                                                'puc', 'road_tax', 'calibration', 'other')),
  doc_number  text,
  issued_on   date,
  expires_on  date,
  amount      numeric(12, 2),
  file_url    text,
  created_at  timestamptz not null default now()
);
create index on public.vehicle_document (tenant_id, expires_on);

-- Everything expiring soon, across the tenant (feeds the expiry calendar and WhatsApp alerts).
create view public.vehicle_documents_expiring with (security_invoker = true) as
  select d.*, v.reg_no, v.kind, (d.expires_on - current_date) as days_left
  from public.vehicle_document d
  join public.vehicle v on v.id = d.vehicle_id
  where d.expires_on is not null
    and d.id = (select d2.id from public.vehicle_document d2
                where d2.vehicle_id = d.vehicle_id and d2.doc_type = d.doc_type
                order by d2.expires_on desc nulls last limit 1)
    and d.expires_on <= current_date + 30;

-- ---------------------------------------------------------------------------
-- RLS: masters are readable by everyone in the tenant, writable with the master's permission.
-- Writes are checked against any company the user belongs to, since masters are tenant-wide.
-- ---------------------------------------------------------------------------

create function public.can_edit_master(p_feature text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_tenant_admin()
      or exists (select 1 from public.my_company_ids() c(id) where public.user_can(p_feature, 'edit', c.id)
                                                              or public.user_can(p_feature, 'create', c.id))
$$;

do $$
declare
  t text;
  f text;
begin
  for t, f in values
    ('party', 'core.masters.party'), ('party_gstin', 'core.masters.party'), ('party_address', 'core.masters.party'),
    ('party_contact', 'core.masters.party'), ('item', 'core.masters.item'), ('item_uom', 'core.masters.item'),
    ('item_location', 'core.masters.item'), ('vehicle', 'core.masters.vehicle'),
    ('vehicle_document', 'core.masters.vehicle')
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select using (tenant_id = public.auth_tenant_id())', t || '_read', t);
    execute format('create policy %I on public.%I for insert with check (tenant_id = public.auth_tenant_id() and public.can_edit_master(%L))', t || '_insert', t, f);
    execute format('create policy %I on public.%I for update using (tenant_id = public.auth_tenant_id() and public.can_edit_master(%L)) with check (tenant_id = public.auth_tenant_id())', t || '_update', t, f);
    execute format('create policy %I on public.%I for delete using (public.is_tenant_admin(tenant_id))', t || '_delete', t);
    perform audit.track(('public.' || t)::regclass);
  end loop;
end $$;

-- Credit terms are per company: only members of that company see or change them.
alter table public.party_company enable row level security;
create policy party_company_read on public.party_company for select
  using (company_id in (select public.my_company_ids()));
create policy party_company_write on public.party_company for all
  using (public.user_can('core.masters.party', 'edit', company_id))
  with check (public.user_can('core.masters.party', 'edit', company_id));

-- party_company has no id column; audit it against the party.
create function audit.capture_party_company() returns trigger
language plpgsql security definer set search_path = audit, public as $$
declare
  v_row jsonb := to_jsonb(coalesce(new, old));
begin
  perform audit.append((v_row ->> 'tenant_id')::uuid, 'public.party_company',
                       (v_row ->> 'party_id') || ':' || (v_row ->> 'company_id'), tg_op,
                       case when tg_op <> 'INSERT' then to_jsonb(old) end,
                       case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return null;
end;
$$;
create trigger zz_audit after insert or update or delete on public.party_company
  for each row execute function audit.capture_party_company();
