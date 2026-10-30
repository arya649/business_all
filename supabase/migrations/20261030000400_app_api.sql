-- Functions the web and mobile apps call for their home screen, owner dashboard and leakage board.

-- Who am I, which companies and locations can I work in.
create function public.my_context() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'user', (select jsonb_build_object('id', u.id, 'name', u.full_name, 'mobile', u.mobile, 'language', u.preferred_language,
                                       'is_tenant_admin', u.is_tenant_admin, 'is_platform_admin', u.is_platform_admin, 'photo', u.photo_url)
             from app_user u where u.id = auth.uid()),
    'tenant', (select jsonb_build_object('id', t.id, 'name', t.name, 'logo', t.logo_url) from tenant t where t.id = public.auth_tenant_id()),
    'ui_mode', coalesce((select max(r.ui_mode) from public.my_assignments() a join role r on r.id = a.role_id),
                        case when public.is_tenant_admin() then 'power' else 'simple' end),
    'companies', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.legal_name, 'code', c.short_code,
        'locations', coalesce((
          select jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'code', l.short_code, 'type', l.type) order by l.name)
          from location l
          where l.company_id = c.id and l.parent_id is null and l.is_active
            and (public.is_tenant_admin()
                 or exists (select 1 from public.my_assignments() a where a.company_id = c.id
                            and (a.location_id is null or a.location_id = l.id)))), '[]')
      ) order by c.legal_name)
      from company c where c.id in (select public.my_company_ids()) and c.is_active), '[]')
  )
$$;

-- Leakage board: every rule that finds money slipping away, in plain words, with a link to the record.
create function public.leakage_board(p_company uuid)
returns table (kind text, severity text, title text, detail text, entity text, record_id uuid, location_id uuid,
               amount numeric, doc_date date)
language sql stable security definer set search_path = public as $$
  select * from (
    select 'tank_variance', 'high', 'Tank stock does not match',
           format('Dip %s L vs book %s L (%s L)', round(d.dip_litres), round(d.book_litres), round(d.variance_litres)),
           'bunk.dip', d.id, d.location_id, abs(d.variance_litres), d.doc_date
    from bunk_dip d where d.company_id = p_company and d.variance_alert and d.doc_date > current_date - 30
    union all
    select 'cash_short', 'medium', 'Cash short at shift close',
           format('Shift %s short by ₹%s', s.doc_no, abs(round(s.short_excess))),
           'bunk.shift', s.id, s.location_id, abs(s.short_excess), s.doc_date
    from bunk_shift s where s.company_id = p_company and s.short_excess < -100 and s.doc_date > current_date - 30
    union all
    select 'tanker_short', 'high', 'Tanker delivered short',
           format('%s: %s L short, density diff %s', t.invoice_no, abs(round(t.short_litres)), round(t.density_diff, 1)),
           'bunk.tanker_receipt', t.id, t.location_id, abs(t.short_litres), t.doc_date
    from bunk_tanker_receipt t where t.company_id = p_company and (t.short_litres < -25 or abs(coalesce(t.density_diff, 0)) > 3)
      and t.doc_date > current_date - 60
    union all
    select 'tare_drift', 'high', 'Vehicle tare differs from usual',
           format('%s: tare %s kg vs usual %s kg', w.vehicle_no, round(w.tare_kg), round(w.standard_tare_kg)),
           'weighbridge.ticket', w.id, w.location_id, abs(w.tare_kg - w.standard_tare_kg), w.doc_date
    from weighbridge_ticket w where w.company_id = p_company and w.tare_alert and w.doc_date > current_date - 30
    union all
    select 'manual_weight', 'medium', 'Weight typed by hand',
           format('%s: %s', w.vehicle_no, coalesce(w.manual_reason, 'no reason')),
           'weighbridge.ticket', w.id, w.location_id, w.net_kg, w.doc_date
    from weighbridge_ticket w where w.company_id = p_company and 'manual' in (w.first_mode, w.second_mode) and w.doc_date > current_date - 30
    union all
    select 'batch_deviation', 'medium', 'Batch outside mix design',
           format('%s: worst material off by %s%%', b.doc_no, trim_scale(round(b.max_deviation_pct, 1))),
           'rmc.batch', b.id, b.location_id, b.max_deviation_pct, b.doc_date
    from rmc_batch b where b.company_id = p_company and b.deviation_alert and b.doc_date > current_date - 30
    union all
    select 'unbilled_challan', 'high', 'Delivered but not billed',
           format('%s %s m³ %s, %s days ago', c.doc_no, trim_scale(c.qty_m3), c.grade, current_date - c.doc_date),
           'rmc.challan', c.id, c.location_id, c.qty_m3 * coalesce(o.rate_per_m3, 0), c.doc_date
    from rmc_challan c join rmc_order o on o.id = c.order_id
    where c.company_id = p_company and c.billing_status = 'unbilled' and c.doc_date < current_date - 2
    union all
    select 'unbilled_hotmix', 'high', 'Hot-mix delivered but not billed', format('%s %s MT', d.doc_no, trim_scale(d.net_mt)),
           'bitumen.dispatch', d.id, d.location_id, d.amount, d.doc_date
    from bitumen_dispatch d where d.company_id = p_company and d.billing_status = 'unbilled' and d.doc_date < current_date - 2
    union all
    select 'fuel_mismatch', 'high', 'Fuel use above norm',
           format('%s: %s%% worse than norm', v.reg_no, trim_scale(round(f.variance_pct, 1))),
           'fleet.fuel', f.id, f.location_id, f.litres, f.doc_date
    from fleet_fuel f join vehicle v on v.id = f.vehicle_id
    where f.company_id = p_company and f.mismatch_alert and f.doc_date > current_date - 30
    union all
    select 'cube_fail', 'high', 'Cube test failed', format('%s %s: 28-day %s N/mm²', ct.doc_no, ct.grade, ct.avg_28_day),
           'rmc.cube_test', ct.id, ct.location_id, null, ct.doc_date
    from rmc_cube_test ct where ct.company_id = p_company and ct.result = 'fail'
    union all
    select 'unbilled_work', 'medium', 'Project work done but not billed',
           format('%s: %s %s not billed', b.item_no, round(b.done_qty - b.billed_qty, 1), b.unit),
           'infra.boq_item', b.id, b.location_id, (b.done_qty - b.billed_qty) * b.rate, null::date
    from infra_boq_item b where b.company_id = p_company and b.done_qty - b.billed_qty > 0
    union all
    select 'doc_expiry', case when vd.expires_on < current_date then 'high' else 'medium' end,
           'Vehicle document ' || case when vd.expires_on < current_date then 'expired' else 'expiring' end,
           format('%s %s on %s', vd.reg_no, vd.doc_type, to_char(vd.expires_on, 'DD Mon')),
           null, vd.vehicle_id, null, null, vd.expires_on
    from vehicle_documents_expiring vd join vehicle v on v.id = vd.vehicle_id
    where v.owning_company_id = p_company
  ) x(kind, severity, title, detail, entity, record_id, location_id, amount, doc_date)
  where public.is_tenant_admin() or public.user_can('core.dashboard.leakage_board', 'view', p_company, null)
  order by case severity when 'high' then 0 else 1 end, amount desc nulls last
