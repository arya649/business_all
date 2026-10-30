-- Speed: a screen asks "may this person do X here?" hundreds of times. The resolved switch tree for
-- (user, company, location) is now worked out once per request and reused. Any change to switches, roles
-- or assignments in the same transaction moves a generation counter, so a stale answer is never used.

create function public.rf_cache_key(p_company uuid, p_location uuid) returns text
language sql stable as $$
  select 'erp.rf_' || md5(coalesce(auth.uid()::text, 'system') || '|' || p_company || '|' || coalesce(p_location::text, '-')
                          || '|' || coalesce(nullif(current_setting('erp.rf_gen', true), ''), '0'))
$$;

create function public.resolved_map(p_company uuid, p_location uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  k text := public.rf_cache_key(p_company, p_location);
  m jsonb := nullif(current_setting(k, true), '')::jsonb;
begin
  if m is null then
    select coalesce(jsonb_object_agg(feature_key, jsonb_build_object('s', state, 'c', config)), '{}') into m
    from public.resolved_features(p_company, p_location);
    perform set_config(k, m::text, true);
  end if;
  return m;
end;
$$;

create or replace function public.feature_state_of(p_feature text, p_company uuid, p_location uuid default null)
returns public.feature_state
language sql stable security definer set search_path = public as $$
  select coalesce((public.resolved_map(p_company, p_location) -> p_feature ->> 's')::feature_state, 'off')
$$;

create function public.feature_config_of(p_feature text, p_company uuid, p_location uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(public.resolved_map(p_company, p_location) -> p_feature -> 'c', '{}')
$$;

create function public.rf_bump() returns trigger
language plpgsql as $$
begin
  perform set_config('erp.rf_gen', (coalesce(nullif(current_setting('erp.rf_gen', true), ''), '0')::int + 1)::text, true);
  return null;
end;
$$;
create trigger rf_bump after insert or update or delete on public.feature_flag for each statement execute function public.rf_bump();
create trigger rf_bump after insert or update or delete on public.role_permission for each statement execute function public.rf_bump();
create trigger rf_bump after insert or update or delete on public.user_assignment for each statement execute function public.rf_bump();
create trigger rf_bump after insert or update or delete on public.app_user for each statement execute function public.rf_bump();

-- Field visibility uses the cached tree for its switch config.
create or replace function public.erp_hidden_fields(p_entity text, p_company uuid, p_location uuid default null)
returns text[]
language plpgsql stable security definer set search_path = public as $$
declare
  v_feature text;
  v_hidden  text[] := '{}';
  v_cfg     jsonb;
begin
  select feature_key into v_feature from erp_entity where key = p_entity;
  v_cfg := public.feature_config_of(v_feature, p_company, p_location);
  if v_cfg ? 'hidden_fields' then
    v_hidden := v_hidden || array(select jsonb_array_elements_text(v_cfg -> 'hidden_fields'));
  end if;
  if public.is_tenant_admin() then
    return v_hidden;
  end if;
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

-- Catalogue: one pass, with each entity's fields worked out once.
create or replace function public.erp_catalog(p_company uuid, p_location uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v jsonb;
  v_locs uuid[] := array(select id from location where company_id = p_company and (p_location is null or id = p_location));
begin
  with ents as (
    select e.*, (public.resolved_map(p_company, p_location) -> e.feature_key ->> 's') as state
    from erp_entity e where e.parent_key is null
  ),
  ok as (
    select e.*,
           public.user_can(e.feature_key, 'view', p_company, p_location)
             or exists (select 1 from unnest(v_locs) l(id) where public.user_can(e.feature_key, 'view', p_company, l.id)) as can_view,
           e.state = 'on' and (public.user_can(e.feature_key, 'create', p_company, p_location)
             or exists (select 1 from unnest(v_locs) l(id) where public.user_can(e.feature_key, 'create', p_company, l.id))) as can_create
    from ents e where e.state in ('on', 'read_only')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', e.key, 'module', e.module, 'feature', e.feature_key, 'label', e.label, 'label_plural', e.label_plural,
    'kind', e.kind, 'scope', e.scope, 'numbering', e.numbering is not null, 'workflow', e.workflow, 'dated', e.dated,
    'title_field', e.title_field, 'amount_field', e.amount_field, 'mobile', e.mobile, 'icon', e.icon,
    'description', e.description, 'read_only', e.state = 'read_only',
    'can', jsonb_build_object('create', e.can_create, 'approve', public.user_can(e.feature_key, 'approve', p_company, p_location)),
    'fields', public.erp_visible_fields(e.key, p_company, p_location),
    'children', (select coalesce(jsonb_agg(jsonb_build_object('key', c.key, 'name', c.child_name, 'label', c.label,
                                  'fields', public.erp_visible_fields(c.key, p_company, p_location)) order by c.sort), '[]')
                 from erp_entity c where c.parent_key = e.key)
  ) order by e.sort), '[]') into v
  from ok e where e.can_view;
  return v;
end;
$$;


-- Permissions for (user, company, location) are also worked out once per request.
create or replace function public.user_can(
  p_feature  text,
  p_action   text,
  p_company  uuid,
  p_location uuid default null
) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  k text;
  m jsonb;
  v_state feature_state;
begin
  if p_company is null or auth.uid() is null then
    return false;
  end if;
  k := 'erp.pm_' || substr(public.rf_cache_key(p_company, p_location), 8);
  m := nullif(current_setting(k, true), '')::jsonb;
  if m is null then
    m := jsonb_build_object(
      'tenant_ok', public.is_platform_admin()
                   or exists (select 1 from company c where c.id = p_company and c.tenant_id = public.auth_tenant_id()),
      'admin', public.is_tenant_admin(),
      'perms', coalesce((
        select jsonb_object_agg(x.feature_key, x.acts) from (
          select rp.feature_key, jsonb_agg(distinct act) as acts
          from public.my_assignments() a
          join role_permission rp on rp.role_id = a.role_id
          cross join unnest(rp.actions) act
          where a.company_id = p_company
            and (a.location_id is null or a.location_id = p_location
                 or a.location_id = (select l.parent_id from location l where l.id = p_location))
          group by rp.feature_key) x), '{}'));
    perform set_config(k, m::text, true);
  end if;

  if not (m ->> 'tenant_ok')::boolean then
    return false;
  end if;
  v_state := public.feature_state_of(p_feature, p_company, p_location);
  if v_state in ('off', 'hidden') then
    return false;
  end if;
  if v_state = 'read_only' and p_action not in ('view', 'export', 'print') then
    return false;
  end if;
  if (m ->> 'admin')::boolean then
    return true;
  end if;
  return exists (select 1 from jsonb_each(m -> 'perms') e(key, acts)
                 where (p_feature = e.key or p_feature like e.key || '.%') and e.acts ? p_action);
end;
$$;

-- Admin "preview as": the screens a given person would get here, with switches and their roles both applied.
-- Runs the real catalogue as that person for the length of this call only.
create function public.preview_screens(p_user uuid, p_company uuid, p_location uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me text := current_setting('request.jwt.claims', true);
  v jsonb;
begin
  if not public.is_tenant_admin()
     or not exists (select 1 from app_user u where u.id = p_user and u.tenant_id = public.auth_tenant_id()) then
    raise exception 'only admins can preview their own people' using errcode = '42501';
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('erp.rf_gen', 'preview' || p_user::text, true);
  begin
    select coalesce(jsonb_agg(jsonb_build_object('key', e ->> 'key', 'label', e ->> 'label_plural', 'read_only', e -> 'read_only',
                                                 'can_create', e -> 'can' -> 'create', 'fields', jsonb_array_length(e -> 'fields'))), '[]')
      into v from jsonb_array_elements(public.erp_catalog(p_company, p_location)) e;
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_me, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_me, ''), true);
  perform set_config('erp.rf_gen', '', true);
  return v;
end;
$$;
