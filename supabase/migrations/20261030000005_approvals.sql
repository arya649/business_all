-- Approvals engine: configurable multi-step approvals for any document type.
--
-- Admin sets rules ("PO above ₹50,000 at any plant: plant head, then owner").
-- Modules call submit_for_approval() with a small summary of the document; approvers act
-- through act_on_approval() from the web, the mobile card or WhatsApp.
-- Every step is written to approval_action and to the audit chain.

create table public.approval_rule (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenant on delete cascade,
  company_id  uuid references public.company on delete cascade,      -- null = every company
  doc_type    text not null,                                          -- purchase.po, finance.expense, crm.price_change ...
  name        text not null,
  -- All conditions must hold: [{"field":"amount","op":">","value":50000}, {"field":"category","op":"in","value":["capital"]}]
  conditions  jsonb not null default '[]' check (jsonb_typeof(conditions) = 'array'),
  priority    integer not null default 100,                           -- lower is checked first
  allow_self_approval boolean not null default false,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);
create index on public.approval_rule (tenant_id, doc_type);

create table public.approval_rule_step (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenant on delete cascade,
  rule_id          uuid not null references public.approval_rule on delete cascade,
  step_no          integer not null check (step_no > 0),
  approver_type    text not null check (approver_type in ('user', 'role', 'location_head', 'tenant_admin')),
  approver_user_id uuid references public.app_user,
  approver_role_id uuid references public.role,
  mode             text not null default 'any' check (mode in ('any', 'all')),
  sla_hours        integer check (sla_hours > 0),
  escalate_to_user_id uuid references public.app_user,
  unique (rule_id, step_no),
  check (approver_type <> 'user' or approver_user_id is not null),
  check (approver_type <> 'role' or approver_role_id is not null)
);

create table public.approval_request (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenant,
  company_id   uuid not null references public.company,
  location_id  uuid references public.location,
  doc_type     text not null,
  doc_id       uuid not null,
  -- What the approver sees on the card: {"title":"PO-114 Cement 400 bags","amount":152000,
  --   "context":"₹15/bag above last 3 POs","photo_url":"..."}
  summary      jsonb not null default '{}',
  rule_id      uuid references public.approval_rule,
  current_step integer,
  status       text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'sent_back', 'cancelled')),
  requested_by uuid not null references public.app_user default auth.uid(),
  requested_at timestamptz not null default now(),
  step_started_at timestamptz not null default now(),
  decided_at   timestamptz
);
create index on public.approval_request (tenant_id, status);
create unique index approval_one_open_per_doc on public.approval_request (doc_type, doc_id) where status = 'pending';

create table public.approval_action (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenant,
  request_id  uuid not null references public.approval_request on delete cascade,
  step_no     integer,
  actor_id    uuid references public.app_user default auth.uid(),
  action      text not null check (action in ('submit', 'approve', 'reject', 'send_back', 'cancel', 'auto_approve', 'escalate')),
  comment     text,
  voice_note_url text,
  geo         text,
  source      text,                                  -- web / mobile / whatsapp / ai
  acted_at    timestamptz not null default now()
);
create index on public.approval_action (request_id);

-- ---------------------------------------------------------------------------
-- Rule matching
-- ---------------------------------------------------------------------------

create function public.approval_condition_holds(p_cond jsonb, p_summary jsonb) returns boolean
language plpgsql immutable as $$
declare
  v_field text := p_cond ->> 'field';
  v_op    text := p_cond ->> 'op';
  v_want  jsonb := p_cond -> 'value';
  v_have  jsonb := p_summary -> v_field;