$$;

-- Owner dashboard: one row per company the user can see.
create function public.owner_dashboard(p_from date default date_trunc('month', current_date)::date, p_to date default current_date)
returns table (company_id uuid, company_code text, company_name text, sales numeric, sales_today numeric, cash_bank numeric,
               receivables numeric, payables numeric, intercompany_sales numeric, diesel_litres numeric, rmc_m3 numeric,
               hotmix_mt numeric, bricks_units numeric, fuel_litres_sold numeric, pending_approvals bigint, alerts bigint)
language sql stable security definer set search_path = public as $$
  with cos as (
    select c.* from company c where c.id in (select public.my_company_ids())
      and (public.is_tenant_admin() or public.user_can('core.dashboard.owner', 'view', c.id, null))
  ),
  jl as (
    select j.company_id, j.doc_date, j.is_intercompany, fl.code, fl.ledger_group, l.debit, l.credit
    from finance_journal j join finance_journal_lines l on l.parent_id = j.id join finance_ledger fl on fl.id = l.ledger_id
    where j.status = 'approved' and j.company_id in (select id from cos)
  )
  select c.id, c.short_code, c.legal_name,
    (select coalesce(sum(credit - debit), 0) from jl where jl.company_id = c.id and ledger_group = 'sales' and doc_date between p_from and p_to),
    (select coalesce(sum(credit - debit), 0) from jl where jl.company_id = c.id and ledger_group = 'sales' and doc_date = current_date),
    (select coalesce(sum(debit - credit), 0) from jl where jl.company_id = c.id and ledger_group in ('cash', 'bank')),
    (select coalesce(sum(debit - credit), 0) from jl where jl.company_id = c.id and code = 'DEBTORS'),
    (select coalesce(sum(credit - debit), 0) from jl where jl.company_id = c.id and code = 'CREDITORS'),
    (select coalesce(sum(credit - debit), 0) from jl where jl.company_id = c.id and ledger_group = 'sales' and is_intercompany and doc_date between p_from and p_to),
    (select coalesce(sum(litres), 0) from fleet_fuel f where f.company_id = c.id and f.doc_date between p_from and p_to),
    (select coalesce(sum(qty_m3 - coalesce(returned_m3, 0)), 0) from rmc_challan ch where ch.company_id = c.id and ch.doc_date between p_from and p_to),
    (select coalesce(sum(net_mt), 0) from bitumen_dispatch d where d.company_id = c.id and d.doc_date between p_from and p_to),
    (select coalesce(sum(good_units), 0) from bricks_production p where p.company_id = c.id and p.doc_date between p_from and p_to),
    (select coalesce(sum(total_litres), 0) from bunk_shift s where s.company_id = c.id and s.status = 'approved' and s.doc_date between p_from and p_to),
    (select count(*) from approval_request r where r.company_id = c.id and r.status = 'pending'),
    (select count(*) from public.leakage_board(c.id))
  from cos c
  order by c.legal_name
