-- Audit log: who changed what, when, from where, and why.
--
-- * Every tracked table gets a trigger that records the full before/after row.
-- * Business events that are not row changes (approve, print, export, login, AI tool call)
--   go through audit.log_event().
-- * Each tenant has its own hash chain: hash = sha256(prev_hash || canonical record).
--   Editing, deleting or reordering any record breaks the chain, which audit.verify_chain() reports.
--   Anchor audit.chain_head externally (e.g. to the Zentrix ADK audit storage) on a schedule so a
--   truncated tail is detectable too.
-- * The log is append-only: UPDATE / DELETE / TRUNCATE are refused for every role.
--
-- Request context comes from PostgREST request headers (x-source, x-device-id, x-correlation-id,
-- x-reason, x-on-behalf-of, x-geo) or, for server-side code, from the app.* settings.

create schema if not exists audit;

create table audit.chain_head (
  chain_key uuid primary key,          -- tenant id; the zero uuid for platform-level records
  seq       bigint not null,
  hash      bytea not null,
  updated_at timestamptz not null default now()
);

create table audit.log (
  id             bigint generated always as identity primary key,
  tenant_id      uuid,
  seq            bigint not null,
  occurred_at    timestamptz not null default clock_timestamp(),
  table_name     text not null,
  record_id      text,
  action         text not null,       -- INSERT / UPDATE / DELETE, or an event name like approval.approved
  actor_id       uuid,
  actor_type     text not null,       -- user / service / ai_agent / hardware / system
  on_behalf_of   uuid,                -- the user an AI agent or device acted for
  source         text,                -- web / mobile / api / ai / hardware / sync / system
  device_id      text,
  ip             text,
  geo            text,                -- "lat,lng" from the device
  correlation_id text,
  reason         text,
  changed_fields text[],
  old_data       jsonb,
  new_data       jsonb,
  prev_hash      bytea not null,
  hash           bytea not null,
  unique (tenant_id, seq)
);
create index on audit.log (tenant_id, table_name, record_id);
create index on audit.log (tenant_id, actor_id, occurred_at desc);
create index on audit.log (correlation_id) where correlation_id is not null;

-- ---------------------------------------------------------------------------
-- Context
-- ---------------------------------------------------------------------------

create function audit.ctx(p_name text) returns text
language sql stable as $$
  select coalesce(
    nullif(current_setting('app.' || replace(p_name, '-', '_'), true), ''),
    nullif((nullif(current_setting('request.headers', true), '')::jsonb) ->> ('x-' || p_name), '')
  )
$$;

-- Values that say who acted (actor type, on-behalf-of) are trusted only from server-side code,
-- never from request headers a client could forge.
create function audit.server_ctx(p_name text) returns text
language sql stable as $$
  select nullif(current_setting('app.' || replace(p_name, '-', '_'), true), '')
$$;

-- For server-side code (edge functions, workers, hardware gateway) inside one transaction.
create function audit.set_context(
  p_source text default null, p_reason text default null, p_correlation_id text default null,
  p_device_id text default null, p_on_behalf_of uuid default null, p_actor_type text default null
) returns void
language sql as $$
  select set_config('app.source', coalesce(p_source, ''), true),
         set_config('app.reason', coalesce(p_reason, ''), true),
         set_config('app.correlation_id', coalesce(p_correlation_id, ''), true),
         set_config('app.device_id', coalesce(p_device_id, ''), true),
         set_config('app.on_behalf_of', coalesce(p_on_behalf_of::text, ''), true),
         set_config('app.actor_type', coalesce(p_actor_type, ''), true);
$$;

-- ---------------------------------------------------------------------------
-- Hashing
-- ---------------------------------------------------------------------------

