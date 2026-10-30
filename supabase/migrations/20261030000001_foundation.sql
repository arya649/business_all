-- Foundation: tenants, companies, locations, users, feature switches, roles and permissions.
--
-- Hierarchy:  platform (us) -> tenant (a client business group) -> company (GSTIN holder) -> location
-- Access is the intersection of three layers, like Zentrix ADK's partner ∩ customer ∩ token:
--   plan (what the platform sold to the tenant)  ∩  feature switches (tenant admin)  ∩  role permissions

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------------
-- Tenancy
-- ---------------------------------------------------------------------------

create table public.tenant (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  logo_url         text,
  fy_start_month   smallint not null default 4 check (fy_start_month between 1 and 12),
  base_currency    char(3) not null default 'INR',
  timezone         text not null default 'Asia/Kolkata',
  default_language text not null default 'en',
  status           text not null default 'active' check (status in ('active', 'suspended')),
  created_at       timestamptz not null default now()
);

create table public.company (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenant on delete restrict,
  legal_name       text not null,
  trade_name       text,
  short_code       text not null check (short_code ~ '^[A-Z0-9]{2,8}$'),
  pan              text check (pan ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'),
  tan              text,
  cin              text,
  logo_url         text,
  books_start_date date,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  unique (tenant_id, short_code)
);
create index on public.company (tenant_id);

create table public.company_gstin (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenant,
  company_id          uuid not null references public.company on delete cascade,
  gstin               text not null unique
                      check (gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
  state_code          char(2) generated always as (left(gstin, 2)) stored,
  registered_address  text,
  e_invoice_enabled   boolean not null default false,
  eway_enabled        boolean not null default false,
  gsp_credentials_ref text,            -- key name in the secrets vault, never the secret itself
  filing_frequency    text not null default 'monthly' check (filing_frequency in ('monthly', 'qrmp')),
  created_at          timestamptz not null default now()
);
create index on public.company_gstin (company_id);

create type public.location_type as enum (
  'branch', 'office', 'plant', 'site', 'bunk', 'weighbridge', 'yard', 'warehouse',
  -- sub-locations (parent_id set)
  'silo', 'tank', 'bin', 'bay', 'store', 'curing_block', 'floor'
);

create table public.location (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenant,
  company_id         uuid not null references public.company on delete restrict,
  parent_id          uuid references public.location on delete restrict,
  gstin_id           uuid references public.company_gstin,
  type               public.location_type not null,
  name               text not null,
  short_code         text not null check (short_code ~ '^[A-Z0-9-]{2,12}$'),
  address            text,
  lat                numeric(9, 6),
  lng                numeric(9, 6),
  geofence_radius_m  integer not null default 200 check (geofence_radius_m > 0),
  in_charge_user_id  uuid,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  unique (company_id, short_code)
);
create index on public.location (company_id);
create index on public.location (parent_id);

-- ---------------------------------------------------------------------------
-- Users (one row per Supabase auth user)
-- ---------------------------------------------------------------------------

create table public.app_user (
  id                 uuid primary key references auth.users on delete cascade,
  tenant_id          uuid references public.tenant,          -- null only for platform staff
  full_name          text not null,
  mobile             text unique check (mobile ~ '^\+?[0-9]{10,15}$'),
  email              text,
  photo_url          text,
  preferred_language text not null default 'en',
  is_platform_admin  boolean not null default false,
  is_tenant_admin    boolean not null default false,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  check (is_platform_admin or tenant_id is not null)
);
create index on public.app_user (tenant_id);

alter table public.location
  add constraint location_in_charge_fk foreign key (in_charge_user_id) references public.app_user;

-- ---------------------------------------------------------------------------
-- Feature catalogue and switches
-- ---------------------------------------------------------------------------

-- Ordered from most to least restrictive so least()/max() work directly on the enum.
create type public.feature_state as enum ('off', 'hidden', 'read_only', 'on');

create table public.feature (
  key            text primary key check (key ~ '^[a-z0-9_]+(\.[a-z0-9_]+)*$'),
  parent_key     text references public.feature on delete cascade,
  label          text not null,
  description    text,
  default_state  public.feature_state not null default 'on',
  default_config jsonb not null default '{}',
  sort           integer not null default 0
);
create index on public.feature (parent_key);

-- plan     : set by the platform per tenant; a ceiling the tenant can never exceed
-- tenant .. user : set by the tenant admin; the most specific level wins
create type public.flag_level as enum ('plan', 'tenant', 'company', 'location', 'role', 'user');

create table public.feature_flag (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenant on delete cascade,
  feature_key text not null references public.feature on delete cascade,
  level       public.flag_level not null,
  level_id    uuid not null,                 -- tenant / company / location / role / user id
  state       public.feature_state,          -- null = inherit, only override config
  config      jsonb,
  updated_by  uuid default auth.uid(),
  updated_at  timestamptz not null default now(),
  unique (feature_key, level, level_id)
);
create index on public.feature_flag (tenant_id);

-- ---------------------------------------------------------------------------
-- Roles and permissions
-- ---------------------------------------------------------------------------

create table public.role (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenant on delete cascade,
  name        text not null,
  description text,
  ui_mode     text not null default 'simple' check (ui_mode in ('simple', 'standard', 'power')),
  created_at  timestamptz not null default now(),
  unique (tenant_id, name)
);

-- A permission on a parent feature covers its children ("rmc" covers "rmc.batch_entry").
create table public.role_permission (
  role_id           uuid not null references public.role on delete cascade,
  feature_key       text not null references public.feature on delete cascade,
  actions           text[] not null check (actions <@ array[
                      'view', 'create', 'edit', 'delete', 'approve', 'export', 'print', 'see_rates', 'see_cost']),
  masked_fields     text[] not null default '{}',
  edit_window_hours integer check (edit_window_hours > 0),
  primary key (role_id, feature_key)
);

-- location_id null = every location of the company
create table public.user_assignment (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenant on delete cascade,
  user_id     uuid not null references public.app_user on delete cascade,
  company_id  uuid not null references public.company on delete cascade,
  location_id uuid references public.location on delete cascade,
  role_id     uuid not null references public.role on delete cascade,
  valid_from  date not null default current_date,
  valid_to    date,
  check (valid_to is null or valid_to >= valid_from)
);
create index on public.user_assignment (user_id, company_id);

-- ---------------------------------------------------------------------------
-- Identity helpers (security definer so RLS policies can call them without recursion)
-- ---------------------------------------------------------------------------

create function public.auth_tenant_id() returns uuid
language sql stable security definer set search_path = public as $$
  select u.tenant_id from app_user u
  join tenant t on t.id = u.tenant_id
  where u.id = auth.uid() and u.is_active and t.status = 'active'
$$;

create function public.is_platform_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_platform_admin and is_active from app_user where id = auth.uid()), false)
$$;