$$;

-- Search the audit log (admins and roles with core.audit view).
create function public.audit_search(p_actor uuid default null, p_table text default null, p_record text default null,
                                    p_from timestamptz default now() - interval '7 days', p_to timestamptz default now(),
                                    p_limit integer default 200)
returns setof public.record_history
language sql stable security invoker set search_path = public as $$
  select * from public.record_history h
  where (p_actor is null or h.actor_id = p_actor)
    and (p_table is null or h.table_name = p_table)
    and (p_record is null or h.record_id = p_record)
    and h.occurred_at between p_from and p_to
  order by h.occurred_at desc
  limit least(p_limit, 1000)
$$;

-- Record history for one module record (the History tab).
create function public.erp_history(p_entity text, p_id uuid) returns setof public.record_history
language plpgsql stable security definer set search_path = public as $$
declare
  e erp_entity := public.erp_entity_row(p_entity);
  v jsonb;
begin
  -- anyone who can see the record can see its history
  v := public.erp_get(p_entity, p_id);
  return query
    select * from record_history h
    where (h.table_name = 'public.' || e.table_name and h.record_id = p_id::text)
       or (h.table_name in (select 'public.' || c.table_name from erp_entity c where c.parent_key = p_entity)
           and (h.new_data ->> 'parent_id' = p_id::text or h.old_data ->> 'parent_id' = p_id::text))
       or (h.table_name = 'public.approval_action' and h.new_data ->> 'request_id' in
             (select r.id::text from approval_request r where r.doc_type = p_entity and r.doc_id = p_id))
    order by h.occurred_at desc;
end;
$$;

-- Pending approvals with enough context for the card.
create function public.my_approval_cards() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'doc_type', r.doc_type, 'doc_id', r.doc_id, 'title', r.summary ->> 'title', 'amount', r.summary -> 'amount',
    'company', c.short_code, 'location', l.name, 'requested_by', u.full_name, 'requested_at', r.requested_at,
    'step', r.current_step, 'steps', (select count(*) from approval_rule_step s where s.rule_id = r.rule_id),
    'rule', ar.name, 'entity_label', e.label) order by r.requested_at), '[]')
  from public.my_pending_approvals() r
  join company c on c.id = r.company_id
  left join location l on l.id = r.location_id
  left join app_user u on u.id = r.requested_by
  left join approval_rule ar on ar.id = r.rule_id
  left join erp_entity e on e.key = r.doc_type
$$;

-- Admin: preview as user — the full resolved switch tree for any user in a company.
create function public.preview_features(p_user uuid, p_company uuid, p_location uuid default null)
returns table (feature_key text, parent_key text, label text, state public.feature_state, config jsonb)
language sql stable security definer set search_path = public as $$
  select r.feature_key, f.parent_key, f.label, r.state, r.config
  from public.resolved_features(p_company, p_location, p_user) r join feature f on f.key = r.feature_key
  where public.is_tenant_admin()
  order by f.sort
$$;

-- Admin: every field of a feature's records, for the "response fields 14/17" checklist.
create function public.feature_fields(p_feature text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('entity', e.key, 'entity_label', e.label, 'name', f.name, 'label', f.label,
                                               'sensitive', f.sensitive) order by e.sort, f.sort), '[]')
  from erp_entity e join erp_field f on f.entity_key = e.key
  where e.feature_key = p_feature or e.feature_key like p_feature || '.%'
     or e.parent_key in (select key from erp_entity where feature_key = p_feature or feature_key like p_feature || '.%')