create function audit.record_digest(
  p_prev bytea, p_tenant uuid, p_seq bigint, p_at timestamptz, p_table text, p_record text,
  p_action text, p_actor uuid, p_actor_type text, p_on_behalf uuid, p_source text, p_device text,
  p_ip text, p_geo text, p_corr text, p_reason text, p_fields text[], p_old jsonb, p_new jsonb
) returns bytea
language sql immutable as $$
  select extensions.digest(
    p_prev || convert_to(concat_ws(chr(31),
      coalesce(p_tenant::text, ''), p_seq::text,
      to_char(p_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'),
      p_table, coalesce(p_record, ''), p_action,
      coalesce(p_actor::text, ''), p_actor_type, coalesce(p_on_behalf::text, ''),
      coalesce(p_source, ''), coalesce(p_device, ''), coalesce(p_ip, ''), coalesce(p_geo, ''),
      coalesce(p_corr, ''), coalesce(p_reason, ''),
      coalesce(array_to_string(p_fields, ','), ''),
      coalesce(p_old::text, ''), coalesce(p_new::text, '')), 'UTF8'),
    'sha256')
$$;

-- The single writer. Serialises per tenant by locking that tenant's chain head row.
create function audit.append(
  p_tenant uuid, p_table text, p_record text, p_action text,
  p_old jsonb, p_new jsonb, p_fields text[] default null, p_reason text default null
) returns bigint
language plpgsql security definer set search_path = audit, public as $$
declare
  v_key   uuid := coalesce(p_tenant, '00000000-0000-0000-0000-000000000000');
  v_seq   bigint;
  v_prev  bytea;
  v_at    timestamptz := clock_timestamp();
  v_actor uuid := auth.uid();
  v_actor_type text := coalesce(audit.server_ctx('actor-type'),
                         case when auth.uid() is null then 'system' else 'user' end);
  v_behalf uuid := audit.server_ctx('on-behalf-of')::uuid;
  v_source text := audit.ctx('source');
  v_device text := audit.ctx('device-id');
  v_ip     text := audit.ctx('forwarded-for');
  v_geo    text := audit.ctx('geo');
  v_corr   text := audit.ctx('correlation-id');
  v_reason text := coalesce(p_reason, audit.ctx('reason'));
  v_hash   bytea;
  v_id     bigint;
begin
  insert into audit.chain_head (chain_key, seq, hash) values (v_key, 0, '\x'::bytea)
  on conflict (chain_key) do nothing;

  select seq, hash into v_seq, v_prev from audit.chain_head where chain_key = v_key for update;
  v_seq := v_seq + 1;

  v_hash := audit.record_digest(v_prev, p_tenant, v_seq, v_at, p_table, p_record, p_action, v_actor,
              v_actor_type, v_behalf, v_source, v_device, v_ip, v_geo, v_corr, v_reason, p_fields, p_old, p_new);

  insert into audit.log (tenant_id, seq, occurred_at, table_name, record_id, action, actor_id, actor_type,
                         on_behalf_of, source, device_id, ip, geo, correlation_id, reason, changed_fields,
                         old_data, new_data, prev_hash, hash)
  values (p_tenant, v_seq, v_at, p_table, p_record, p_action, v_actor, v_actor_type,
          v_behalf, v_source, v_device, v_ip, v_geo, v_corr, v_reason, p_fields,
          p_old, p_new, v_prev, v_hash)
  returning id into v_id;

  update audit.chain_head set seq = v_seq, hash = v_hash, updated_at = now() where chain_key = v_key;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row-change trigger
-- ---------------------------------------------------------------------------

create function audit.capture() returns trigger
language plpgsql security definer set search_path = audit, public as $$
declare
  v_old    jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new    jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_row    jsonb := coalesce(v_new, v_old);
  v_tenant uuid;
  v_fields text[];
begin
  v_tenant := case
    when tg_table_name = 'tenant' then (v_row ->> 'id')::uuid
    else (v_row ->> 'tenant_id')::uuid
  end;

  if tg_op = 'UPDATE' then
    select array_agg(k order by k) into v_fields
    from jsonb_object_keys(v_new) k
    where v_new -> k is distinct from v_old -> k;
    if v_fields is null then
      return null;                         -- nothing actually changed
    end if;
  end if;

  perform audit.append(v_tenant, tg_table_schema || '.' || tg_table_name,
                       coalesce(v_row ->> 'id', v_row::text), tg_op, v_old, v_new, v_fields);
  return null;
end;
$$;

-- Turn on auditing for a table: select audit.track('public.party');
create function audit.track(p_table regclass) returns void
language plpgsql as $$
begin
  execute format('drop trigger if exists zz_audit on %s', p_table);
  execute format('create trigger zz_audit after insert or update or delete on %s
                  for each row execute function audit.capture()', p_table);
end;
$$;

-- Business events that are not row changes.
create function audit.log_event(
  p_action text, p_table text, p_record text, p_data jsonb default null, p_reason text default null,
  p_tenant uuid default null
) returns bigint
language plpgsql security definer set search_path = audit, public as $$
begin
  return audit.append(coalesce(p_tenant, public.auth_tenant_id()), p_table, p_record, p_action,
                      null, p_data, null, p_reason);
end;
$$;

-- ---------------------------------------------------------------------------
-- Append-only enforcement
-- ---------------------------------------------------------------------------

create function audit.refuse_change() returns trigger
language plpgsql as $$
begin
  raise exception 'audit log is append-only' using errcode = '42501';
end;
$$;

create trigger no_update_delete before update or delete on audit.log
  for each row execute function audit.refuse_change();
create trigger no_truncate before truncate on audit.log
  for each statement execute function audit.refuse_change();

revoke all on audit.log, audit.chain_head from public;
revoke update, delete, truncate on audit.log from public;

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------
-- Returns one row per broken record (empty = chain intact), plus a row if the head doesn't match.

create function audit.verify_chain(p_tenant uuid)
returns table (seq bigint, problem text)
language plpgsql stable security definer set search_path = audit, public as $$
declare
  r          audit.log;
  v_prev     bytea := '\x'::bytea;
  v_expected bigint := 1;
  v_calc     bytea;
  v_head     audit.chain_head;
begin
  if not public.is_tenant_admin(p_tenant) and not public.is_platform_admin() then
    raise exception 'only admins can verify the audit chain' using errcode = '42501';
  end if;

  for r in select * from audit.log l where l.tenant_id is not distinct from p_tenant order by l.seq loop
    if r.seq <> v_expected then
      seq := v_expected; problem := 'missing record(s) before seq ' || r.seq; return next;
      v_expected := r.seq;
    end if;
    if r.prev_hash <> v_prev then
      seq := r.seq; problem := 'prev_hash does not match previous record'; return next;
    end if;
    v_calc := audit.record_digest(r.prev_hash, r.tenant_id, r.seq, r.occurred_at, r.table_name, r.record_id,
                r.action, r.actor_id, r.actor_type, r.on_behalf_of, r.source, r.device_id, r.ip, r.geo,
                r.correlation_id, r.reason, r.changed_fields, r.old_data, r.new_data);
    if v_calc <> r.hash then
      seq := r.seq; problem := 'record content was altered'; return next;
    end if;
    v_prev := r.hash;
    v_expected := r.seq + 1;
  end loop;

  select * into v_head from audit.chain_head h
  where h.chain_key = coalesce(p_tenant, '00000000-0000-0000-0000-000000000000');
  if found and (v_head.seq <> v_expected - 1 or v_head.hash <> v_prev) then
    seq := v_head.seq; problem := 'chain head does not match the last record (tail removed?)'; return next;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Read access through the API
-- ---------------------------------------------------------------------------

alter table audit.log enable row level security;

create policy audit_read on audit.log for select using (
  public.is_platform_admin()
  or (tenant_id = public.auth_tenant_id()
      and (public.is_tenant_admin(tenant_id)
           or exists (select 1 from public.my_assignments() a
                      join public.role_permission rp on rp.role_id = a.role_id
                      where rp.feature_key in ('core', 'core.audit', 'core.audit.record_history')
                        and 'view' = any(rp.actions))))
);

grant usage on schema audit to authenticated;
grant select on audit.log to authenticated;
grant execute on function audit.log_event(text, text, text, jsonb, text, uuid) to authenticated;
grant execute on function audit.verify_chain(uuid) to authenticated;

-- History of one record, newest first, with the user's name. Used by the "History" tab on every screen.
create view public.record_history with (security_invoker = true) as
  select l.id, l.tenant_id, l.table_name, l.record_id, l.action, l.occurred_at,
         l.actor_id, u.full_name as actor_name, l.actor_type, l.on_behalf_of, l.source, l.device_id,
         l.reason, l.changed_fields, l.old_data, l.new_data, l.correlation_id
  from audit.log l
  left join public.app_user u on u.id = l.actor_id;

-- Track the foundation tables.
select audit.track('public.tenant');
select audit.track('public.company');
select audit.track('public.company_gstin');
select audit.track('public.location');
select audit.track('public.app_user');
select audit.track('public.feature_flag');
select audit.track('public.role');
select audit.track('public.user_assignment');

-- role_permission has no id/tenant_id column of its own; record it against the role.
create function audit.capture_role_permission() returns trigger
language plpgsql security definer set search_path = audit, public as $$
declare
  v_row jsonb := to_jsonb(coalesce(new, old));
begin
  perform audit.append((select r.tenant_id from public.role r where r.id = (v_row ->> 'role_id')::uuid),
                       'public.role_permission', (v_row ->> 'role_id') || ':' || (v_row ->> 'feature_key'),
                       tg_op,
                       case when tg_op <> 'INSERT' then to_jsonb(old) end,
                       case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return null;
end;
$$;
create trigger zz_audit after insert or update or delete on public.role_permission
  for each row execute function audit.capture_role_permission();