create function public.is_tenant_admin(p_tenant uuid default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_platform_admin() or coalesce((
    select u.is_tenant_admin from app_user u
    where u.id = auth.uid() and u.is_active
      and u.tenant_id = coalesce(p_tenant, public.auth_tenant_id())
  ), false)
$$;

-- Active assignments of the caller today.
create function public.my_assignments()
returns setof public.user_assignment
language sql stable security definer set search_path = public as $$
  select a.* from user_assignment a
  where a.user_id = auth.uid()
    and current_date >= a.valid_from
    and (a.valid_to is null or current_date <= a.valid_to)
    and a.tenant_id = public.auth_tenant_id()
$$;

create function public.my_company_ids() returns setof uuid
language sql stable security definer set search_path = public as $$
  select id from company where tenant_id = public.auth_tenant_id() and public.is_tenant_admin()
  union
  select company_id from public.my_assignments()
$$;

-- ---------------------------------------------------------------------------
-- Feature resolution
-- ---------------------------------------------------------------------------
-- For one user in one company (and optionally one location) returns every feature's
-- effective state and merged config. A child is never more open than its parent,
-- and nothing is more open than the tenant's plan.

create function public.resolved_features(
  p_company  uuid,
  p_location uuid default null,
  p_user     uuid default null
)
returns table (feature_key text, state public.feature_state, config jsonb)
language plpgsql stable security definer set search_path = public as $$
declare
  v_user   uuid := coalesce(p_user, auth.uid());
  v_tenant uuid;
  v_roles  uuid[];
begin
  -- Only admins may resolve for someone else. System code (no signed-in user) resolves for the record's author.
  if v_user is distinct from auth.uid() and auth.uid() is not null and not public.is_tenant_admin() then
    raise exception 'not allowed to resolve features for another user' using errcode = '42501';
  end if;

  select c.tenant_id into v_tenant from company c where c.id = p_company;
  if v_tenant is null then
    return;
  end if;

  select coalesce(array_agg(distinct a.role_id), '{}') into v_roles
  from user_assignment a
  where a.user_id = v_user and a.company_id = p_company
    and (a.location_id is null or a.location_id = p_location)
    and current_date >= a.valid_from and (a.valid_to is null or current_date <= a.valid_to);

  return query
  with recursive own as (
    select
      f.key, f.parent_key,
      least(
        coalesce(
          (select ff.state from feature_flag ff where ff.feature_key = f.key and ff.level = 'user'     and ff.level_id = v_user     and ff.state is not null),
          (select max(ff.state) from feature_flag ff where ff.feature_key = f.key and ff.level = 'role' and ff.level_id = any(v_roles)),
          (select ff.state from feature_flag ff where ff.feature_key = f.key and ff.level = 'location' and ff.level_id = p_location and ff.state is not null),
          (select ff.state from feature_flag ff where ff.feature_key = f.key and ff.level = 'company'  and ff.level_id = p_company  and ff.state is not null),
          (select ff.state from feature_flag ff where ff.feature_key = f.key and ff.level = 'tenant'   and ff.level_id = v_tenant   and ff.state is not null),
          f.default_state),
        coalesce(
          (select ff.state from feature_flag ff where ff.feature_key = f.key and ff.level = 'plan' and ff.level_id = v_tenant and ff.state is not null),
          'on'::feature_state)
      ) as own_state,
      f.default_config
        || coalesce((select ff.config from feature_flag ff where ff.feature_key = f.key and ff.level = 'plan'     and ff.level_id = v_tenant),   '{}')
        || coalesce((select ff.config from feature_flag ff where ff.feature_key = f.key and ff.level = 'tenant'   and ff.level_id = v_tenant),   '{}')
        || coalesce((select ff.config from feature_flag ff where ff.feature_key = f.key and ff.level = 'company'  and ff.level_id = p_company),  '{}')
        || coalesce((select ff.config from feature_flag ff where ff.feature_key = f.key and ff.level = 'location' and ff.level_id = p_location), '{}')
        || coalesce((select ff.config from feature_flag ff where ff.feature_key = f.key and ff.level = 'user'     and ff.level_id = v_user),     '{}')
        as merged_config
    from feature f
  ),
  tree as (
    select o.key, o.own_state as eff, o.merged_config from own o where o.parent_key is null
    union all
    select o.key, least(o.own_state, t.eff), o.merged_config
    from own o join tree t on o.parent_key = t.key
  )
  select t.key, t.eff, t.merged_config from tree t;
end;
$$;

create function public.feature_state_of(p_feature text, p_company uuid, p_location uuid default null)
returns public.feature_state
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select r.state from public.resolved_features(p_company, p_location) r where r.feature_key = p_feature),
    'off')