$$;

-- Public wrapper so the admin screen can check the audit chain without exposing the audit schema.
create function public.verify_audit_chain() returns table (seq bigint, problem text)
language sql stable security definer set search_path = public as $$
  select * from audit.verify_chain(public.auth_tenant_id())
$$;

-- ---------------------------------------------------------------------------
-- AI (Zentrix ADK)
-- ---------------------------------------------------------------------------

-- Scopes for the user's Zentrix token: plan ∩ switches ∩ role, the same rule Zentrix applies to partner ∩ customer ∩ token.
create function public.ai_scopes(p_company uuid, p_location uuid default null) returns text[]
language sql stable security definer set search_path = public as $$
  with f as (select * from public.resolved_features(p_company, p_location))
  select array_remove(array(
    select 'agent.' || a from unnest(array['owner_assistant', 'site_assistant', 'plant_assistant', 'bunk_assistant',
                                           'fleet_assistant', 'accounts_assistant', 'admin_assistant']) a
    where exists (select 1 from f where feature_key = 'ai.chat' and state = 'on')
      and (a <> 'admin_assistant' or public.is_tenant_admin())
      and (a <> 'owner_assistant' or public.is_tenant_admin() or public.user_can('core.dashboard.owner', 'view', p_company, null))
    union all
    select 'extract.*' where exists (select 1 from f where feature_key = 'ai.ocr' and state = 'on')
    union all
    select e.feature_key || '.' || act
    from erp_entity e cross join unnest(array['view', 'create']) act
    where e.parent_key is null
      and exists (select 1 from f where f.feature_key = e.feature_key and f.state in ('on', 'read_only'))
      and (public.user_can(e.feature_key, act, p_company, p_location)
           or exists (select 1 from location l where l.company_id = p_company and public.user_can(e.feature_key, act, p_company, l.id)))
  ), null)
$$;

-- The single door AI tools use to read ERP data. Only tokens minted by the AI service (claim via = zentrix)
-- may call it; it runs as the user (RLS and permissions apply) and marks every audit record as an AI action
-- on that user's behalf, linked to the Zentrix correlation id.
create function public.ai_call(p_fn text, p_args jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path = public as $$
declare
  v_claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  v jsonb;
begin
  if coalesce(v_claims ->> 'via', '') <> 'zentrix' then
    raise exception 'ai_call is only for the AI service' using errcode = '42501';
  end if;
  perform audit.set_context(p_source => 'ai', p_actor_type => 'ai_agent', p_on_behalf_of => auth.uid(),
                            p_correlation_id => v_claims ->> 'correlation_id');
  case p_fn
    when 'erp_catalog' then v := public.erp_catalog((p_args ->> 'company')::uuid, (p_args ->> 'location')::uuid);
    when 'erp_list' then v := public.erp_list(p_args ->> 'entity', (p_args ->> 'company')::uuid, (p_args ->> 'location')::uuid,
                                              coalesce(p_args -> 'filters', '{}'), p_args ->> 'search', coalesce((p_args ->> 'limit')::int, 20), 0);
    when 'erp_get' then v := public.erp_get(p_args ->> 'entity', (p_args ->> 'id')::uuid);
    when 'owner_dashboard' then select coalesce(jsonb_agg(to_jsonb(d)), '[]') into v from public.owner_dashboard() d;
    when 'leakage_board' then select coalesce(jsonb_agg(to_jsonb(d)), '[]') into v from public.leakage_board((p_args ->> 'company')::uuid) d;
    when 'trial_balance' then select coalesce(jsonb_agg(to_jsonb(d)), '[]') into v from public.trial_balance((p_args ->> 'company')::uuid) d;
    when 'stock_on_hand' then select coalesce(jsonb_agg(to_jsonb(d)), '[]') into v
                              from public.stock_on_hand((p_args ->> 'company')::uuid, (p_args ->> 'location')::uuid) d;
    when 'party_balance' then v := to_jsonb(public.party_balance((p_args ->> 'company')::uuid, (p_args ->> 'party')::uuid));
    when 'project_health' then v := public.project_health((p_args ->> 'project')::uuid);
    when 'lookup' then select coalesce(jsonb_agg(to_jsonb(d)), '[]') into v
                       from public.erp_lookup(p_args ->> 'ref', (p_args ->> 'company')::uuid, p_args ->> 'search') d;
    else raise exception 'AI tools cannot call %', p_fn;
  end case;
  perform audit.log_event('ai.tool_call', 'ai', p_fn, jsonb_build_object('args', p_args));
  return v;
end;
$$;
