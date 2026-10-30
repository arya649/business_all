-- Module engine: one set of rules for every module's screens.
--
-- Each module describes its records (entities) and fields in config/modules/*.mjs. The generator creates the
-- tables and fills erp_entity / erp_field. Every read and write from the web app, the mobile app and AI agents
-- goes through the erp_* functions below, which apply in one place:
--   * feature switches (off / hidden / read_only) for the user's company and location
--   * role permissions (view / create / edit / delete / approve / see_rates / see_cost)
--   * field visibility: fields unticked for the user's roles, fields hidden by a switch's config, rate and
--     cost fields for users without see_rates / see_cost (navam-style "response fields 14/17")
--   * document numbering, workflow status, approvals, required-field checks, locked records
-- Module tables are not readable directly by app users; only these functions read them.

create table public.erp_entity (
  key          text primary key,                        -- rmc.order
  module       text not null,                           -- rmc
  feature_key  text not null references public.feature,
  table_name   text not null unique,
  parent_key   text references public.erp_entity,       -- set for line tables
  child_name   text,                                    -- property name on the parent ("lines")
  label        text not null,
  label_plural text not null,
  kind         text not null check (kind in ('master', 'transaction', 'log', 'child')),
  scope        text not null check (scope in ('company', 'location')),
  numbering    text,                                    -- pattern; null = no document number
  workflow     boolean not null default false,          -- draft → submitted → approved / rejected / cancelled
  dated        boolean not null default false,          -- has doc_date
  title_field  text,
  amount_field text,                                    -- shown on approval cards, used by approval rules
  mobile       boolean not null default false,          -- shown as a tile in the mobile app
  icon         text,
  description  text,
  stock_rules  jsonb,                                   -- stock moves this record makes (see stock migration)
  posting      jsonb,                                   -- default ledger posting (see finance migration)
  submit_hook  text,                                    -- function(uuid) run just before submitting, e.g. 3-way match
  sort         integer not null default 0
);

create table public.erp_field (
  entity_key text not null references public.erp_entity on delete cascade,
  name       text not null,
  label      text not null,
  type       text not null,
  required   boolean not null default false,
  options    jsonb,                                     -- select options
  ref        text,                                      -- party / item / vehicle / app_user / location / company / entity key
  computed   boolean not null default false,
  sensitive  text check (sensitive in ('rates', 'cost')),
  quick      boolean not null default false,            -- shown on the simple (field staff) form
  in_list    boolean not null default false,
  unit       text,
  help       text,
  section    text,
  default_value text,
  sort       integer not null default 0,
  primary key (entity_key, name)
);

alter table public.erp_entity enable row level security;
alter table public.erp_field  enable row level security;
create policy erp_entity_read on public.erp_entity for select using (auth.uid() is not null);
create policy erp_field_read  on public.erp_field  for select using (auth.uid() is not null);

-- ---------------------------------------------------------------------------
-- Field visibility
-- ---------------------------------------------------------------------------

create function public.erp_hidden_fields(p_entity text, p_company uuid, p_location uuid default null)
returns text[]
language plpgsql stable security definer set search_path = public as $$
declare
  v_feature text;
  v_hidden  text[] := '{}';
  v_cfg     jsonb;
begin
  select feature_key into v_feature from erp_entity where key = p_entity;

  -- 1. Hidden for everyone by a switch's config, e.g. {"hidden_fields": ["density"]} at one bunk.
  select r.config into v_cfg from public.resolved_features(p_company, p_location) r where r.feature_key = v_feature;
  if v_cfg ? 'hidden_fields' then
    v_hidden := v_hidden || array(select jsonb_array_elements_text(v_cfg -> 'hidden_fields'));
  end if;

  if public.is_tenant_admin() then
    return v_hidden;
  end if;

  -- 2. Unticked for the user's roles: hidden only if every role that can view the feature hides it.
  v_hidden := v_hidden || coalesce((
    with r as (
      select distinct on (a.role_id) rp.masked_fields
      from public.my_assignments() a
      join role_permission rp on rp.role_id = a.role_id
      where a.company_id = p_company
        and (a.location_id is null or a.location_id = p_location
             or a.location_id = (select l.parent_id from location l where l.id = p_location))
        and (rp.feature_key = v_feature or v_feature like rp.feature_key || '.%')
        and 'view' = any(rp.actions)
      order by a.role_id, length(rp.feature_key) desc
    )
    select array_agg(m) from (
      select m from r, unnest(r.masked_fields) m group by m having count(*) = (select count(*) from r)
    ) x
  ), '{}');

  -- 3. Rates and costs.
  if not public.user_can(v_feature, 'see_rates', p_company, p_location) then
    v_hidden := v_hidden || array(select f.name from erp_field f
                                  where f.entity_key in (select p_entity union select key from erp_entity where parent_key = p_entity)
                                    and f.sensitive = 'rates');
  end if;
  if not public.user_can(v_feature, 'see_cost', p_company, p_location) then
    v_hidden := v_hidden || array(select f.name from erp_field f
                                  where f.entity_key in (select p_entity union select key from erp_entity where parent_key = p_entity)
                                    and f.sensitive = 'cost');
  end if;
  return v_hidden;
end;
$$;

-- Locations of a company where the user may do an action on a feature. Null = company-level records allowed too.
create function public.erp_allowed_locations(p_feature text, p_action text, p_company uuid)
returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(l.id), '{}') from location l
  where l.company_id = p_company and public.user_can(p_feature, p_action, p_company, l.id)
$$;

-- ---------------------------------------------------------------------------
-- Catalogue for the app: entities the user can open in this company, with visible fields.
-- ---------------------------------------------------------------------------

create function public.erp_catalog(p_company uuid, p_location uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v jsonb;
begin
  with feats as (select * from public.resolved_features(p_company, p_location)),
  ents as (
    select e.*, f.state,
           public.user_can(e.feature_key, 'view', p_company, p_location)
             or exists (select 1 from location l where l.company_id = p_company
                        and public.user_can(e.feature_key, 'view', p_company, l.id)) as can_view
    from erp_entity e join feats f on f.feature_key = e.feature_key
    where e.parent_key is null and f.state in ('on', 'read_only')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', e.key, 'module', e.module, 'feature', e.feature_key, 'label', e.label, 'label_plural', e.label_plural,
    'kind', e.kind, 'scope', e.scope, 'numbering', e.numbering is not null, 'workflow', e.workflow, 'dated', e.dated,
    'title_field', e.title_field, 'amount_field', e.amount_field, 'mobile', e.mobile, 'icon', e.icon,
    'description', e.description, 'read_only', e.state = 'read_only',
    'can', jsonb_build_object(
      'create', e.state = 'on' and (public.user_can(e.feature_key, 'create', p_company, p_location)
                or exists (select 1 from location l where l.company_id = p_company and public.user_can(e.feature_key, 'create', p_company, l.id))),
      'approve', public.user_can(e.feature_key, 'approve', p_company, p_location)),
    'fields', public.erp_visible_fields(e.key, p_company, p_location),
    'children', (select coalesce(jsonb_agg(jsonb_build_object('key', c.key, 'name', c.child_name, 'label', c.label,
                                  'fields', public.erp_visible_fields(c.key, p_company, p_location)) order by c.sort), '[]')
                 from erp_entity c where c.parent_key = e.key)
  ) order by e.sort), '[]') into v
  from ents e where e.can_view;
  return v;
end;
$$;

create function public.erp_visible_fields(p_entity text, p_company uuid, p_location uuid default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', f.name, 'label', f.label, 'type', f.type, 'required', f.required, 'options', f.options, 'ref', f.ref,
    'computed', f.computed, 'quick', f.quick, 'in_list', f.in_list, 'unit', f.unit, 'help', f.help,
    'section', f.section, 'default', f.default_value) order by f.sort), '[]')
  from erp_field f
  where f.entity_key = p_entity
    and not f.name = any(public.erp_hidden_fields(coalesce((select parent_key from erp_entity where key = p_entity), p_entity),
                                                  p_company, p_location))
$$;

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

create function public.erp_entity_row(p_entity text) returns public.erp_entity
language plpgsql stable security definer set search_path = public as $$
declare
  e erp_entity;
begin
  select * into e from erp_entity where key = p_entity;
  if not found then
    raise exception 'unknown record type %', p_entity using errcode = 'P0002';
  end if;
  return e;
end;
$$;

create function public.erp_writable_columns(p_table text) returns text[]
language sql stable as $$
  select array_agg(a.attname::text order by a.attnum)
  from pg_attribute a
  where a.attrelid = ('public.' || quote_ident(p_table))::regclass
    and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
    and a.attname not in ('tenant_id', 'created_by', 'created_at', 'updated_by', 'updated_at', 'status',
                          'submitted_at', 'approved_at', 'approval_request_id', 'posted')
$$;

create function public.erp_mask(p_row jsonb, p_hidden text[]) returns jsonb
language sql immutable as $$
  select coalesce(p_row, '{}'::jsonb) - coalesce(p_hidden, '{}'::text[])
$$;

-- ---------------------------------------------------------------------------
-- Read
-- ---------------------------------------------------------------------------

create function public.erp_list(
  p_entity   text,
  p_company  uuid,
  p_location uuid default null,
  p_filters  jsonb default '{}',
  p_search   text default null,
  p_limit    integer default 50,
  p_offset   integer default 0
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  e        erp_entity := public.erp_entity_row(p_entity);
  v_locs   uuid[];
  v_co_ok  boolean;
  v_hidden text[];
  v_where  text := '';
  v_k      text;
  v_v      jsonb;
  v_rows   jsonb;
  v_total  bigint;
  v_order  text;
begin
  if e.parent_key is not null then
    raise exception 'line records are read through their parent';
  end if;
  v_locs := public.erp_allowed_locations(e.feature_key, 'view', p_company);
  v_co_ok := public.user_can(e.feature_key, 'view', p_company, null);
  if not v_co_ok and cardinality(v_locs) = 0 then
    raise exception 'This module is not enabled for your company or your account.' using errcode = '42501';
  end if;
  if p_location is not null then
    if not (p_location = any(v_locs)) then
      raise exception 'This module is not enabled for this location or your account.' using errcode = '42501';
    end if;
    v_locs := array[p_location];
    v_co_ok := false;
  end if;
  v_hidden := public.erp_hidden_fields(p_entity, p_company, p_location);

  for v_k, v_v in select * from jsonb_each(coalesce(p_filters, '{}')) loop
    if v_k = 'date_from' and e.dated then
      v_where := v_where || format(' and t.doc_date >= %L::date', v_v #>> '{}');
    elsif v_k = 'date_to' and e.dated then
      v_where := v_where || format(' and t.doc_date <= %L::date', v_v #>> '{}');
    elsif v_k = any(public.erp_writable_columns(e.table_name) || array['status', 'created_by'])
          and not v_k = any(v_hidden) then
      v_where := v_where || format(' and t.%I::text = %L', v_k, v_v #>> '{}');
    end if;
  end loop;
  if coalesce(trim(p_search), '') <> '' then
    v_where := v_where || format(' and to_jsonb(t)::text ilike %L', '%' || trim(p_search) || '%');
  end if;

  v_order := case when e.dated then 't.doc_date desc, t.created_at desc' else 't.created_at desc' end;

  execute format(
    'select coalesce(max(x.total), 0), coalesce(jsonb_agg(public.erp_mask(x.r, $3) order by x.n), ''[]'')
     from (select to_jsonb(t) as r, count(*) over () as total, row_number() over (order by %s) as n
           from public.%I t
           where t.company_id = $1 and (t.location_id = any($2) or (t.location_id is null and $4)) %s
           order by %s limit $5 offset $6) x',
    v_order, e.table_name, v_where, v_order)
  using p_company, v_locs, v_hidden, v_co_ok, least(greatest(p_limit, 1), 500), greatest(p_offset, 0)
  into v_total, v_rows;

  return jsonb_build_object('rows', v_rows, 'total', v_total, 'hidden', to_jsonb(v_hidden));
end;
$$;

create function public.erp_get(p_entity text, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  e        erp_entity := public.erp_entity_row(p_entity);
  c        erp_entity;
  v_row    jsonb;
  v_hidden text[];
  v_kids   jsonb;
  v_co     uuid;
  v_loc    uuid;
begin
  execute format('select to_jsonb(t) from public.%I t where t.id = $1', e.table_name) using p_id into v_row;
  if v_row is null then
    raise exception 'record not found' using errcode = 'P0002';
  end if;
  v_co := (v_row ->> 'company_id')::uuid;
  v_loc := (v_row ->> 'location_id')::uuid;
  if not public.user_can(e.feature_key, 'view', v_co, v_loc) then
    raise exception 'You do not have access to this record.' using errcode = '42501';
  end if;
  v_hidden := public.erp_hidden_fields(p_entity, v_co, v_loc);
  v_row := public.erp_mask(v_row, v_hidden);

  for c in select * from erp_entity where parent_key = p_entity order by sort loop
    execute format('select coalesce(jsonb_agg(public.erp_mask(to_jsonb(t) - ''tenant_id'', $2) order by t.line_no), ''[]'')
                    from public.%I t where t.parent_id = $1', c.table_name)
    using p_id, v_hidden into v_kids;
    v_row := v_row || jsonb_build_object(c.child_name, v_kids);
  end loop;

  return v_row || jsonb_build_object('_can', jsonb_build_object(
    'edit', public.user_can(e.feature_key, 'edit', v_co, v_loc)
            and (not e.workflow or v_row ->> 'status' = 'draft' or v_row ->> 'status' = 'sent_back'),
    'approve', public.user_can(e.feature_key, 'approve', v_co, v_loc),
    'cancel', e.workflow and v_row ->> 'status' not in ('cancelled')
              and (public.user_can(e.feature_key, 'approve', v_co, v_loc) or public.user_can(e.feature_key, 'delete', v_co, v_loc)),
    'delete', e.kind = 'master' and public.user_can(e.feature_key, 'delete', v_co, v_loc)));
end;
$$;

-- Lookup lists for reference fields (party, item, vehicle, user, location, or another entity).
create function public.erp_lookup(p_ref text, p_company uuid, p_search text default null, p_ids uuid[] default null,
                                  p_limit integer default 30)
returns table (id uuid, label text, sub text)
language plpgsql stable security definer set search_path = public as $$
declare
  e erp_entity;
  s text := '%' || coalesce(trim(p_search), '') || '%';
begin
  if p_company not in (select public.my_company_ids()) and not public.is_platform_admin() then
    return;
  end if;
  if p_ref = 'party' then
    return query select p.id, p.display_name, p.party_code from party p
      where p.tenant_id = public.auth_tenant_id() and (p_ids is null or p.id = any(p_ids))
        and (p.display_name ilike s or p.party_code ilike s or coalesce(p.mobile, '') ilike s)
      order by p.display_name limit p_limit;
  elsif p_ref = 'item' then
    return query select i.id, i.name, coalesce(i.local_name, i.item_code) from item i
      where i.tenant_id = public.auth_tenant_id() and (p_ids is null or i.id = any(p_ids))
        and (i.name ilike s or i.item_code ilike s or coalesce(i.local_name, '') ilike s)
      order by i.name limit p_limit;
  elsif p_ref = 'vehicle' then
    return query select v.id, v.reg_no, v.kind from vehicle v
      where v.tenant_id = public.auth_tenant_id() and (p_ids is null or v.id = any(p_ids)) and v.reg_no ilike s
      order by v.reg_no limit p_limit;
  elsif p_ref = 'app_user' then
    return query select u.id, u.full_name, u.mobile from app_user u
      where u.tenant_id = public.auth_tenant_id() and (p_ids is null or u.id = any(p_ids)) and u.full_name ilike s
      order by u.full_name limit p_limit;
  elsif p_ref = 'location' then
    return query select l.id, l.name, l.type::text from location l
      where l.company_id = p_company and (p_ids is null or l.id = any(p_ids)) and l.name ilike s
      order by l.name limit p_limit;
  elsif p_ref = 'company' then
    return query select c.id, c.legal_name, c.short_code from company c
      where c.tenant_id = public.auth_tenant_id() and (p_ids is null or c.id = any(p_ids)) and c.legal_name ilike s
      order by c.legal_name limit p_limit;
  else
    -- Masters (tanks, nozzles, projects, BOQ items...) can be picked by anyone in the company;
    -- other records only by people who can view them.
    select * into e from erp_entity where key = p_ref;
    if not found or (e.kind <> 'master'
                     and not exists (select 1 from location l where l.company_id = p_company
                                     and public.user_can(e.feature_key, 'view', p_company, l.id))
                     and not public.user_can(e.feature_key, 'view', p_company, null)) then
      return;
    end if;
    return query execute format(
      'select t.id, coalesce(%s, t.id::text), %s from public.%I t
       where t.company_id = $1 and ($2::uuid[] is null or t.id = any($2)) and coalesce(%s, '''') ilike $3
       order by 2 limit $4',
      case when e.title_field is null then 'null::text' else 't.' || quote_ident(e.title_field) || '::text' end,
      case when e.numbering is not null then 't.doc_no' else 'null::text' end,
      e.table_name,
      case when e.title_field is null then 't.id::text' else 't.' || quote_ident(e.title_field) || '::text' end)
    using p_company, p_ids, s, p_limit;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Write
-- ---------------------------------------------------------------------------

create function public.erp_write_row(p_table text, p_data jsonb, p_cols text[], p_id uuid, p_insert boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cols text[] := array(select c from unnest(p_cols) c where p_data ? c or c in ('tenant_id', 'id'));
  v_list text;
begin
  if p_insert then
    v_list := (select string_agg(quote_ident(c), ', ') from unnest(v_cols) c);
    execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1)',
                   p_table, v_list, v_list, p_table) using p_data;
  else
    v_cols := array(select c from unnest(v_cols) c where c not in ('id', 'tenant_id', 'company_id'));
    v_list := (select string_agg(quote_ident(c), ', ') from unnest(v_cols) c);
    if v_list is null then return; end if;
    execute format('update public.%I t set (%s) = (select %s from jsonb_populate_record(t, $1)) where t.id = $2',
                   p_table, v_list || ', updated_by, updated_at', v_list || ', auth.uid(), now()', p_table)
    using p_data, p_id;
  end if;
end;
$$;

create function public.erp_save(p_entity text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  e          erp_entity := public.erp_entity_row(p_entity);
  c          erp_entity;
  v_id       uuid := coalesce((p_data ->> 'id')::uuid, gen_random_uuid());
  v_old      jsonb;
  v_insert   boolean;
  v_co       uuid;
  v_loc      uuid;
  v_hidden   text[];
  v_cols     text[];
  v_data     jsonb;
  v_missing  text;
  v_line     jsonb;
  v_n        integer;
  v_line_cols text[];
  v_def      record;
begin
  if e.parent_key is not null then
    raise exception 'line records are saved with their parent';
  end if;

  execute format('select to_jsonb(t) from public.%I t where t.id = $1', e.table_name) using v_id into v_old;
  v_insert := v_old is null;

  v_co  := coalesce((v_old ->> 'company_id')::uuid, (p_data ->> 'company_id')::uuid);
  v_loc := case when v_insert then (p_data ->> 'location_id')::uuid
                else coalesce((p_data ->> 'location_id')::uuid, (v_old ->> 'location_id')::uuid) end;
  if v_co is null then
    raise exception 'Choose a company first.';
  end if;
  if e.scope = 'location' and v_loc is null then
    raise exception 'Choose a location (plant, site, bunk...) first.';
  end if;
  if v_loc is not null and not exists (select 1 from location l where l.id = v_loc and l.company_id = v_co) then
    raise exception 'That location does not belong to this company.';
  end if;

  if not public.user_can(e.feature_key, case when v_insert then 'create' else 'edit' end, v_co, v_loc) then
    raise exception 'You are not allowed to % %.', case when v_insert then 'add' else 'change' end, lower(e.label_plural)
      using errcode = '42501';
  end if;
  if not v_insert and e.workflow and v_old ->> 'status' not in ('draft', 'sent_back')
     and not public.user_can(e.feature_key, 'approve', v_co, v_loc) then
    raise exception 'This % is % and can no longer be changed.', lower(e.label), v_old ->> 'status' using errcode = '42501';
  end if;
  if not v_insert and e.workflow and v_old ->> 'status' not in ('draft', 'sent_back')
     and coalesce(audit.ctx('reason'), p_data ->> '_reason', '') = '' then
    raise exception 'Give a reason for changing a % that is already %.', lower(e.label), v_old ->> 'status';
  end if;
  if not v_insert and (v_old ->> 'company_id')::uuid is distinct from (coalesce(p_data ->> 'company_id', v_old ->> 'company_id'))::uuid then
    raise exception 'A record cannot be moved to another company.';
  end if;
  if coalesce(p_data ->> '_reason', '') <> '' then
    perform set_config('app.reason', p_data ->> '_reason', true);
  end if;

  v_hidden := public.erp_hidden_fields(p_entity, v_co, v_loc);
  v_cols := array(select c2 from unnest(public.erp_writable_columns(e.table_name)) c2 where not c2 = any(v_hidden));

  v_data := (p_data - v_hidden) || jsonb_build_object('id', v_id, 'company_id', v_co, 'location_id', v_loc,
                                                     'tenant_id', (select tenant_id from company where id = v_co));
  if e.numbering is not null and not v_insert then
    v_data := v_data - 'doc_no';
  end if;

  if v_insert then
    -- required fields, in plain words
    select string_agg(f.label, ', ' order by f.sort) into v_missing
    from erp_field f
    where f.entity_key = p_entity and f.required and not f.computed and not f.name = any(v_hidden)
      and coalesce(v_data ->> f.name, '') = '' and f.default_value is null;
    if v_missing is not null then
      raise exception 'Please fill: %', v_missing;
    end if;

    for v_def in select f.name, f.default_value from erp_field f
                 where f.entity_key = p_entity and f.default_value is not null and not (v_data ? f.name)
                   and not f.name = any(v_hidden) loop
      v_data := v_data || jsonb_build_object(v_def.name, v_def.default_value);
    end loop;

    if e.numbering is not null and coalesce(v_data ->> 'doc_no', '') = '' then
      perform public.erp_ensure_series(e, v_co);
      v_data := v_data || jsonb_build_object('doc_no',
        public.next_doc_number(v_co, v_loc, e.key, coalesce((v_data ->> 'doc_date')::date, current_date)));
    end if;
    perform public.erp_write_row(e.table_name, v_data, v_cols || array['tenant_id'], v_id, true);
  else
    perform public.erp_write_row(e.table_name, v_data, v_cols, v_id, false);
  end if;

  -- lines: replaced as a whole when sent
  for c in select * from erp_entity where parent_key = p_entity loop
    if p_data ? c.child_name then
      execute format('delete from public.%I where parent_id = $1', c.table_name) using v_id;
      v_line_cols := array(select c2 from unnest(public.erp_writable_columns(c.table_name)) c2 where not c2 = any(v_hidden));
      v_n := 0;
      for v_line in select * from jsonb_array_elements(p_data -> c.child_name) loop
        v_n := v_n + 1;
        select string_agg(f.label, ', ' order by f.sort) into v_missing
        from erp_field f
        where f.entity_key = c.key and f.required and not f.computed and not f.name = any(v_hidden)
          and coalesce(v_line ->> f.name, '') = '';
        if v_missing is not null then
          raise exception 'Line %: please fill %', v_n, v_missing;
        end if;
        perform public.erp_write_row(c.table_name,
          (v_line - v_hidden) || jsonb_build_object('id', gen_random_uuid(), 'parent_id', v_id, 'line_no', v_n,
                                                    'tenant_id', v_data ->> 'tenant_id'),
          v_line_cols || array['tenant_id'], null, true);
      end loop;
      -- let the parent recompute totals from its lines
      execute format('update public.%I set updated_at = now() where id = $1', e.table_name) using v_id;
    end if;
  end loop;

  return public.erp_get(p_entity, v_id);
end;
$$;

-- Company-wide number series for an entity, created from its pattern the first time it is used.
create function public.erp_ensure_series(e public.erp_entity, p_company uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into number_series (tenant_id, company_id, location_id, doc_type, pattern, fy, max_length)
  select c.tenant_id, c.id, null, e.key, e.numbering, public.financial_year(current_date, t.fy_start_month),
         case when e.key in ('finance.sales_invoice', 'finance.purchase_invoice') then 16 else 24 end
  from company c join tenant t on t.id = c.tenant_id
  where c.id = p_company
    and not exists (select 1 from number_series s where s.company_id = p_company and s.doc_type = e.key)
  on conflict do nothing;
end;
$$;

-- Numbering checks the entity's feature, not the entity key.
create or replace function public.next_doc_number(p_company uuid, p_location uuid, p_doc_type text, p_date date default current_date)
returns text
language plpgsql security definer set search_path = public as $$
declare
  s     number_series;
  v_co  text;
  v_loc text;
  v_num text;
begin
  if not public.user_can(coalesce((select feature_key from erp_entity where key = p_doc_type), p_doc_type),
                         'create', p_company, p_location) then
    raise exception 'not allowed to create % here', p_doc_type using errcode = '42501';
  end if;
  s := public.get_series(p_company, p_location, p_doc_type, p_date);
  select short_code into v_co from company where id = p_company;
  select short_code into v_loc from location where id = p_location;
  v_num := public.format_doc_number(s.pattern, v_co, v_loc, s.fy, s.next_value);
  if length(v_num) > s.max_length then
    raise exception 'document number % is longer than % characters; shorten the pattern', v_num, s.max_length;
  end if;
  update number_series set next_value = next_value + 1 where id = s.id;
  return v_num;
end;
$$;

create or replace function public.reserve_number_block(
  p_company uuid, p_location uuid, p_doc_type text, p_device_id text, p_count int default 50
) returns table (series_id uuid, pattern text, company_code text, location_code text, fy text,
                 from_value bigint, to_value bigint)
language plpgsql security definer set search_path = public as $$
declare
  s number_series;
  e erp_entity;
begin
  if p_count not between 1 and 500 then
    raise exception 'block size must be between 1 and 500';
  end if;
  if not public.user_can(coalesce((select feature_key from erp_entity where key = p_doc_type), p_doc_type),
                         'create', p_company, p_location) then
    raise exception 'not allowed to create % here', p_doc_type using errcode = '42501';
  end if;
  select * into e from erp_entity where key = p_doc_type;
  if found then
    perform public.erp_ensure_series(e, p_company);
  end if;
  s := public.get_series(p_company, p_location, p_doc_type, current_date);
  update number_series set next_value = next_value + p_count where id = s.id;
  insert into number_block (tenant_id, series_id, device_id, from_value, to_value)
  values (s.tenant_id, s.id, p_device_id, s.next_value, s.next_value + p_count - 1);
  return query
  select s.id, s.pattern, (select short_code from company where id = p_company),
         (select short_code from location where id = p_location), s.fy,
         s.next_value, s.next_value + p_count - 1;
end;
$$;

-- Approvals check the entity's feature too.
create or replace function public.submit_for_approval(
  p_doc_type text, p_doc_id uuid, p_company uuid, p_location uuid, p_summary jsonb, p_source text default 'web'
) returns public.approval_request
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid := public.auth_tenant_id();
  v_rule   approval_rule;
  v_req    approval_request;
begin
  if not public.user_can(coalesce((select feature_key from erp_entity where key = p_doc_type), p_doc_type),
                         'create', p_company, p_location) then
    raise exception 'not allowed to submit % for approval', p_doc_type using errcode = '42501';
  end if;

  v_rule := public.match_approval_rule(v_tenant, p_company, p_doc_type, p_summary);

  insert into approval_request (tenant_id, company_id, location_id, doc_type, doc_id, summary, rule_id, current_step, status, decided_at)
  values (v_tenant, p_company, p_location, p_doc_type, p_doc_id, p_summary, v_rule.id,
          case when v_rule.id is null then null else 1 end,
          case when v_rule.id is null then 'approved' else 'pending' end,
          case when v_rule.id is null then now() end)
  returning * into v_req;

  insert into approval_action (tenant_id, request_id, step_no, action, source, comment)
  values (v_tenant, v_req.id, null, case when v_rule.id is null then 'auto_approve' else 'submit' end, p_source,
          case when v_rule.id is null then 'no approval rule matched' end);

  return v_req;
end;
$$;

-- ---------------------------------------------------------------------------
-- Workflow: submit, cancel. Approval decisions come back through the trigger below.
-- ---------------------------------------------------------------------------

create function public.erp_set_status(p_entity text, p_id uuid, p_action text, p_reason text default null,
                                      p_source text default 'web')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  e      erp_entity := public.erp_entity_row(p_entity);
  v_row  jsonb;
  v_co   uuid;
  v_loc  uuid;
  v_req  approval_request;
  v_new  text;
begin
  if not e.workflow then
    raise exception '% records have no approval workflow', e.label;
  end if;
  execute format('select to_jsonb(t) from public.%I t where t.id = $1 for update', e.table_name) using p_id into v_row;
  if v_row is null then
    raise exception 'record not found' using errcode = 'P0002';
  end if;
  v_co := (v_row ->> 'company_id')::uuid;
  v_loc := (v_row ->> 'location_id')::uuid;
  perform set_config('app.reason', coalesce(p_reason, ''), true);

  if p_action = 'submit' then
    if v_row ->> 'status' not in ('draft', 'sent_back') then
      raise exception 'Only drafts can be submitted (this one is %).', v_row ->> 'status';
    end if;
    if not public.user_can(e.feature_key, 'create', v_co, v_loc) then
      raise exception 'You are not allowed to submit %.', lower(e.label_plural) using errcode = '42501';
    end if;
    if e.submit_hook is not null then
      execute format('select public.%I($1)', e.submit_hook) using p_id;
      execute format('select to_jsonb(t) from public.%I t where t.id = $1', e.table_name) using p_id into v_row;
    end if;
    -- a sent-back request is closed; a fresh one is opened
    v_req := public.submit_for_approval(e.key, p_id, v_co, v_loc,
               (v_row - 'id') || jsonb_build_object('title', e.label || ' ' || coalesce(v_row ->> 'doc_no', ''),
                                  'amount', case when e.amount_field is not null then v_row -> e.amount_field end,
                                  'entity', e.key), p_source);
    v_new := case when v_req.status = 'approved' then 'approved' else 'submitted' end;
    execute format('update public.%I set status = $2, submitted_at = now(), approval_request_id = $3,
                    approved_at = case when $2 = ''approved'' then now() end where id = $1', e.table_name)
    using p_id, v_new, v_req.id;
  elsif p_action = 'cancel' then
    if v_row ->> 'status' = 'cancelled' then
      raise exception 'Already cancelled.';
    end if;
    if not (public.user_can(e.feature_key, 'approve', v_co, v_loc) or public.user_can(e.feature_key, 'delete', v_co, v_loc)
            or (v_row ->> 'status' = 'draft' and (v_row ->> 'created_by')::uuid = auth.uid())) then
      raise exception 'You are not allowed to cancel %.', lower(e.label_plural) using errcode = '42501';
    end if;
    if coalesce(trim(p_reason), '') = '' then
      raise exception 'Give a reason for cancelling.';
    end if;
    update approval_request set status = 'cancelled', decided_at = now()
    where doc_type = e.key and doc_id = p_id and status = 'pending';
    execute format('update public.%I set status = ''cancelled'' where id = $1', e.table_name) using p_id;
  else
    raise exception 'unknown action %', p_action;
  end if;
  return public.erp_get(p_entity, p_id);
end;
$$;

-- When an approval request for a module record is decided, the record follows.
create function public.erp_on_approval_decided() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e erp_entity;
begin
  if new.status = old.status or new.status = 'pending' then
    return null;
  end if;
  select * into e from erp_entity where key = new.doc_type;
  if not found or not e.workflow then
    return null;
  end if;
  execute format('update public.%I set status = $2, approved_at = case when $2 = ''approved'' then now() end
                  where id = $1 and approval_request_id = $3 and status = ''submitted''', e.table_name)
  using new.doc_id, case new.status when 'approved' then 'approved' when 'rejected' then 'rejected'
                                    when 'sent_back' then 'sent_back' else 'cancelled' end, new.id;
  return null;
end;
$$;
create trigger erp_follow_approval after update of status on public.approval_request
  for each row execute function public.erp_on_approval_decided();

create function public.erp_delete(p_entity text, p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  e     erp_entity := public.erp_entity_row(p_entity);
  v_row jsonb;
begin
  if e.kind <> 'master' then
    raise exception '% records are cancelled, not deleted.', e.label;
  end if;
  execute format('select to_jsonb(t) from public.%I t where t.id = $1', e.table_name) using p_id into v_row;
  if v_row is null then
    raise exception 'record not found' using errcode = 'P0002';
  end if;
  if not public.user_can(e.feature_key, 'delete', (v_row ->> 'company_id')::uuid, (v_row ->> 'location_id')::uuid) then
    raise exception 'You are not allowed to delete %.', lower(e.label_plural) using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Give a reason for deleting.';
  end if;
  perform set_config('app.reason', p_reason, true);
  execute format('delete from public.%I where id = $1', e.table_name) using p_id;
exception when foreign_key_violation then
  raise exception 'This % is used in other records; mark it inactive instead.', lower(e.label);
end;
$$;

-- Common trigger: keep updated_at fresh.
create function public.erp_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- App users never touch module tables directly.
revoke execute on function public.erp_write_row(text, jsonb, text[], uuid, boolean) from public, anon, authenticated;