$$;

-- ---------------------------------------------------------------------------
-- Permission check used by RLS write policies and by every RPC
-- ---------------------------------------------------------------------------

create function public.user_can(
  p_feature  text,
  p_action   text,
  p_company  uuid,
  p_location uuid default null
) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_state feature_state;
begin
  if p_company is null or auth.uid() is null then
    return false;
  end if;
  if not exists (select 1 from company c where c.id = p_company and c.tenant_id = public.auth_tenant_id())
     and not public.is_platform_admin() then
    return false;
  end if;

  v_state := public.feature_state_of(p_feature, p_company, p_location);
  if v_state in ('off', 'hidden') then
    return false;
  end if;
  if v_state = 'read_only' and p_action not in ('view', 'export', 'print') then
    return false;
  end if;

  if public.is_tenant_admin() then
    return true;
  end if;

  return exists (
    select 1
    from public.my_assignments() a
    join role_permission rp on rp.role_id = a.role_id
    where a.company_id = p_company
      and (a.location_id is null or a.location_id = p_location
           or a.location_id = (select l.parent_id from location l where l.id = p_location))
      and (rp.feature_key = p_feature or p_feature like rp.feature_key || '.%')
      and p_action = any(rp.actions)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.tenant          enable row level security;
alter table public.company         enable row level security;
alter table public.company_gstin   enable row level security;
alter table public.location        enable row level security;
alter table public.app_user        enable row level security;
alter table public.feature         enable row level security;
alter table public.feature_flag    enable row level security;
alter table public.role            enable row level security;
alter table public.role_permission enable row level security;
alter table public.user_assignment enable row level security;

create policy tenant_read  on public.tenant for select using (id = public.auth_tenant_id() or public.is_platform_admin());
create policy tenant_write on public.tenant for all    using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy company_read  on public.company for select using (id in (select public.my_company_ids()) or public.is_platform_admin());
create policy company_write on public.company for all
  using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));

