-- Core platform tests. Run with scripts/test-db.sh. Any failed assertion stops the run.
\set ON_ERROR_STOP 1
\set QUIET 1

create schema t;
grant usage on schema t to authenticated, anon;

create function t.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, false);
  select set_config('role', 'authenticated', false);
$$;
grant execute on function t.login(uuid) to authenticated;

create function t.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if p_cond is not true then raise exception 'FAIL: %', p_msg; end if;
  raise notice 'ok - %', p_msg;
end $$;
grant execute on function t.ok(boolean, text) to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Fixture (as superuser)
-- ---------------------------------------------------------------------------
-- Tenants:  T1 = Sri Group (RMC co + Bunk co),  T2 = another client
insert into tenant (id, name) values
  ('10000000-0000-0000-0000-000000000001', 'Sri Group'),
  ('10000000-0000-0000-0000-000000000002', 'Other Group');

insert into company (id, tenant_id, legal_name, short_code, pan) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Sri RMC Pvt Ltd', 'SRMC', 'AABCS1234K'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'Sri Fuels', 'SFUEL', 'AABFS1234L'),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', 'Other Infra', 'OINF', null);

insert into company_gstin (tenant_id, company_id, gstin) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '37AABCS1234K1Z5');

insert into location (id, tenant_id, company_id, type, name, short_code) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'plant', 'Vijayawada RMC', 'VJA'),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'plant', 'Guntur RMC', 'GNT'),
  ('30000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 'bunk', 'Highway Bunk', 'HWB');

insert into auth.users (id) values
  ('40000000-0000-0000-0000-00000000000a'), ('40000000-0000-0000-0000-00000000000b'),
  ('40000000-0000-0000-0000-00000000000c'), ('40000000-0000-0000-0000-00000000000d'),
  ('40000000-0000-0000-0000-00000000000e');

-- a = tenant admin (owner), b = plant operator at VJA, c = plant head of SRMC, d = other tenant user, e = accountant
insert into app_user (id, tenant_id, full_name, mobile, is_tenant_admin) values
  ('40000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', 'Owner', '9000000001', true),
  ('40000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000001', 'Ravi Operator', '9000000002', false),
  ('40000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-000000000001', 'Plant Head', '9000000003', false),
  ('40000000-0000-0000-0000-00000000000d', '10000000-0000-0000-0000-000000000002', 'Other User', '9000000004', false),
  ('40000000-0000-0000-0000-00000000000e', '10000000-0000-0000-0000-000000000001', 'Accountant', '9000000005', false);

insert into role (id, tenant_id, name, ui_mode) values
  ('50000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Plant Operator', 'simple'),
  ('50000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'Plant Head', 'standard'),
  ('50000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'Accountant', 'power');

insert into role_permission (role_id, feature_key, actions) values
  ('50000000-0000-0000-0000-000000000001', 'rmc.batch_entry', '{view,create}'),
  ('50000000-0000-0000-0000-000000000001', 'rmc.delivery_challan', '{view,create,print}'),
  ('50000000-0000-0000-0000-000000000002', 'rmc', '{view,create,edit,approve}'),
  ('50000000-0000-0000-0000-000000000002', 'purchase', '{view,create,approve}'),
  ('50000000-0000-0000-0000-000000000003', 'core.masters.party', '{view,create,edit}'),
  ('50000000-0000-0000-0000-000000000003', 'core.audit', '{view}');

insert into user_assignment (tenant_id, user_id, company_id, location_id, role_id) values
  ('10000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-00000000000b', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-00000000000c', '20000000-0000-0000-0000-000000000001', null, '50000000-0000-0000-0000-000000000002'),
  ('10000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-00000000000e', '20000000-0000-0000-0000-000000000001', null, '50000000-0000-0000-0000-000000000003'),
  ('10000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-00000000000e', '20000000-0000-0000-0000-000000000002', null, '50000000-0000-0000-0000-000000000003');

update location set in_charge_user_id = '40000000-0000-0000-0000-00000000000c' where short_code = 'VJA';

-- ---------------------------------------------------------------------------
\echo '== Tenant isolation'
-- ---------------------------------------------------------------------------
select t.login('40000000-0000-0000-0000-00000000000d');
select t.ok((select count(*) from company where tenant_id = '10000000-0000-0000-0000-000000000001') = 0, 'other-tenant user sees no Sri Group company');
select t.ok((select count(*) from app_user where tenant_id = '10000000-0000-0000-0000-000000000001') = 0, 'other-tenant user sees no Sri Group users');
reset role;

select t.login('40000000-0000-0000-0000-00000000000b');
select t.ok((select array_agg(short_code order by short_code) from company) = '{SRMC}', 'operator sees only the company they are assigned to');
select t.ok((select count(*) from user_assignment) = 1, 'operator sees only their own assignment');
do $$ begin
  update company set legal_name = 'hacked';
  perform t.ok((select legal_name from company where short_code = 'SRMC') = 'Sri RMC Pvt Ltd', 'operator cannot rename the company');
end $$;
reset role;

select t.login('40000000-0000-0000-0000-00000000000a');
select t.ok((select count(*) from company) = 2, 'tenant admin sees every company in the group');
reset role;

-- ---------------------------------------------------------------------------
\echo '== Permissions'
-- ---------------------------------------------------------------------------
select t.login('40000000-0000-0000-0000-00000000000b');
select t.ok(user_can('rmc.batch_entry', 'create', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001'), 'operator can create batch entries at VJA');
select t.ok(not user_can('rmc.batch_entry', 'create', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002'), 'operator cannot create batch entries at GNT');
select t.ok(not user_can('rmc.batch_entry', 'edit',   '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001'), 'operator cannot edit batch entries');
select t.ok(not user_can('rmc.billing', 'view',       '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001'), 'operator cannot see billing');
select t.ok(not user_can('bunk.dsr', 'view',          '20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000003'), 'operator has nothing at the bunk company');
reset role;

select t.login('40000000-0000-0000-0000-00000000000c');
select t.ok(user_can('rmc.cube_test', 'approve', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002'), 'plant head: permission on "rmc" covers rmc.cube_test at any plant');
reset role;

-- ---------------------------------------------------------------------------
\echo '== Feature switches'
-- ---------------------------------------------------------------------------
-- Owner turns on cube tests with custom ages; the platform plan does not include ATG integration.
insert into feature_flag (tenant_id, feature_key, level, level_id, state, config) values
  ('10000000-0000-0000-0000-000000000001', 'rmc.cube_test', 'tenant', '10000000-0000-0000-0000-000000000001', 'on', '{"ages":[3,7,28]}'),
  ('10000000-0000-0000-0000-000000000001', 'bunk.tanks.atg_integration', 'plan', '10000000-0000-0000-0000-000000000001', 'off', null),
  ('10000000-0000-0000-0000-000000000001', 'bunk.tanks.atg_integration', 'tenant', '10000000-0000-0000-0000-000000000001', 'on', null),
  -- Guntur plant is closing: RMC becomes read-only there.
  ('10000000-0000-0000-0000-000000000001', 'rmc', 'location', '30000000-0000-0000-0000-000000000002', 'read_only', null),
  -- Owner hides the whole AI module for the bunk company.
  ('10000000-0000-0000-0000-000000000001', 'ai', 'company', '20000000-0000-0000-0000-000000000002', 'off', null);

select t.login('40000000-0000-0000-0000-00000000000a');
select t.ok((select config -> 'ages' from resolved_features('20000000-0000-0000-0000-000000000001') where feature_key = 'rmc.cube_test') = '[3,7,28]',
            'tenant config overrides the default cube-test ages');
select t.ok((select config ->> 'min_samples' from resolved_features('20000000-0000-0000-0000-000000000001') where feature_key = 'rmc.cube_test') = '3',
            'default config keys survive the merge');
select t.ok(feature_state_of('bunk.tanks.atg_integration', '20000000-0000-0000-0000-000000000002') = 'off',
            'plan ceiling wins over the tenant switching a feature on');
select t.ok(feature_state_of('rmc.batch_entry', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002') = 'read_only',
            'read_only on a parent flows down to children at that location');
select t.ok(feature_state_of('rmc.batch_entry', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001') = 'on',
            'other locations are unaffected');
select t.ok(feature_state_of('ai.proactive.diesel_watchdog', '20000000-0000-0000-0000-000000000002') = 'off',
            'switching off a module switches off every feature below it');
select t.ok(feature_state_of('ai.chat', '20000000-0000-0000-0000-000000000001') = 'on',
            'company-level switch does not leak to other companies');
reset role;

select t.login('40000000-0000-0000-0000-00000000000c');
select t.ok(not user_can('rmc.batch_entry', 'create', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002'),
            'nobody can create in a read_only feature, even with permission');
select t.ok(user_can('rmc.batch_entry', 'view', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002'),
            'read_only still allows viewing');
do $$ begin
  perform resolved_features('20000000-0000-0000-0000-000000000001', null, '40000000-0000-0000-0000-00000000000b');
  raise exception 'FAIL: non-admin resolved features for another user';
exception when insufficient_privilege then perform t.ok(true, 'non-admin cannot resolve features for another user');
end $$;
do $$ begin
  insert into feature_flag (tenant_id, feature_key, level, level_id, state)
  values ('10000000-0000-0000-0000-000000000001', 'rmc', 'user', '40000000-0000-0000-0000-00000000000c', 'on');
  raise exception 'FAIL: non-admin changed a feature switch';
exception when insufficient_privilege then perform t.ok(true, 'non-admin cannot change feature switches');
end $$;
reset role;

select t.login('40000000-0000-0000-0000-00000000000a');
do $$ begin
  insert into feature_flag (tenant_id, feature_key, level, level_id, state)
  values ('10000000-0000-0000-0000-000000000001', 'bunk', 'plan', '10000000-0000-0000-0000-000000000001', 'on');
  raise exception 'FAIL: tenant admin changed their own plan';
exception when insufficient_privilege then perform t.ok(true, 'tenant admin cannot raise their own plan ceiling');
end $$;
reset role;

-- ---------------------------------------------------------------------------
\echo '== Masters'
-- ---------------------------------------------------------------------------
select t.login('40000000-0000-0000-0000-00000000000b');
do $$ begin
  insert into party (tenant_id, party_code, display_name, party_types)
  values ('10000000-0000-0000-0000-000000000001', 'C001', 'Ravi Constructions', '{customer}');
  raise exception 'FAIL: operator created a party';
exception when insufficient_privilege then perform t.ok(true, 'operator without master permission cannot add parties');
end $$;
reset role;

select t.login('40000000-0000-0000-0000-00000000000e');
insert into party (tenant_id, party_code, display_name, party_types, pan, mobile) values
  ('10000000-0000-0000-0000-000000000001', 'C001', 'Ravi Constructions', '{customer,bunk_credit}', 'AAAPR1234C', '9876543210');
insert into party (tenant_id, party_code, display_name, party_types, group_company_id) values
  ('10000000-0000-0000-0000-000000000001', 'IC01', 'Sri Fuels (group)', '{vendor}', '20000000-0000-0000-0000-000000000002');
select t.ok((select is_intercompany from party where party_code = 'IC01'), 'a party linked to a group company is flagged inter-company automatically');
select t.ok((select reason from find_similar_parties('Ravi Construction') limit 1) = 'similar name', 'duplicate warning on a similar name');
select t.ok((select reason from find_similar_parties('R. C. Builders', '9876543210') limit 1) = 'same mobile', 'duplicate warning on the same mobile');
reset role;

-- ---------------------------------------------------------------------------
\echo '== Document numbers'
-- ---------------------------------------------------------------------------
-- Challans are not GST invoices, so they may exceed the 16-character invoice limit.
insert into number_series (tenant_id, company_id, location_id, doc_type, pattern, fy, max_length) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', null, 'rmc.delivery_challan', 'DC/{LOC}/{FY}/{SEQ:4}', '26-27', 20);

select t.ok(financial_year('2026-10-30') = '26-27' and financial_year('2027-02-01') = '26-27' and financial_year('2027-04-01') = '27-28',
            'financial year runs April to March');

select t.login('40000000-0000-0000-0000-00000000000b');
select t.ok(next_doc_number('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'rmc.delivery_challan', '2026-10-30') = 'DC/VJA/26-27/0001',
            'first challan at VJA follows the company pattern');
select t.ok(next_doc_number('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'rmc.delivery_challan', '2026-10-30') = 'DC/VJA/26-27/0002',
            'numbers increase');
select t.ok((select from_value from reserve_number_block('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'rmc.delivery_challan', 'phone-ravi', 50)) = 3,
            'offline block starts after the last online number');
select t.ok(next_doc_number('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'rmc.delivery_challan', '2026-10-30') = 'DC/VJA/26-27/0053',
            'online numbering skips the block reserved for the phone');
do $$ begin
  perform next_doc_number('20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000003', 'bunk.shift');
  raise exception 'FAIL: operator numbered a bunk document';
exception when insufficient_privilege then perform t.ok(true, 'cannot take numbers for a module you have no access to');
end $$;
reset role;

-- ---------------------------------------------------------------------------
\echo '== Approvals'
-- ---------------------------------------------------------------------------
-- POs above 50,000: plant head (role), then owner (tenant admin).
insert into approval_rule (id, tenant_id, doc_type, name, conditions) values
  ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'purchase.po', 'Big POs',
   '[{"field":"amount","op":">","value":50000}]');
insert into approval_rule_step (tenant_id, rule_id, step_no, approver_type, approver_role_id) values
  ('10000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 1, 'role', '50000000-0000-0000-0000-000000000002');
insert into approval_rule_step (tenant_id, rule_id, step_no, approver_type) values
  ('10000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 2, 'tenant_admin');

-- Operator gets purchase rights so they can raise a PO.
insert into role_permission (role_id, feature_key, actions) values ('50000000-0000-0000-0000-000000000001', 'purchase', '{view,create}');

select t.login('40000000-0000-0000-0000-00000000000b');
select t.ok((submit_for_approval('purchase.po', '70000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
             '30000000-0000-0000-0000-000000000001', '{"amount": 12000, "title": "PO small"}')).status = 'approved',
            'below the threshold: approved automatically');
select t.ok((submit_for_approval('purchase.po', '70000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001',
             '30000000-0000-0000-0000-000000000001', '{"amount": 152000, "title": "PO cement 400 bags"}')).current_step = 1,
            'above the threshold: waits at step 1');
do $$ begin
  perform act_on_approval((select id from approval_request where doc_id = '70000000-0000-0000-0000-000000000002'), 'approve');
  raise exception 'FAIL: requester approved their own PO';
exception when insufficient_privilege then perform t.ok(true, 'requester cannot approve their own PO');
end $$;
reset role;

select t.login('40000000-0000-0000-0000-00000000000c');
select t.ok((select count(*) from my_pending_approvals()) = 1, 'plant head sees the PO in their approvals tile');
do $$ begin
  perform act_on_approval((select id from approval_request where doc_id = '70000000-0000-0000-0000-000000000002'), 'reject');
  raise exception 'FAIL: rejected without a reason';
exception when others then
  perform t.ok(sqlerrm like 'a reason is required%', 'rejecting needs a reason');
end $$;
select t.ok((act_on_approval((select id from approval_request where doc_id = '70000000-0000-0000-0000-000000000002'), 'approve', 'rate ok', 'mobile')).current_step = 2,
            'plant head approves: moves to step 2');
select t.ok((select count(*) from my_pending_approvals()) = 0, 'gone from the plant head''s tile after acting');
reset role;

select t.login('40000000-0000-0000-0000-00000000000a');
select t.ok((act_on_approval((select id from approval_request where doc_id = '70000000-0000-0000-0000-000000000002'), 'approve', null, 'whatsapp')).status = 'approved',
            'owner approves from WhatsApp: PO approved');
select t.ok((select array_agg(action order by acted_at) from approval_action a join approval_request r on r.id = a.request_id
             where r.doc_id = '70000000-0000-0000-0000-000000000002') = '{submit,approve,approve}',
            'approval trail records every step');
reset role;

-- ---------------------------------------------------------------------------
\echo '== Audit log'
-- ---------------------------------------------------------------------------
select t.login('40000000-0000-0000-0000-00000000000e');
select set_config('request.headers', '{"x-source":"mobile","x-device-id":"phone-acct","x-reason":"customer changed number","x-correlation-id":"corr-1"}', false);
update party set mobile = '9123456789' where party_code = 'C001';
select set_config('request.headers', '', false);
select t.ok((select changed_fields from record_history where table_name = 'public.party' and action = 'UPDATE') = '{mobile}',
            'history shows exactly which field changed');
select t.ok((select actor_name || '|' || source || '|' || device_id || '|' || reason from record_history
             where table_name = 'public.party' and action = 'UPDATE') = 'Accountant|mobile|phone-acct|customer changed number',
            'history shows who, from which device, and why');
select t.ok((select old_data ->> 'mobile' || '>' || (new_data ->> 'mobile') from record_history
             where table_name = 'public.party' and action = 'UPDATE') = '9876543210>9123456789',
            'history keeps the before and after values');
reset role;

-- Client headers cannot pretend to be an AI agent or act on behalf of someone else.
select t.login('40000000-0000-0000-0000-00000000000e');
select set_config('request.headers', '{"x-actor-type":"ai_agent","x-on-behalf-of":"40000000-0000-0000-0000-00000000000a"}', false);
update party set email = 'a@b.in' where party_code = 'C001';
select set_config('request.headers', '', false);
select t.ok((select actor_type = 'user' and on_behalf_of is null from audit.log where table_name = 'public.party' and changed_fields = '{email}'),
            'actor type and on-behalf-of cannot be forged from request headers');
reset role;

-- Server-side AI agent acting for the accountant.
begin;
select audit.set_context(p_source => 'ai', p_actor_type => 'ai_agent', p_on_behalf_of => '40000000-0000-0000-0000-00000000000e',
                         p_correlation_id => 'zadk-abc');
select t.login('40000000-0000-0000-0000-00000000000e');
update party set whatsapp = '9123456789' where party_code = 'C001';
commit;
reset role;
select t.ok((select actor_type || '|' || correlation_id from audit.log where changed_fields = '{whatsapp}') = 'ai_agent|zadk-abc',
            'AI changes are marked as AI, linked to the Zentrix ADK correlation id');

select t.login('40000000-0000-0000-0000-00000000000b');
select t.ok((select count(*) from record_history) = 0, 'operator without audit permission sees no history');
reset role;

select t.login('40000000-0000-0000-0000-00000000000d');
select t.ok((select count(*) from record_history where tenant_id = '10000000-0000-0000-0000-000000000001') = 0, 'other tenants never see our audit log');
reset role;

select t.login('40000000-0000-0000-0000-00000000000a');
select t.ok((select count(*) from audit.verify_chain('10000000-0000-0000-0000-000000000001')) = 0, 'audit chain verifies');
do $$ begin
  update audit.log set reason = 'nothing to see' where id = 1;
  raise exception 'FAIL: audit log was edited';
exception when insufficient_privilege then perform t.ok(true, 'audit log cannot be edited');
end $$;
do $$ begin
  delete from audit.log where id = 1;
  raise exception 'FAIL: audit log row deleted';
exception when insufficient_privilege then perform t.ok(true, 'audit log rows cannot be deleted');
end $$;
reset role;

-- A database superuser bypasses the guard and edits a record: verification catches it.
alter table audit.log disable trigger no_update_delete;
update audit.log set new_data = jsonb_set(new_data, '{mobile}', '"9999999999"')
where table_name = 'public.party' and action = 'UPDATE' and changed_fields = '{mobile}';
alter table audit.log enable trigger no_update_delete;

select t.login('40000000-0000-0000-0000-00000000000a');
select t.ok((select problem from audit.verify_chain('10000000-0000-0000-0000-000000000001') limit 1) = 'record content was altered',
            'tampering by a superuser is detected');
reset role;

alter table audit.log disable trigger no_update_delete;
delete from audit.log where tenant_id = '10000000-0000-0000-0000-000000000001'
  and seq = (select max(seq) from audit.log where tenant_id = '10000000-0000-0000-0000-000000000001');
alter table audit.log enable trigger no_update_delete;
select t.login('40000000-0000-0000-0000-00000000000a');
select t.ok(exists (select 1 from audit.verify_chain('10000000-0000-0000-0000-000000000001') where problem like 'chain head%'),
            'removing the newest record is detected');
reset role;

\echo '== all core tests passed'
