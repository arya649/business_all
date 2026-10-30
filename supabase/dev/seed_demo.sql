-- Demo group for the local dev stack: three companies, six locations, five people, a month of activity.
-- All records go through the same erp_* functions as the apps (as the owner), so rules, postings and audit apply.
\set ON_ERROR_STOP 1

insert into tenant (id, name) values ('a0000000-0000-0000-0000-000000000001', 'Sri Lakshmi Group');
insert into company (id, tenant_id, legal_name, short_code, pan) values
  ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Sri Lakshmi Infra & RMC Pvt Ltd', 'SLRMC', 'AAKCS4521K'),
  ('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Sri Lakshmi Fuels', 'SLFUEL', 'AAKFS7812L'),
  ('c0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Sri Lakshmi Asphalt LLP', 'SLASP', 'AAJFS1209M');
insert into company_gstin (id, tenant_id, company_id, gstin, e_invoice_enabled, eway_enabled) values
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', '37AAKCS4521K1Z2', true, true),
  ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', '37AAKFS7812L1Z9', false, false),
  ('d0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003', '37AAJFS1209M1Z4', true, true);
insert into location (id, tenant_id, company_id, gstin_id, type, name, short_code, lat, lng) values
  ('e0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'plant', 'Vijayawada RMC plant', 'VJA', 16.5062, 80.6480),
  ('e0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'site', 'Guntur bypass road project', 'GBR', 16.3067, 80.4365),
  ('e0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'plant', 'Kondapalli brick unit', 'KBU', 16.6200, 80.5400),
  ('e0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000002', 'bunk', 'NH16 Gannavaram bunk', 'GNV', 16.5400, 80.8000),
  ('e0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000003', 'plant', 'Ibrahimpatnam hot-mix plant', 'IBP', 16.5900, 80.5200);

insert into auth.users (id, email, phone, encrypted_password) values
  ('b0000000-0000-0000-0000-000000000001', 'owner@demo.in', '+919000000001', extensions.crypt('demo1234', extensions.gen_salt('bf'))),
  ('b0000000-0000-0000-0000-000000000002', null, '+919000000002', null),
  ('b0000000-0000-0000-0000-000000000003', null, '+919000000003', null),
  ('b0000000-0000-0000-0000-000000000004', null, '+919000000004', null),
  ('b0000000-0000-0000-0000-000000000005', 'accounts@demo.in', '+919000000005', extensions.crypt('demo1234', extensions.gen_salt('bf')));
insert into app_user (id, tenant_id, full_name, mobile, email, is_tenant_admin, preferred_language) values
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Venkata Rao (Owner)', '9000000001', 'owner@demo.in', true, 'en'),
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Srinu (Bunk cashier)', '9000000002', null, false, 'te'),
  ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Ramesh (Site engineer)', '9000000003', null, false, 'te'),
  ('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Kiran (Plant operator)', '9000000004', null, false, 'te'),
  ('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'Lakshmi (Accounts)', '9000000005', 'accounts@demo.in', false, 'en');

insert into role (id, tenant_id, name, ui_mode) values
  ('f0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Bunk cashier', 'simple'),
  ('f0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Site engineer', 'simple'),
  ('f0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Plant operator', 'simple'),
  ('f0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Accountant', 'power');
insert into role_permission (role_id, feature_key, actions, masked_fields) values
  ('f0000000-0000-0000-0000-000000000001', 'bunk.shift', '{view,create,edit,print}', '{}'),
  ('f0000000-0000-0000-0000-000000000001', 'bunk.tanks.daily_dip', '{view,create}', '{book_litres,variance_litres,variance_alert}'),
  ('f0000000-0000-0000-0000-000000000001', 'bunk.internal_fuel_issue', '{view,create,print}', '{transfer_rate,amount}'),
  ('f0000000-0000-0000-0000-000000000001', 'bunk.lubes', '{view,create,print}', '{}'),
  ('f0000000-0000-0000-0000-000000000002', 'infra.dpr', '{view,create,edit}', '{}'),
  ('f0000000-0000-0000-0000-000000000002', 'infra.labour_attendance', '{view,create,edit}', '{wage_rate}'),
  ('f0000000-0000-0000-0000-000000000002', 'infra.material_request', '{view,create}', '{}'),
  ('f0000000-0000-0000-0000-000000000002', 'infra.projects', '{view}', '{contract_value,retention_pct,security_deposit_pct}'),
  ('f0000000-0000-0000-0000-000000000002', 'finance.receipts_payments', '{view,create}', '{}'),
  ('f0000000-0000-0000-0000-000000000003', 'rmc.batch_entry', '{view,create}', '{}'),
  ('f0000000-0000-0000-0000-000000000003', 'rmc.delivery_challan', '{view,create,print}', '{}'),
  ('f0000000-0000-0000-0000-000000000003', 'rmc.orders', '{view}', '{rate_per_m3,pump_charge,order_value,outstanding_at_order}'),
  ('f0000000-0000-0000-0000-000000000003', 'weighbridge.tickets', '{view,create,edit}', '{weighing_charge}'),
  ('f0000000-0000-0000-0000-000000000003', 'fleet.fuel_log', '{view,create}', '{}'),
  ('f0000000-0000-0000-0000-000000000004', 'finance', '{view,create,edit,approve,export,print,see_rates,see_cost}', '{}'),
  ('f0000000-0000-0000-0000-000000000004', 'purchase', '{view,create,edit,export,print,see_rates}', '{}'),
  ('f0000000-0000-0000-0000-000000000004', 'core.masters', '{view,create,edit}', '{}'),
  ('f0000000-0000-0000-0000-000000000004', 'core.audit', '{view}', '{}'),
  ('f0000000-0000-0000-0000-000000000004', 'core.dashboard', '{view}', '{}');
insert into user_assignment (tenant_id, user_id, company_id, location_id, role_id) values
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000004', 'f0000000-0000-0000-0000-000000000001'),
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000002'),
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000003'),
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000001', null, 'f0000000-0000-0000-0000-000000000004'),
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000002', null, 'f0000000-0000-0000-0000-000000000004'),
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000003', null, 'f0000000-0000-0000-0000-000000000004');
update location set in_charge_user_id = 'b0000000-0000-0000-0000-000000000004' where id = 'e0000000-0000-0000-0000-000000000001';

-- masters
insert into party (id, tenant_id, party_code, display_name, party_types, mobile, pan) values
  ('70000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'C001', 'Sai Krishna Builders', '{customer,bunk_credit}', '9848012345', 'AAGFS1234P'),
  ('70000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'C002', 'Amaravati Homes', '{customer}', '9848022222', null),
  ('70000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'C003', 'Krishna Transport Co', '{customer,bunk_credit}', '9848033333', null),
  ('70000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'G001', 'R&B Dept, Guntur Division', '{customer,govt_dept}', null, null),
  ('70000000-0000-0000-0000-000000000011', 'a0000000-0000-0000-0000-000000000001', 'V001', 'Ultratech Cement (Depot VJA)', '{vendor}', '9848044444', 'AAACU1234Q'),
  ('70000000-0000-0000-0000-000000000012', 'a0000000-0000-0000-0000-000000000001', 'V002', 'Sri Venkateswara Stone Crushers', '{vendor}', '9848055555', null),
  ('70000000-0000-0000-0000-000000000013', 'a0000000-0000-0000-0000-000000000001', 'V003', 'IOCL Depot Kondapalli', '{vendor}', null, null);
insert into party (id, tenant_id, party_code, display_name, party_types, group_company_id) values
  ('70000000-0000-0000-0000-000000000021', 'a0000000-0000-0000-0000-000000000001', 'IC-RMC', 'Sri Lakshmi Infra & RMC (group)', '{customer,vendor}', 'c0000000-0000-0000-0000-000000000001'),
  ('70000000-0000-0000-0000-000000000022', 'a0000000-0000-0000-0000-000000000001', 'IC-FUEL', 'Sri Lakshmi Fuels (group)', '{customer,vendor}', 'c0000000-0000-0000-0000-000000000002'),
  ('70000000-0000-0000-0000-000000000023', 'a0000000-0000-0000-0000-000000000001', 'IC-ASP', 'Sri Lakshmi Asphalt (group)', '{customer,vendor}', 'c0000000-0000-0000-0000-000000000003');
insert into party_gstin (tenant_id, party_id, gstin) values
  ('a0000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', '37AAGFS1234P1Z8'),
  ('a0000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000011', '37AAACU1234Q1Z1');
insert into party_company (tenant_id, party_id, company_id, credit_limit, credit_days) values
  ('a0000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 800000, 30),
  ('a0000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 300000, 15),
  ('a0000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 150000, 15),
  ('a0000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000002', 250000, 15);
insert into item (id, tenant_id, item_code, name, local_name, category, base_uom, hsn_sac, gst_rate) values
  ('71000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'CEM-OPC53', 'Cement OPC 53', 'సిమెంట్', 'raw_material', 'KG', '2523', 18),
  ('71000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'AGG-20', 'Aggregate 20 mm', 'కంకర 20', 'raw_material', 'KG', '2517', 5),
  ('71000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'AGG-10', 'Aggregate 10 mm', 'కంకర 10', 'raw_material', 'KG', '2517', 5),
  ('71000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'MSAND', 'M-sand', 'ఇసుక', 'raw_material', 'KG', '2505', 5),
  ('71000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'FLYASH', 'Fly ash', 'ఫ్లై యాష్', 'raw_material', 'KG', '2621', 5),
  ('71000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001', 'ADMIX', 'Admixture PCE', null, 'raw_material', 'KG', '3824', 18),
  ('71000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000001', 'VG30', 'Bitumen VG-30', 'తారు', 'raw_material', 'KG', '2713', 18),
  ('71000000-0000-0000-0000-000000000008', 'a0000000-0000-0000-0000-000000000001', 'FAB-9', 'Fly ash brick 9 in', 'ఇటుక', 'finished_good', 'NOS', '6815', 5),
  ('71000000-0000-0000-0000-000000000009', 'a0000000-0000-0000-0000-000000000001', 'LUBE-15W40', 'Engine oil 15W-40 (5 L)', null, 'lube', 'NOS', '2710', 18);
insert into vehicle (id, tenant_id, reg_no, kind, owning_company_id, capacity, capacity_uom, standard_tare_kg, norm_km_per_l, tank_capacity_l, current_location_id, rfid_tag) values
  ('72000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'AP16TX4521', 'transit_mixer', 'c0000000-0000-0000-0000-000000000001', 7, 'M3', 14200, 3.2, 300, 'e0000000-0000-0000-0000-000000000001', 'RF0001'),
  ('72000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'AP16TX4522', 'transit_mixer', 'c0000000-0000-0000-0000-000000000001', 7, 'M3', 14150, 3.2, 300, 'e0000000-0000-0000-0000-000000000001', 'RF0002'),
  ('72000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'AP16TB7788', 'tipper', 'c0000000-0000-0000-0000-000000000003', 20, 'MT', 11800, 3.8, 250, 'e0000000-0000-0000-0000-000000000005', 'RF0003');
insert into vehicle (id, tenant_id, reg_no, kind, owning_company_id, norm_l_per_hour, meter_type, current_location_id) values
  ('72000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'JCB3DX0042', 'loader', 'c0000000-0000-0000-0000-000000000001', 5.5, 'hours', 'e0000000-0000-0000-0000-000000000002');
insert into vehicle_document (tenant_id, vehicle_id, doc_type, doc_number, expires_on) values
  ('a0000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001', 'insurance', 'POL-99121', current_date + 12),
  ('a0000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000002', 'fitness', 'FC-2231', current_date - 3),
  ('a0000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000003', 'puc', 'PUC-5512', current_date + 25);

-- AI switched off at the brick unit; density field hidden at the bunk (attendants don't have hydrometers yet)
insert into feature_flag (tenant_id, feature_key, level, level_id, state, config) values
  ('a0000000-0000-0000-0000-000000000001', 'ai', 'location', 'e0000000-0000-0000-0000-000000000003', 'off', null),
  ('a0000000-0000-0000-0000-000000000001', 'bunk.tanks.daily_dip', 'location', 'e0000000-0000-0000-0000-000000000004', null, '{"hidden_fields": ["density", "temperature_c"]}');

-- approval rules
insert into approval_rule (id, tenant_id, doc_type, name, conditions) values
  ('73000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'purchase.po', 'POs above ₹1 lakh', '[{"field":"amount","op":">","value":100000}]'),
  ('73000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'finance.expense', 'Expenses above ₹5,000', '[{"field":"amount","op":">","value":5000}]'),
  ('73000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'rmc.order', 'Credit override for RMC', '[{"field":"credit_check","op":"=","value":"over_limit"}]');
insert into approval_rule_step (tenant_id, rule_id, step_no, approver_type, sla_hours) values
  ('a0000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000001', 1, 'tenant_admin', 24),
  ('a0000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000002', 1, 'tenant_admin', 24),
  ('a0000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000003', 1, 'tenant_admin', 4);

-- ---------------------------------------------------------------------------
-- A month of activity, entered as the owner through the app's own functions
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"b0000000-0000-0000-0000-000000000001","role":"authenticated"}', false);

do $$
declare
  rmc  uuid := 'c0000000-0000-0000-0000-000000000001';
  fuel uuid := 'c0000000-0000-0000-0000-000000000002';
  asp  uuid := 'c0000000-0000-0000-0000-000000000003';
  vja  uuid := 'e0000000-0000-0000-0000-000000000001';
  gbr  uuid := 'e0000000-0000-0000-0000-000000000002';
  kbu  uuid := 'e0000000-0000-0000-0000-000000000003';
  gnv  uuid := 'e0000000-0000-0000-0000-000000000004';
  ibp  uuid := 'e0000000-0000-0000-0000-000000000005';
  v jsonb; tank uuid; tank2 uuid; noz1 uuid; noz2 uuid; noz3 uuid; mix uuid; ord uuid; b jsonb; proj uuid; boq1 uuid; boq2 uuid;
  jmf uuid; d date; i int; tot numeric := 125000; tot2 numeric := 88000; tot3 numeric := 40100; dipmm numeric := 1600; sh jsonb;
begin
  -- stock in by GRN at the RMC plant
  perform erp_save('purchase.grn', jsonb_build_object('company_id', rmc, 'location_id', vja, 'doc_date', current_date - 28,
    'party_id', '70000000-0000-0000-0000-000000000011', 'vendor_challan_no', 'UTC/88123',
    'lines', jsonb_build_array(jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'received_qty', 120000, 'rate', 7.3),
                               jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000005', 'received_qty', 40000, 'rate', 1.4),
                               jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000006', 'received_qty', 1500, 'rate', 95))));
  perform erp_save('purchase.grn', jsonb_build_object('company_id', rmc, 'location_id', vja, 'doc_date', current_date - 27,
    'party_id', '70000000-0000-0000-0000-000000000012',
    'lines', jsonb_build_array(jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000002', 'received_qty', 600000, 'rate', 0.85),
                               jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000003', 'received_qty', 300000, 'rate', 0.9),
                               jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000004', 'received_qty', 500000, 'rate', 0.7))));
  update item_location set reorder_level = 0 where false;
  insert into item_location (tenant_id, item_id, location_id, reorder_level) values
    ('a0000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', vja, 60000);

  -- RMC: mix designs M20 and M25
  v := erp_save('rmc.mix_design', jsonb_build_object('company_id', rmc, 'location_id', vja, 'grade', 'M25', 'mix_code', 'VJA-M25-01',
    'effective_from', current_date - 60, 'selling_price_per_m3', 5150, 'material_cost_per_m3', 3480, 'slump_target_mm', 120, 'cement_type', 'OPC53',
    'materials', jsonb_build_array(
      jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'qty_per_m3', 330),
      jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000005', 'qty_per_m3', 70),
      jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000002', 'qty_per_m3', 720),
      jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000003', 'qty_per_m3', 480),
      jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000004', 'qty_per_m3', 760),
      jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000006', 'qty_per_m3', 3.2))));
  perform erp_set_status('rmc.mix_design', (v ->> 'id')::uuid, 'submit');
  v := erp_save('rmc.mix_design', jsonb_build_object('company_id', rmc, 'location_id', vja, 'grade', 'M20', 'mix_code', 'VJA-M20-01',
    'effective_from', current_date - 60, 'selling_price_per_m3', 4750, 'material_cost_per_m3', 3150,
    'materials', jsonb_build_array(
      jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'qty_per_m3', 290),
      jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000005', 'qty_per_m3', 80),
      jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000002', 'qty_per_m3', 740),
      jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000004', 'qty_per_m3', 800))));
  perform erp_set_status('rmc.mix_design', (v ->> 'id')::uuid, 'submit');

  -- RMC orders, batches, signed challans over the month
  for i in 1..10 loop
    d := current_date - 26 + i * 2;
    v := erp_save('rmc.order', jsonb_build_object('company_id', rmc, 'location_id', vja, 'doc_date', d - 1,
      'party_id', case when i % 3 = 0 then '70000000-0000-0000-0000-000000000002' else '70000000-0000-0000-0000-000000000001' end,
      'site_name', case when i % 3 = 0 then 'Amaravati Homes Block ' || i else 'Sai Krishna Villas, Gollapudi' end,
      'grade', case when i % 2 = 0 then 'M25' else 'M20' end, 'qty_m3', 14, 'element', 'slab',
      'pour_start', (d + time '07:00')::timestamptz, 'pump', 'boom', 'pump_charge', 5000));
    ord := (v ->> 'id')::uuid;
    perform erp_set_status('rmc.order', ord, 'submit');
    b := erp_save('rmc.batch', jsonb_build_object('company_id', rmc, 'location_id', vja, 'doc_date', d, 'order_id', ord,
      'vehicle_id', '72000000-0000-0000-0000-000000000001', 'qty_m3', 7));
    perform erp_save('rmc.challan', jsonb_build_object('company_id', rmc, 'location_id', vja, 'doc_date', d, 'order_id', ord,
      'batch_id', b ->> 'id', 'qty_m3', 7, 'vehicle_id', '72000000-0000-0000-0000-000000000001', 'receiver_name', 'Site supervisor',
      'left_plant_at', (d + time '06:40')::timestamptz, 'reached_site_at', (d + time '07:05')::timestamptz,
      'pour_start_at', (d + time '07:50')::timestamptz, 'pour_end_at', (d + time '08:30')::timestamptz));
    b := erp_save('rmc.batch', jsonb_build_object('company_id', rmc, 'location_id', vja, 'doc_date', d, 'order_id', ord,
      'vehicle_id', '72000000-0000-0000-0000-000000000002', 'qty_m3', 7));
    perform erp_save('rmc.challan', jsonb_build_object('company_id', rmc, 'location_id', vja, 'doc_date', d, 'order_id', ord,
      'batch_id', b ->> 'id', 'qty_m3', 7, 'vehicle_id', '72000000-0000-0000-0000-000000000002',
      'receiver_name', case when i < 9 then 'Site supervisor' end));
  end loop;
  -- one batch with too much cement
  perform erp_save('rmc.batch', jsonb_build_object('company_id', rmc, 'location_id', vja, 'doc_date', current_date - 1, 'order_id', ord,
    'vehicle_id', '72000000-0000-0000-0000-000000000001', 'qty_m3', 6,
    'materials', jsonb_build_array(jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'actual_qty', 2150),
                                   jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000002', 'actual_qty', 4440))));
  -- bill the first fortnight; approve it
  for v in select to_jsonb(r) from billing_run('rmc.challan', rmc, vja, current_date - 14) r loop
    perform erp_set_status('finance.sales_invoice', (v ->> 'invoice_id')::uuid, 'submit');
  end loop;
  perform erp_save('finance.receipt', jsonb_build_object('company_id', rmc, 'location_id', vja, 'doc_date', current_date - 5,
    'party_id', '70000000-0000-0000-0000-000000000001', 'amount', 150000, 'mode', 'neft_rtgs', 'reference_no', 'UTR8812234'));
  -- an order from a customer over the limit: waits for the owner's credit override
  v := erp_save('rmc.order', jsonb_build_object('company_id', rmc, 'location_id', vja, 'party_id', '70000000-0000-0000-0000-000000000002',
    'site_name', 'Amaravati Homes Block 12', 'grade', 'M25', 'qty_m3', 60, 'pour_start', now() + interval '2 days'));
  perform erp_set_status('rmc.order', (v ->> 'id')::uuid, 'submit');

  -- weighbridge at the plant: cement and aggregate inward, one tipper with a heavy tare
  for i in 1..6 loop
    v := erp_save('weighbridge.ticket', jsonb_build_object('company_id', rmc, 'location_id', vja, 'doc_date', current_date - i * 3,
      'ticket_type', 'purchase_inward', 'vehicle_no', 'AP0' || (7 + i) || 'TC' || (1000 + i * 37), 'party_id', '70000000-0000-0000-0000-000000000012',
      'item_id', '71000000-0000-0000-0000-000000000002', 'first_weight_kg', 38000 + i * 150, 'party_qty_kg', 26000));
    perform erp_save('weighbridge.ticket', jsonb_build_object('id', v ->> 'id', 'second_weight_kg', 12100 + i * 40));
  end loop;
  v := erp_save('weighbridge.ticket', jsonb_build_object('company_id', rmc, 'location_id', vja, 'ticket_type', 'sales_dispatch',
    'vehicle_no', 'AP16TX4521', 'first_weight_kg', 14780));
  perform erp_save('weighbridge.ticket', jsonb_build_object('id', v ->> 'id', 'second_weight_kg', 31200));
  perform erp_save('weighbridge.ticket', jsonb_build_object('company_id', rmc, 'location_id', vja, 'ticket_type', 'purchase_inward',
    'vehicle_no', 'TS09UB4410', 'first_weight_kg', 40100, 'first_mode', 'manual', 'manual_reason', 'Scale display not stable'));

  -- petrol bunk: tank with chart, three nozzles, prices
  v := erp_save('bunk.tank', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'name', 'Tank 1 · HSD', 'product', 'HSD', 'capacity_l', 20000,
    'calibration_chart', '[[0,0],[500,3200],[1000,7900],[1500,12600],[2000,17000],[2300,20000]]'::jsonb));
  tank := (v ->> 'id')::uuid;
  v := erp_save('bunk.tank', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'name', 'Tank 2 · MS', 'product', 'MS', 'capacity_l', 15000,
    'calibration_chart', '[[0,0],[500,2900],[1000,6800],[1500,10800],[2000,15000]]'::jsonb));
  tank2 := (v ->> 'id')::uuid;
  noz1 := (erp_save('bunk.nozzle', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'name', 'DU1-N1 HSD', 'dispenser', 'DU1', 'tank_id', tank, 'current_totaliser', tot)) ->> 'id')::uuid;
  noz2 := (erp_save('bunk.nozzle', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'name', 'DU1-N2 HSD', 'dispenser', 'DU1', 'tank_id', tank, 'current_totaliser', tot2)) ->> 'id')::uuid;
  noz3 := (erp_save('bunk.nozzle', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'name', 'DU2-N1 MS', 'dispenser', 'DU2', 'tank_id', tank2, 'current_totaliser', tot3)) ->> 'id')::uuid;
  perform erp_save('bunk.price', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'product', 'HSD', 'rsp', 89.62, 'effective_from', now() - interval '40 days'));
  perform erp_save('bunk.price', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'product', 'MS', 'rsp', 109.46, 'effective_from', now() - interval '40 days'));

  perform erp_save('bunk.dip', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'doc_date', current_date - 15, 'tank_id', tank, 'dip_mm', dipmm));
  for i in 1..14 loop
    d := current_date - 15 + i - 1;
    sh := erp_save('bunk.shift', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'doc_date', d, 'shift_name', 'full_day',
      'attendant_id', 'b0000000-0000-0000-0000-000000000002', 'opened_at', (d + time '06:00')::timestamptz));
    sh := erp_save('bunk.shift', jsonb_build_object('id', sh ->> 'id',
      'readings', jsonb_build_array(
        jsonb_build_object('nozzle_id', noz1, 'opening', tot, 'closing', tot + 420 + i * 7, 'testing', 5),
        jsonb_build_object('nozzle_id', noz2, 'opening', tot2, 'closing', tot2 + 300 + i * 5, 'testing', 5),
        jsonb_build_object('nozzle_id', noz3, 'opening', tot3, 'closing', tot3 + 510 + i * 3, 'testing', 5)),
      'credit', case when i % 3 = 0 then jsonb_build_array(jsonb_build_object('party_id', '70000000-0000-0000-0000-000000000003',
                                                                              'vehicle_no', 'AP16TT2210', 'product', 'HSD', 'litres', 120, 'slip_no', 'KT-' || i)) else '[]'::jsonb end,
      'upi_pos', 31000 + i * 120));
    tot := tot + 420 + i * 7; tot2 := tot2 + 300 + i * 5; tot3 := tot3 + 510 + i * 3;
    sh := erp_save('bunk.shift', jsonb_build_object('id', sh ->> 'id',
      'cash_counted', (sh ->> 'expected_collection')::numeric - case when i in (4, 11) then 1200 else 0 end,
      'closed_at', (d + time '22:00')::timestamptz));
    perform erp_set_status('bunk.shift', (sh ->> 'id')::uuid, 'submit');
    -- morning dip; day 9 shows a loss beyond tolerance
    dipmm := dipmm - ((420 + i * 7 + 300 + i * 5 - 10) / 9.4) - case when i = 9 then 30 else 0 end;
    if i % 7 = 0 then
      perform erp_save('bunk.tanker_receipt', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'doc_date', d + 1, 'tank_id', tank,
        'supplier_id', '70000000-0000-0000-0000-000000000013', 'invoice_no', 'IOC/' || (55100 + i), 'invoice_litres', 12000,
        'invoice_density', 832.5, 'observed_density', case when i = 14 then 828.1 else 832.2 end, 'tanker_no', 'AP16TK' || (4400 + i),
        'received_litres', case when i = 14 then 11940 else 11995 end, 'invoice_amount', 12000 * 86.1));
    end if;
    perform erp_save('bunk.dip', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'doc_date', d + 1, 'tank_id', tank, 'dip_mm', round(dipmm)));
  end loop;
  -- fuel to the group's transit mixers and tipper
  for i in 1..5 loop
    perform erp_save('bunk.internal_issue', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'doc_date', current_date - i * 4,
      'vehicle_id', case when i % 2 = 0 then '72000000-0000-0000-0000-000000000002' else '72000000-0000-0000-0000-000000000001' end,
      'litres', 140 + i * 5, 'odometer', 45000 + (6 - i) * 420));
  end loop;
  perform erp_save('bunk.internal_issue', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'doc_date', current_date - 2,
    'vehicle_id', '72000000-0000-0000-0000-000000000003', 'litres', 180, 'odometer', 61200));
  perform erp_save('bunk.internal_issue', jsonb_build_object('company_id', fuel, 'location_id', gnv, 'doc_date', current_date - 1,
    'vehicle_id', '72000000-0000-0000-0000-000000000003', 'litres', 175, 'odometer', 61610));

  -- project at Guntur
  v := erp_save('infra.project', jsonb_build_object('company_id', rmc, 'location_id', gbr, 'name', 'Guntur bypass 4-laning, package 2',
    'client_id', '70000000-0000-0000-0000-000000000004', 'work_order_no', 'R&B/GNT/2026/114', 'contract_value', 248000000,
    'start_date', current_date - 120, 'end_date', current_date + 420, 'mobilisation_advance', 12400000, 'mobilisation_recovery_pct', 10,
    'manager_id', 'b0000000-0000-0000-0000-000000000003'));
  proj := (v ->> 'id')::uuid;
  boq1 := (erp_save('infra.boq_item', jsonb_build_object('company_id', rmc, 'location_id', gbr, 'project_id', proj, 'item_no', '3.2',
    'description', 'Granular sub-base, grading II', 'unit', 'm3', 'contract_qty', 42000, 'rate', 1450)) ->> 'id')::uuid;
  boq2 := (erp_save('infra.boq_item', jsonb_build_object('company_id', rmc, 'location_id', gbr, 'project_id', proj, 'item_no', '5.1',
    'description', 'Dense bituminous macadam 50 mm', 'unit', 'm2', 'contract_qty', 180000, 'rate', 410)) ->> 'id')::uuid;
  for i in 1..8 loop
    v := erp_save('infra.dpr', jsonb_build_object('company_id', rmc, 'location_id', gbr, 'doc_date', current_date - 10 + i, 'project_id', proj,
      'weather', case when i = 5 then 'rain' else 'clear' end,
      'hindrance_cause', case when i = 5 then 'rain' when i = 6 then 'drawing_pending' else 'none' end,
      'hindrances', case when i = 6 then 'Culvert at Ch 14+300 drawing not given by client' end,
      'work', jsonb_build_array(jsonb_build_object('boq_item_id', boq1, 'qty', case when i = 5 then 0 else 380 + i * 10 end, 'location_detail', 'Ch ' || (12 + i * 0.2) || ' LHS'),
                                jsonb_build_object('boq_item_id', boq2, 'qty', case when i > 4 then 2600 else 0 end)),
      'labour', jsonb_build_array(jsonb_build_object('trade', 'helper', 'count', 24 + i % 4), jsonb_build_object('trade', 'operator', 'count', 6),
                                  jsonb_build_object('trade', 'supervisor', 'count', 2))));
    if i < 8 then perform erp_set_status('infra.dpr', (v ->> 'id')::uuid, 'submit'); end if;
  end loop;
  v := erp_save('infra.ra_bill', jsonb_build_object('company_id', rmc, 'location_id', gbr, 'project_id', proj, 'period_to', current_date - 3,
    'lines', jsonb_build_array(jsonb_build_object('boq_item_id', boq1, 'this_qty', 2400))));
  perform erp_set_status('infra.ra_bill', (v ->> 'id')::uuid, 'submit');

  -- hot-mix plant
  v := erp_save('bitumen.jmf', jsonb_build_object('company_id', asp, 'location_id', ibp, 'mix_type', 'DBM', 'jmf_code', 'IBP-DBM-G2',
    'bitumen_pct', 4.5, 'bitumen_grade', 'VG30', 'price_per_mt', 5600, 'cost_per_mt', 4300));
  jmf := (v ->> 'id')::uuid;
  perform erp_set_status('bitumen.jmf', jmf, 'submit');
  for i in 1..6 loop
    perform erp_save('bitumen.batch', jsonb_build_object('company_id', asp, 'location_id', ibp, 'doc_date', current_date - 7 + i, 'jmf_id', jmf,
      'batch_mt', 60, 'mix_temp_c', case when i = 3 then 171 else 158 end));
    perform erp_save('bitumen.dispatch', jsonb_build_object('company_id', asp, 'location_id', ibp, 'doc_date', current_date - 7 + i,
      'party_id', '70000000-0000-0000-0000-000000000021', 'mix_type', 'DBM', 'vehicle_id', '72000000-0000-0000-0000-000000000003',
      'net_mt', 19.6, 'dispatch_temp_c', 152, 'arrival_temp_c', 141, 'tarpaulin_covered', true, 'rate_per_mt', 5600,
      'site_name', 'Guntur bypass pkg 2'));
  end loop;

  -- bricks
  perform erp_save('bricks.recipe', jsonb_build_object('company_id', rmc, 'location_id', kbu, 'product_id', '71000000-0000-0000-0000-000000000008',
    'curing_days', 14, 'materials', jsonb_build_array(jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000005', 'qty', 1750),
                                                      jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'qty', 260),
                                                      jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000004', 'qty', 900))));
  for i in 1..10 loop
    perform erp_save('bricks.production', jsonb_build_object('company_id', rmc, 'location_id', kbu, 'doc_date', current_date - 25 + i * 2,
      'product_id', '71000000-0000-0000-0000-000000000008', 'good_units', 9200 + i * 40, 'rejected_units', 300, 'machine', 'Hydraulic press 1',
      'curing_block', 'B' || (1 + i % 3)));
  end loop;

  -- people and payroll
  for i in 1..6 loop
    perform erp_save('hr.employee', jsonb_build_object('company_id', rmc, 'location_id', vja, 'emp_code', 'VJA' || lpad(i::text, 3, '0'),
      'full_name', (array['Suresh Kumar', 'Naga Raju', 'Prasad B', 'Anil Kumar', 'Mahesh T', 'Ravi Teja'])[i], 'mobile', '98480' || lpad((1000 + i)::text, 5, '0'),
      'employment_type', case when i <= 2 then 'driver' else 'operator' end, 'designation', case when i <= 2 then 'TM driver' else 'Plant operator' end,
      'date_of_joining', current_date - 400, 'basic', 11000 + i * 500, 'da', 2000, 'hra', 2500, 'other_allowance', 1000,
      'pf_applicable', true, 'esi_applicable', true));
  end loop;

  -- expense and a PO waiting for the owner
  v := erp_save('finance.expense', jsonb_build_object('company_id', rmc, 'location_id', gbr, 'category', 'repairs', 'amount', 7800,
    'paid_by', 'petty_cash', 'description', 'JCB hydraulic hose replaced'));
  perform erp_set_status('finance.expense', (v ->> 'id')::uuid, 'submit');
  v := erp_save('purchase.po', jsonb_build_object('company_id', rmc, 'location_id', vja, 'party_id', '70000000-0000-0000-0000-000000000011',
    'lines', jsonb_build_array(jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'qty', 60000, 'rate', 7.45))));
  perform erp_set_status('purchase.po', (v ->> 'id')::uuid, 'submit');

  -- a CRM lead or two
  perform erp_save('crm.lead', jsonb_build_object('company_id', rmc, 'location_id', vja, 'contact_name', 'Satyanarayana', 'mobile', '9849011122',
    'company_name', 'SNR Constructions', 'business_line', 'rmc', 'source', 'whatsapp', 'requirement', '45 m³ M25 for raft, next Monday',
    'expected_value', 230000, 'next_follow_up_at', now() + interval '1 day', 'owner_id', 'b0000000-0000-0000-0000-000000000001'));
  perform erp_save('crm.lead', jsonb_build_object('company_id', rmc, 'location_id', vja, 'contact_name', 'Madhavi', 'mobile', '9849033344',
    'business_line', 'bricks', 'source', 'walk_in', 'requirement', '30,000 fly ash bricks for G+2', 'stage', 'quote_sent'));
end $$;

select set_config('request.jwt.claims', '', false);