create policy gstin_read  on public.company_gstin for select using (company_id in (select public.my_company_ids()) or public.is_platform_admin());
create policy gstin_write on public.company_gstin for all
  using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));

create policy location_read  on public.location for select using (company_id in (select public.my_company_ids()) or public.is_platform_admin());
create policy location_write on public.location for all
  using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));

-- Everyone in a tenant can see colleagues' names (needed for pickers); only admins edit.
create policy user_read  on public.app_user for select using (tenant_id = public.auth_tenant_id() or id = auth.uid() or public.is_platform_admin());
create policy user_write on public.app_user for all
  using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id) and (not is_platform_admin or public.is_platform_admin()));

create policy feature_read  on public.feature for select using (auth.uid() is not null);
create policy feature_write on public.feature for all using (public.is_platform_admin()) with check (public.is_platform_admin());

-- Plan-level switches belong to the platform; every other level to the tenant admin.
create policy flag_read on public.feature_flag for select using (tenant_id = public.auth_tenant_id() or public.is_platform_admin());
create policy flag_write on public.feature_flag for all
  using (case when level = 'plan' then public.is_platform_admin() else public.is_tenant_admin(tenant_id) end)
  with check (case when level = 'plan' then public.is_platform_admin() else public.is_tenant_admin(tenant_id) end);

create policy role_read  on public.role for select using (tenant_id = public.auth_tenant_id() or public.is_platform_admin());
create policy role_write on public.role for all using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));

create policy role_perm_read on public.role_permission for select
  using (exists (select 1 from public.role r where r.id = role_id and (r.tenant_id = public.auth_tenant_id() or public.is_platform_admin())));
create policy role_perm_write on public.role_permission for all
  using (exists (select 1 from public.role r where r.id = role_id and public.is_tenant_admin(r.tenant_id)))
  with check (exists (select 1 from public.role r where r.id = role_id and public.is_tenant_admin(r.tenant_id)));

create policy assignment_read on public.user_assignment for select
  using (user_id = auth.uid() or public.is_tenant_admin(tenant_id));
create policy assignment_write on public.user_assignment for all
  using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));

revoke execute on function public.resolved_features(uuid, uuid, uuid) from public, anon;
grant execute on function public.resolved_features(uuid, uuid, uuid) to authenticated, service_role;