begin
  if v_have is null or v_have = 'null'::jsonb then
    return false;
  end if;
  if v_op = 'in' then
    return v_have in (select jsonb_array_elements(v_want));
  elsif v_op = 'not_in' then
    return v_have not in (select jsonb_array_elements(v_want));
  elsif jsonb_typeof(v_want) = 'number' and jsonb_typeof(v_have) = 'number' then
    return case v_op
      when '>'  then (v_have #>> '{}')::numeric >  (v_want #>> '{}')::numeric
      when '>=' then (v_have #>> '{}')::numeric >= (v_want #>> '{}')::numeric
      when '<'  then (v_have #>> '{}')::numeric <  (v_want #>> '{}')::numeric
      when '<=' then (v_have #>> '{}')::numeric <= (v_want #>> '{}')::numeric
      when '='  then (v_have #>> '{}')::numeric =  (v_want #>> '{}')::numeric
      when '!=' then (v_have #>> '{}')::numeric <> (v_want #>> '{}')::numeric
    end;
  else
    return case v_op when '=' then v_have = v_want when '!=' then v_have <> v_want else false end;
  end if;
end;
$$;

create function public.match_approval_rule(p_tenant uuid, p_company uuid, p_doc_type text, p_summary jsonb)
returns public.approval_rule
language sql stable security definer set search_path = public as $$
  select r.* from approval_rule r
  where r.tenant_id = p_tenant and r.doc_type = p_doc_type and r.is_active
    and (r.company_id is null or r.company_id = p_company)
    and not exists (select 1 from jsonb_array_elements(r.conditions) c
                    where not public.approval_condition_holds(c, p_summary))
    and exists (select 1 from approval_rule_step s where s.rule_id = r.id)
  order by r.priority, (r.company_id is null)   -- company-specific rules win ties
  limit 1
$$;

-- ---------------------------------------------------------------------------
-- Who may act on the current step
-- ---------------------------------------------------------------------------

create function public.is_step_approver(p_request public.approval_request, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from approval_rule_step s
    where s.rule_id = p_request.rule_id and s.step_no = p_request.current_step
      and case s.approver_type
        when 'user' then s.approver_user_id = p_user
        when 'role' then exists (
          select 1 from user_assignment a
          where a.user_id = p_user and a.role_id = s.approver_role_id and a.company_id = p_request.company_id
            and (a.location_id is null or a.location_id = p_request.location_id)
            and current_date >= a.valid_from and (a.valid_to is null or current_date <= a.valid_to))
        when 'location_head' then exists (
          select 1 from location l where l.id = p_request.location_id and l.in_charge_user_id = p_user)
        when 'tenant_admin' then exists (
          select 1 from app_user u where u.id = p_user and u.is_tenant_admin and u.tenant_id = p_request.tenant_id)
      end)
    or exists (                                  -- escalation target once the SLA has passed
      select 1 from approval_rule_step s
      where s.rule_id = p_request.rule_id and s.step_no = p_request.current_step
        and s.escalate_to_user_id = p_user and s.sla_hours is not null
        and now() > p_request.step_started_at + make_interval(hours => s.sla_hours))
$$;

-- Everyone who must approve an 'all' step (named users or role holders).
create function public.step_required_approvers(p_request public.approval_request) returns setof uuid
language sql stable security definer set search_path = public as $$
  select s.approver_user_id from approval_rule_step s
  where s.rule_id = p_request.rule_id and s.step_no = p_request.current_step and s.approver_type = 'user'
  union
  select a.user_id from approval_rule_step s
  join user_assignment a on a.role_id = s.approver_role_id and a.company_id = p_request.company_id
       and (a.location_id is null or a.location_id = p_request.location_id)
       and current_date >= a.valid_from and (a.valid_to is null or current_date <= a.valid_to)
  where s.rule_id = p_request.rule_id and s.step_no = p_request.current_step and s.approver_type = 'role'
$$;

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

create function public.submit_for_approval(
  p_doc_type text, p_doc_id uuid, p_company uuid, p_location uuid, p_summary jsonb, p_source text default 'web'
) returns public.approval_request
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid := public.auth_tenant_id();
  v_rule   approval_rule;
  v_req    approval_request;
begin
  if not public.user_can(p_doc_type, 'create', p_company, p_location) then
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

create function public.act_on_approval(
  p_request uuid, p_action text, p_comment text default null, p_source text default 'web', p_geo text default null
) returns public.approval_request
language plpgsql security definer set search_path = public as $$
declare
  v_req   approval_request;
  v_rule  approval_rule;
  v_step  approval_rule_step;
  v_user  uuid := auth.uid();
  v_last  integer;
  v_done  boolean;
begin
  if p_action not in ('approve', 'reject', 'send_back', 'cancel') then
    raise exception 'unknown action %', p_action;
  end if;

  select * into v_req from approval_request where id = p_request for update;
  if not found or v_req.tenant_id is distinct from public.auth_tenant_id() then
    raise exception 'approval request not found' using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'this request is already %', v_req.status;
  end if;

  if p_action = 'cancel' then
    if v_req.requested_by <> v_user and not public.is_tenant_admin(v_req.tenant_id) then
      raise exception 'only the requester can cancel' using errcode = '42501';
    end if;
  else
    if not public.is_step_approver(v_req, v_user) then
      raise exception 'you are not an approver for this step' using errcode = '42501';
    end if;
    select * into v_rule from approval_rule where id = v_req.rule_id;
    if v_req.requested_by = v_user and not v_rule.allow_self_approval then
      raise exception 'you cannot approve your own request' using errcode = '42501';
    end if;
    if p_action in ('reject', 'send_back') and coalesce(trim(p_comment), '') = '' then
      raise exception 'a reason is required to %', replace(p_action, '_', ' ');
    end if;
  end if;

  insert into approval_action (tenant_id, request_id, step_no, action, comment, source, geo)
  values (v_req.tenant_id, v_req.id, v_req.current_step, p_action, p_comment, p_source, p_geo);

  if p_action = 'approve' then
    select * into v_step from approval_rule_step where rule_id = v_req.rule_id and step_no = v_req.current_step;
    v_done := v_step.mode = 'any' or not exists (
      select 1 from public.step_required_approvers(v_req) r(uid)
      where r.uid <> v_req.requested_by
        and not exists (select 1 from approval_action x
                        where x.request_id = v_req.id and x.step_no = v_req.current_step
                          and x.action = 'approve' and x.actor_id = r.uid));
    if v_done then
      select max(step_no) into v_last from approval_rule_step where rule_id = v_req.rule_id;
      if v_req.current_step >= v_last then
        update approval_request set status = 'approved', decided_at = now() where id = v_req.id returning * into v_req;
      else
        update approval_request set current_step = current_step + 1, step_started_at = now()
        where id = v_req.id returning * into v_req;
      end if;
    end if;
  else
    update approval_request
    set status = case p_action when 'reject' then 'rejected' when 'send_back' then 'sent_back' else 'cancelled' end,
        decided_at = now()
    where id = v_req.id returning * into v_req;
  end if;

  return v_req;
end;
$$;

-- What's waiting for me (mobile "Approvals" tile).
create function public.my_pending_approvals()
returns setof public.approval_request
language sql stable security definer set search_path = public as $$
  select r.* from approval_request r
  where r.tenant_id = public.auth_tenant_id() and r.status = 'pending'
    and public.is_step_approver(r, auth.uid())
    and not exists (select 1 from approval_action x where x.request_id = r.id and x.step_no = r.current_step
                    and x.actor_id = auth.uid() and x.action = 'approve')
  order by r.requested_at
$$;

-- ---------------------------------------------------------------------------
-- RLS: requests and actions are written only through the functions above.
-- ---------------------------------------------------------------------------

alter table public.approval_rule      enable row level security;
alter table public.approval_rule_step enable row level security;
alter table public.approval_request   enable row level security;
alter table public.approval_action    enable row level security;

create policy rule_read  on public.approval_rule for select using (tenant_id = public.auth_tenant_id());
create policy rule_write on public.approval_rule for all
  using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));
create policy step_read  on public.approval_rule_step for select using (tenant_id = public.auth_tenant_id());
create policy step_write on public.approval_rule_step for all
  using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));

-- Visible to the requester, admins, current approvers and anyone who already acted on it.
create function public.can_see_approval(p_request uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from approval_request r
    where r.id = p_request and r.tenant_id = public.auth_tenant_id()
      and (r.requested_by = auth.uid() or public.is_tenant_admin(r.tenant_id)
           or public.is_step_approver(r, auth.uid())
           or exists (select 1 from approval_action x where x.request_id = r.id and x.actor_id = auth.uid())))
$$;

create policy request_read on public.approval_request for select using (public.can_see_approval(id));
create policy action_read  on public.approval_action  for select using (public.can_see_approval(request_id));

select audit.track('public.approval_rule');
select audit.track('public.approval_rule_step');
select audit.track('public.approval_request');
select audit.track('public.approval_action');
