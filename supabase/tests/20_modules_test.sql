-- End-to-end module flows through the same erp_* functions the apps use.
\set ON_ERROR_STOP 1
\set QUIET 1

-- ---------------------------------------------------------------------------
-- Fixture: "Lakshmi Group" with an RMC company and a fuels company
-- ---------------------------------------------------------------------------
insert into tenant (id, name) values ('11000000-0000-0000-0000-000000000001', 'Lakshmi Group');
insert into company (id, tenant_id, legal_name, short_code) values
  ('21000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', 'Lakshmi Infra & RMC', 'LRMC'),
  ('21000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000001', 'Lakshmi Fuels', 'LFUEL');
insert into company_gstin (id, tenant_id, company_id, gstin) values
  ('22000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', '37AAACL1234K1Z5');
insert into location (id, tenant_id, company_id, gstin_id, type, name, short_code) values
  ('31000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000001', 'plant', 'Gollapudi RMC', 'GLP'),
  ('31000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000002', null, 'bunk', 'NH16 Bunk', 'NH16'),
  ('31000000-0000-0000-0000-000000000003', '11000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', null, 'site', 'Guntur Road Project', 'GRP');

insert into auth.users (id) values
  ('41000000-0000-0000-0000-00000000000a'), ('41000000-0000-0000-0000-00000000000b'), ('41000000-0000-0000-0000-00000000000c');
insert into app_user (id, tenant_id, full_name, mobile, is_tenant_admin) values
  ('41000000-0000-0000-0000-00000000000a', '11000000-0000-0000-0000-000000000001', 'Lakshmi Owner', '9100000001', true),
  ('41000000-0000-0000-0000-00000000000b', '11000000-0000-0000-0000-000000000001', 'Bunk Cashier', '9100000002', false),
  ('41000000-0000-0000-0000-00000000000c', '11000000-0000-0000-0000-000000000001', 'Site Engineer', '9100000003', false);

insert into role (id, tenant_id, name) values
  ('51000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', 'Bunk Cashier'),
  ('51000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000001', 'Site Engineer');
insert into role_permission (role_id, feature_key, actions, masked_fields) values
  ('51000000-0000-0000-0000-000000000001', 'bunk.shift', '{view,create,edit}', '{}'),
  ('51000000-0000-0000-0000-000000000001', 'bunk.tanks.daily_dip', '{view,create}', '{density}'),
  ('51000000-0000-0000-0000-000000000002', 'infra', '{view,create}', '{}');
insert into user_assignment (tenant_id, user_id, company_id, location_id, role_id) values
  ('11000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-00000000000b', '21000000-0000-0000-0000-000000000002', '31000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000001'),
  ('11000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-00000000000c', '21000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000003', '51000000-0000-0000-0000-000000000002');

-- masters
insert into party (id, tenant_id, party_code, display_name, party_types) values
  ('61000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', 'C100', 'Sai Builders', '{customer,bunk_credit}'),
  ('61000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000001', 'V100', 'Ultra Cements', '{vendor}');
insert into party (id, tenant_id, party_code, display_name, party_types, group_company_id) values
  ('61000000-0000-0000-0000-000000000011', '11000000-0000-0000-0000-000000000001', 'IC-RMC', 'Lakshmi Infra & RMC', '{customer,vendor}', '21000000-0000-0000-0000-000000000001'),
  ('61000000-0000-0000-0000-000000000012', '11000000-0000-0000-0000-000000000001', 'IC-FUEL', 'Lakshmi Fuels', '{customer,vendor}', '21000000-0000-0000-0000-000000000002');
insert into party_company (tenant_id, party_id, company_id, credit_limit, credit_days) values
  ('11000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', 500000, 30),
  ('11000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000002', 20000, 15);
insert into item (id, tenant_id, item_code, name, category, base_uom, hsn_sac, gst_rate) values
  ('71000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', 'CEM53', 'Cement OPC 53', 'raw_material', 'KG', '2523', 18),
  ('71000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000001', 'AGG20', 'Aggregate 20mm', 'raw_material', 'KG', '2517', 5),
  ('71000000-0000-0000-0000-000000000003', '11000000-0000-0000-0000-000000000001', 'FLYASH', 'Fly ash', 'raw_material', 'KG', '2621', 5),
  ('71000000-0000-0000-0000-000000000004', '11000000-0000-0000-0000-000000000001', 'FAB9', 'Fly ash brick 9"', 'finished_good', 'NOS', '6815', 5);
insert into vehicle (id, tenant_id, reg_no, kind, owning_company_id, standard_tare_kg, norm_km_per_l, tank_capacity_l, current_location_id) values
  ('81000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', 'AP16TX4521', 'transit_mixer', '21000000-0000-0000-0000-000000000001', 14200, 3.5, 300, '31000000-0000-0000-0000-000000000001');

-- ===========================================================================
\echo '== Catalogue and field visibility'
-- ===========================================================================
select t.login('41000000-0000-0000-0000-00000000000b');

select t.ok((select array_agg(e ->> 'key' order by e ->> 'key') from jsonb_array_elements(erp_catalog('21000000-0000-0000-0000-000000000002', '31000000-0000-0000-0000-000000000002')) e)
            = '{bunk.dip,bunk.shift}', 'cashier sees only the shift and dip screens at the bunk');
select t.ok(not exists (select 1 from jsonb_array_elements(erp_catalog('21000000-0000-0000-0000-000000000002', '31000000-0000-0000-0000-000000000002')) e,
                        jsonb_array_elements(e -> 'fields') fl where e ->> 'key' = 'bunk.dip' and fl ->> 'name' = 'density'),
            'density is unticked for the cashier role, so it is not on their dip form');
do $$ begin
  perform erp_list('rmc.order', '21000000-0000-0000-0000-000000000001');
  raise exception 'FAIL: cashier listed RMC orders';
exception when insufficient_privilege then
  perform t.ok(sqlerrm like 'This module is not enabled%', 'cashier opening RMC orders: "This module is not enabled for your company or your account."');
end $$;
reset role;

-- ===========================================================================
\echo '== Petrol bunk: prices, tanks, shift, credit, group vehicle fuel, dip'
-- ===========================================================================
select t.login('41000000-0000-0000-0000-00000000000a');
select erp_save('bunk.tank', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000002', 'location_id', '31000000-0000-0000-0000-000000000002',
  'name', 'Tank 1 HSD', 'product', 'HSD', 'capacity_l', 20000,
  'calibration_chart', '[[0,0],[1000,8000],[2000,16500],[2400,20000]]'::jsonb)) ->> 'id' as tank_id \gset
select erp_save('bunk.nozzle', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000002', 'location_id', '31000000-0000-0000-0000-000000000002',
  'name', 'DU1-N1', 'tank_id', :'tank_id', 'current_totaliser', 125000)) ->> 'id' as nozzle_id \gset
select erp_save('bunk.price', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000002', 'location_id', '31000000-0000-0000-0000-000000000002',
  'product', 'HSD', 'rsp', 90.50, 'effective_from', now() - interval '1 day'));
select t.ok(tank_litres(:'tank_id', 1500) = 12250, 'dip 1500 mm reads 12,250 L from the calibration chart');

select erp_save('bunk.dip', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000002', 'location_id', '31000000-0000-0000-0000-000000000002',
  'doc_date', current_date - 1, 'tank_id', :'tank_id', 'dip_mm', 1500));
reset role;

select t.login('41000000-0000-0000-0000-00000000000b');
select erp_save('bunk.shift', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000002', 'location_id', '31000000-0000-0000-0000-000000000002',
  'doc_date', current_date - 1, 'shift_name', 'full_day', 'attendant_id', '41000000-0000-0000-0000-00000000000b')) as shift \gset
select t.ok((:'shift'::jsonb -> 'readings' -> 0 ->> 'opening')::numeric = 125000, 'new shift opens with the nozzle''s last totaliser');
select t.ok(:'shift'::jsonb ->> 'doc_no' = 'SH/NH16/' || financial_year(current_date - 1) || '/00001', 'shift gets its bunk number');

select (:'shift'::jsonb ->> 'id') as shift_id \gset
select erp_save('bunk.shift', jsonb_build_object('id', :'shift_id',
  'readings', jsonb_build_array(jsonb_build_object('nozzle_id', :'nozzle_id', 'opening', 125000, 'closing', 126000, 'testing', 5)),
  'credit', jsonb_build_array(jsonb_build_object('party_id', '61000000-0000-0000-0000-000000000001', 'vehicle_no', 'AP07AB1234', 'product', 'HSD', 'litres', 100)),
  'upi_pos', 30000, 'cash_counted', 50000)) as shift \gset
select t.ok((:'shift'::jsonb -> 'readings' -> 0 ->> 'sale_litres')::numeric = 995, 'sale = closing − opening − testing = 995 L');
select t.ok((:'shift'::jsonb ->> 'sale_value')::numeric = 90047.50, 'value at today''s rate ₹90.50 = ₹90,047.50');
select t.ok((:'shift'::jsonb ->> 'credit_sales')::numeric = 9050, 'credit slip valued at the pump rate');
select t.ok((:'shift'::jsonb ->> 'short_excess')::numeric = -997.50, 'cash short by ₹997.50 is shown straight away');

select set_config('t.shift_id', :'shift_id', false);
do $$ begin
  perform erp_save('bunk.shift', jsonb_build_object('id', current_setting('t.shift_id'),
    'credit', jsonb_build_array(jsonb_build_object('party_id', '61000000-0000-0000-0000-000000000001', 'vehicle_no', 'AP07AB1234', 'product', 'HSD', 'litres', 300))));
  raise exception 'FAIL: credit limit not enforced';
exception when others then
  perform t.ok(sqlerrm like 'Credit limit crossed%', 'credit beyond the customer''s bunk limit is refused at the pump [' || sqlerrm || ']');
end $$;

select erp_set_status('bunk.shift', :'shift_id', 'submit') ->> 'status' as st \gset
select t.ok(:'st' = 'approved', 'shift submitted; no approval rule, so approved');
reset role;

select t.ok((select current_totaliser from bunk_nozzle where id = :'nozzle_id') = 126000, 'nozzle totaliser moves to the closing reading');
select t.ok((select count(*) from finance_journal where source_entity = 'bunk.shift' and source_id = :'shift_id') = 1, 'shift posted to the books once [' || (select string_agg(doc_no || ':' || status || ':' || total_debit, ',') from finance_journal where source_entity = 'bunk.shift') || ']');
select t.ok((select total_debit = total_credit and total_debit = 90047.50 from finance_journal where source_entity = 'bunk.shift'),
            'shift journal balances at ₹90,047.50');
select t.ok(party_balance('21000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000001') = 9050,
            'credit customer owes the bunk ₹9,050');
select t.ok((select sum(l.debit) from finance_journal_lines l join finance_ledger fl on fl.id = l.ledger_id
             where fl.code = 'CASH_SHORT_EXCESS' and fl.company_id = '21000000-0000-0000-0000-000000000002') = 997.50,
            'cash shortage booked to cash short/excess');

-- Fuel to the group's transit mixer: one entry, three outcomes.
select t.login('41000000-0000-0000-0000-00000000000a');
select erp_save('bunk.internal_issue', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000002',
  'location_id', '31000000-0000-0000-0000-000000000002', 'vehicle_id', '81000000-0000-0000-0000-000000000001',
  'litres', 150, 'odometer', 45210)) as issue \gset
reset role;
select t.ok((:'issue'::jsonb ->> 'amount')::numeric = 13575, 'group vehicle fuel priced at ₹90.50 × 150 L');
select t.ok((select litres from fleet_fuel where vehicle_id = '81000000-0000-0000-0000-000000000001' and source = 'own_bunk') = 150,
            'vehicle''s fuel log in the RMC company got the 150 L');
select t.ok((select is_intercompany from finance_journal where source_entity = 'bunk.internal_issue' and company_id = '21000000-0000-0000-0000-000000000002'),
            'bunk''s sale is tagged inter-company');
select t.ok((select count(*) from finance_journal where source_entity = 'bunk.internal_issue' and company_id = '21000000-0000-0000-0000-000000000001' and is_intercompany) = 1,
            'mirror purchase posted in the RMC company''s books');
select t.ok(party_balance('21000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000012') = -13575,
            'RMC company owes the fuels company ₹13,575');
select t.login('41000000-0000-0000-0000-00000000000a');
select t.ok(not exists (select 1 from trial_balance(null) where ledger_code = 'FUEL_SALES' and company_code = 'LFUEL' and credit > 90047.50),
            'group trial balance eliminates the inter-company fuel sale');
select t.ok(exists (select 1 from trial_balance('21000000-0000-0000-0000-000000000002') where ledger_code = 'FUEL_SALES' and credit = 90047.50 + 13575),
            'the bunk company''s own books still show it');
reset role;

-- Dip today: book stock = yesterday's dip − yesterday's sales.
select t.login('41000000-0000-0000-0000-00000000000b');
select erp_save('bunk.dip', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000002', 'location_id', '31000000-0000-0000-0000-000000000002',
  'tank_id', :'tank_id', 'dip_mm', 1350, 'density', 832)) as dip \gset
select t.ok((:'dip'::jsonb ->> 'book_litres')::numeric = 12250 - 995, 'book stock = 12,250 − 995 = 11,255 L');
select t.ok((:'dip'::jsonb ->> 'variance_alert')::boolean, 'dip of 1350 mm (11,025 L) is beyond tolerance: alert raised');
select t.ok(not (:'dip'::jsonb ? 'density'), 'density sent by the cashier is not saved or shown (field unticked for the role)');
reset role;

-- ===========================================================================
\echo '== RMC: mix design, order with credit check, batch → stock, challan, billing run, invoice → books'
-- ===========================================================================
select t.login('41000000-0000-0000-0000-00000000000a');
-- opening stock by GRN
select erp_save('purchase.grn', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'party_id', '61000000-0000-0000-0000-000000000002',
  'lines', jsonb_build_array(
    jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'received_qty', 50000, 'rate', 7.5),
    jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000002', 'received_qty', 200000, 'rate', 0.9))));
select t.ok((select qty from stock_on_hand('21000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001')) = 50000,
            'GRN puts 50,000 kg cement into plant stock');

select erp_save('rmc.mix_design', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'grade', 'M25', 'mix_code', 'GLP-M25-A', 'effective_from', current_date - 30, 'selling_price_per_m3', 5200,
  'materials', jsonb_build_array(
    jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'qty_per_m3', 340),
    jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000002', 'qty_per_m3', 1150)))) ->> 'id' as mix_id \gset
select erp_set_status('rmc.mix_design', :'mix_id', 'submit');

select erp_save('rmc.order', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'party_id', '61000000-0000-0000-0000-000000000001', 'site_name', 'Sai Villas, Gollapudi', 'grade', 'M25', 'qty_m3', 18,
  'pour_start', now() + interval '1 day', 'pump', 'boom', 'pump_charge', 6000)) as ord \gset
select (:'ord'::jsonb ->> 'id') as order_id \gset
select t.ok((:'ord'::jsonb ->> 'rate_per_m3')::numeric = 5200, 'order picks the approved M25 design''s price');
select t.ok(:'ord'::jsonb ->> 'credit_check' = 'ok', 'credit check: within ₹5,00,000 limit');
select t.ok((:'ord'::jsonb ->> 'order_value')::numeric = 18 * 5200 + 6000, 'order value includes the pump charge');

select erp_save('rmc.batch', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'order_id', :'order_id', 'vehicle_id', '81000000-0000-0000-0000-000000000001', 'qty_m3', 6)) as batch \gset
select t.ok(jsonb_array_length(:'batch'::jsonb -> 'materials') = 2, 'batch without weights takes the mix design quantities');
select t.ok((select qty from stock_on_hand('21000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001')) = 50000 - 340 * 6,
            '6 m³ batch takes 2,040 kg cement out of stock');

select erp_save('rmc.batch', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'order_id', :'order_id', 'vehicle_id', '81000000-0000-0000-0000-000000000001', 'qty_m3', 6,
  'materials', jsonb_build_array(
    jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'actual_qty', 2200),
    jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000002', 'actual_qty', 6900)))) as batch2 \gset
select t.ok((:'batch2'::jsonb ->> 'deviation_alert')::boolean and (:'batch2'::jsonb ->> 'max_deviation_pct')::numeric = 7.84,
            'cement 2,200 kg vs 2,040 target: +7.84%, flagged');

select erp_save('rmc.challan', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'order_id', :'order_id', 'batch_id', :'batch'::jsonb ->> 'id', 'qty_m3', 6, 'receiver_name', 'Ramesh (site)'));
select erp_save('rmc.challan', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'order_id', :'order_id', 'batch_id', :'batch2'::jsonb ->> 'id', 'qty_m3', 6, 'returned_m3', 0.5, 'receiver_name', 'Ramesh (site)'));
select erp_save('rmc.challan', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'order_id', :'order_id', 'qty_m3', 6));
select t.ok((select delivered_m3 from rmc_order where id = :'order_id') = 17.5 and (select delivery_status from rmc_order where id = :'order_id') = 'in_progress',
            'order shows 17.5 m³ delivered (returned concrete deducted) [' || (select delivered_m3 || ' ' || delivery_status from rmc_order where id = :'order_id') || ']');
select t.ok((select party_id from rmc_challan where order_id = :'order_id' limit 1) = '61000000-0000-0000-0000-000000000001', 'challan takes customer from the order');

select * from billing_run('rmc.challan', '21000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000001') \gset bill_
select t.ok(:'bill_lines' = '2', 'billing run bills the 2 signed challans; the unsigned one waits');
select t.ok((select billing_status from rmc_challan where order_id = :'order_id' and receiver_name is null) = 'unbilled', 'unsigned challan stays unbilled');
select t.ok((select taxable_value from finance_sales_invoice where id = :'bill_invoice_id') = 11.5 * 5200
            and (select gst_amount from finance_sales_invoice where id = :'bill_invoice_id') = round(11.5 * 5200 * 0.18, 2),
            'invoice: 11.5 m³ × ₹5,200 + 18% GST');
select t.ok((select doc_no from finance_sales_invoice where id = :'bill_invoice_id') ~ '^GLP/[0-9]{2}-[0-9]{2}/00001$'
            and length((select doc_no from finance_sales_invoice where id = :'bill_invoice_id')) <= 16,
            'invoice number is within the GST 16-character limit');
select erp_set_status('finance.sales_invoice', :'bill_invoice_id', 'submit');
select t.ok(party_balance('21000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001') = round(11.5 * 5200 * 1.18, 2),
            'approved invoice: customer owes ₹70,564');
select t.ok((select sum(debit) = sum(credit) from finance_journal_lines l join finance_journal j on j.id = l.parent_id
             where j.company_id = '21000000-0000-0000-0000-000000000001'), 'RMC company''s books balance');

-- cancel the invoice: books reverse, nothing deleted
select erp_set_status('finance.sales_invoice', :'bill_invoice_id', 'cancel', 'wrong rate agreed');
select t.ok(party_balance('21000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001') = 0, 'cancelled invoice is reversed in the books');
select t.ok((select count(*) from finance_journal where source_entity = 'finance.journal' and is_reversal
             and company_id = '21000000-0000-0000-0000-000000000001') = 1, 'by a reversal journal, not by deleting');
reset role;

-- ===========================================================================
\echo '== Weighbridge'
-- ===========================================================================
select t.login('41000000-0000-0000-0000-00000000000a');
select erp_save('weighbridge.ticket', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'ticket_type', 'sales_dispatch', 'vehicle_no', 'ap 16 tx 4521', 'first_weight_kg', 14650)) as wb \gset
select t.ok(:'wb'::jsonb ->> 'vehicle_no' = 'AP16TX4521' and :'wb'::jsonb ->> 'vehicle_id' = '81000000-0000-0000-0000-000000000001',
            'number plate is cleaned up and matched to our transit mixer');
select erp_save('weighbridge.ticket', jsonb_build_object('id', :'wb'::jsonb ->> 'id', 'second_weight_kg', 29100)) as wb \gset
select t.ok((:'wb'::jsonb ->> 'net_kg')::numeric = 14450 and :'wb'::jsonb ->> 'ticket_status' = 'completed', 'net 14,450 kg, ticket completed');
select t.ok((:'wb'::jsonb ->> 'tare_alert')::boolean, 'tare 14,650 vs usual 14,200: alert (extra 450 kg on the truck?)');
do $$ begin
  perform erp_save('weighbridge.ticket', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
    'ticket_type', 'purchase_inward', 'vehicle_no', 'TS09AB1', 'first_weight_kg', 30000, 'first_mode', 'manual'));
  raise exception 'FAIL: manual weight without reason';
exception when others then perform t.ok(sqlerrm like 'A typed (manual) weight needs a reason%', 'typed weights need a reason');
end $$;
reset role;

-- ===========================================================================
\echo '== Purchase: PO approval, GRN against PO, 3-way match'
-- ===========================================================================
select t.login('41000000-0000-0000-0000-00000000000a');
select erp_save('purchase.po', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'party_id', '61000000-0000-0000-0000-000000000002',
  'lines', jsonb_build_array(jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'qty', 20000, 'rate', 7.4)))) ->> 'id' as po_id \gset
select t.ok((select gst_rate from purchase_po_lines where parent_id = :'po_id') = 18 and (select hsn_sac from purchase_po_lines where parent_id = :'po_id') = '2523',
            'PO line takes HSN and GST rate from the item');
select erp_set_status('purchase.po', :'po_id', 'submit');
select erp_save('purchase.grn', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'party_id', '61000000-0000-0000-0000-000000000002', 'po_id', :'po_id',
  'lines', jsonb_build_array(jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'challan_qty', 20000, 'received_qty', 19800)))) ->> 'id' as grn_id \gset
select t.ok((select receipt_status from purchase_po where id = :'po_id') = 'partly', 'PO shows partly received');
select t.ok((select rate from purchase_grn_lines where parent_id = :'grn_id') = 7.4, 'GRN line takes the PO rate');
select t.ok((select short_qty from purchase_grn_lines where parent_id = :'grn_id') = 200, '200 kg short against the vendor challan');

select erp_save('finance.purchase_invoice', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'party_id', '61000000-0000-0000-0000-000000000002', 'vendor_invoice_no', 'UC/5531', 'vendor_invoice_date', current_date,
  'po_id', :'po_id', 'grn_id', :'grn_id',
  'lines', jsonb_build_array(jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'qty', 20000, 'rate', 7.6, 'gst_rate', 18)))) ->> 'id' as pinv \gset
select set_config('t.pinv', :'pinv', false);
do $$ begin
  perform erp_set_status('finance.purchase_invoice', current_setting('t.pinv')::uuid, 'submit');
  raise exception 'FAIL: mismatched bill auto-approved';
exception when others then perform t.ok(sqlerrm like 'Bill does not match PO/GRN%', 'mismatched bill is stopped from auto-approval [' || sqlerrm || ']');
end $$;
-- with an approval rule for mismatches, it goes to the owner instead
insert into approval_rule (id, tenant_id, doc_type, name, conditions) values
  ('62000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', 'finance.purchase_invoice', 'Mismatched bills',
   '[{"field":"match_status","op":"in","value":["rate_mismatch","qty_mismatch"]}]');
insert into approval_rule_step (tenant_id, rule_id, step_no, approver_type) values
  ('11000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000001', 1, 'tenant_admin');
select t.ok(erp_set_status('finance.purchase_invoice', :'pinv', 'submit') ->> 'status' = 'submitted', 'with a mismatch rule, the bill waits for approval');
select t.ok((select match_status from finance_purchase_invoice where id = :'pinv') = 'rate_mismatch', '3-way match catches ₹7.60 billed vs ₹7.40 on the PO');
select t.ok((select match_notes from finance_purchase_invoice where id = :'pinv') like '%billed 20000, received 19800%', 'and billed 20,000 kg vs 19,800 received');
reset role;

-- ===========================================================================
\echo '== Construction project: BOQ, DPR, RA bill'
-- ===========================================================================
select t.login('41000000-0000-0000-0000-00000000000a');
select erp_save('infra.project', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000003',
  'name', 'Guntur Road 4-laning pkg 2', 'client_id', '61000000-0000-0000-0000-000000000001', 'contract_value', 10000000,
  'start_date', current_date - 60, 'end_date', current_date + 300, 'mobilisation_advance', 500000, 'mobilisation_recovery_pct', 10)) ->> 'id' as proj \gset
select erp_save('infra.boq_item', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000003',
  'project_id', :'proj', 'item_no', '4.1', 'description', 'DBM 50mm', 'unit', 'm2', 'contract_qty', 20000, 'rate', 300)) ->> 'id' as boq \gset
reset role;

select t.login('41000000-0000-0000-0000-00000000000c');
select erp_save('infra.dpr', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000003',
  'project_id', :'proj', 'weather', 'clear',
  'work', jsonb_build_array(jsonb_build_object('boq_item_id', :'boq', 'qty', 2500, 'location_detail', 'Ch 12+200 to 12+700 LHS')),
  'labour', jsonb_build_array(jsonb_build_object('trade', 'helper', 'count', 22), jsonb_build_object('trade', 'operator', 'count', 4)))) as dpr \gset
select t.ok((:'dpr'::jsonb ->> 'total_manpower')::int = 26, 'DPR adds up manpower');
select t.ok(not (:'dpr'::jsonb -> '_can' ->> 'approve')::boolean, 'site engineer cannot approve their own DPR');
select erp_set_status('infra.dpr', (:'dpr'::jsonb ->> 'id')::uuid, 'submit');
reset role;
select t.ok((select done_qty from infra_boq_item where id = :'boq') = 2500, 'approved DPR moves the BOQ item''s done quantity');
select t.ok((select physical_progress_pct from infra_project where id = :'proj') = 12.5, 'project progress 12.5%');

select t.login('41000000-0000-0000-0000-00000000000a');
select erp_save('infra.ra_bill', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000003',
  'project_id', :'proj', 'lines', jsonb_build_array(jsonb_build_object('boq_item_id', :'boq', 'this_qty', 2500)))) as ra \gset
select t.ok((:'ra'::jsonb ->> 'this_bill_value')::numeric = 750000 and (:'ra'::jsonb ->> 'retention')::numeric = 37500
            and (:'ra'::jsonb ->> 'mobilisation_recovery')::numeric = 75000,
            'RA bill 1: ₹7,50,000, 5% retention, 10% mobilisation recovery');
select t.ok((:'ra'::jsonb ->> 'net_payable')::numeric = 750000 + 135000 - 37500 - 75000 - 15000 - 15000 - 7500,
            'net payable after retention, recovery, TDS, GST-TDS and cess');
select erp_set_status('infra.ra_bill', (:'ra'::jsonb ->> 'id')::uuid, 'submit');
select t.ok((select billed_qty from infra_boq_item where id = :'boq') = 2500, 'BOQ billed quantity updated');
select t.ok((select total_debit = total_credit from finance_journal where source_entity = 'infra.ra_bill'), 'RA bill journal balances');
select t.ok((project_health(:'proj') ->> 'billed')::numeric = 750000, 'project health shows billed value');
reset role;

-- ===========================================================================
\echo '== Bricks: recipe, production → curing lot, dispatch rules'
-- ===========================================================================
insert into location (id, tenant_id, company_id, type, name, short_code) values
  ('31000000-0000-0000-0000-000000000004', '11000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', 'plant', 'Brick unit', 'BRK');
select t.login('41000000-0000-0000-0000-00000000000a');
select erp_save('bricks.recipe', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000004',
  'product_id', '71000000-0000-0000-0000-000000000004', 'curing_days', 14,
  'materials', jsonb_build_array(jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000003', 'qty', 1800),
                                 jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'qty', 250))));
select erp_save('bricks.production', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000004',
  'product_id', '71000000-0000-0000-0000-000000000004', 'good_units', 9600, 'rejected_units', 400, 'curing_block', 'B2')) as prod \gset
reset role;
select set_config('t.lot_id', (select id::text from bricks_curing_lot order by created_at desc limit 1), false);
select t.ok((select qty from bricks_production_materials where parent_id = (:'prod'::jsonb ->> 'id')::uuid
             and item_id = '71000000-0000-0000-0000-000000000003') = 18000, '10,000 moulded → 18,000 kg fly ash from the recipe');
select t.ok((select qty from bricks_curing_lot where production_id = (:'prod'::jsonb ->> 'id')::uuid) = 9600
            and (select ready_on from bricks_curing_lot where production_id = (:'prod'::jsonb ->> 'id')::uuid) = current_date + 14,
            'good bricks go into a curing lot ready in 14 days');
select t.login('41000000-0000-0000-0000-00000000000a');
do $$ begin
  perform erp_save('bricks.dispatch', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000004',
    'party_id', '61000000-0000-0000-0000-000000000001', 'product_id', '71000000-0000-0000-0000-000000000004', 'qty', 3000,
    'lot_id', current_setting('t.lot_id')));
  raise exception 'FAIL: dispatched uncured bricks';
exception when others then perform t.ok(sqlerrm like 'This lot is still curing%', 'cannot dispatch bricks that are still curing');
end $$;
reset role;

-- ===========================================================================
\echo '== HR & payroll'
-- ===========================================================================
select t.login('41000000-0000-0000-0000-00000000000a');
select erp_save('hr.employee', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'emp_code', 'E001', 'full_name', 'Suresh K', 'mobile', '9000011111', 'employment_type', 'operator', 'date_of_joining', '2025-01-01',
  'basic', 12000, 'da', 2000, 'hra', 3000, 'other_allowance', 1000, 'pf_applicable', true, 'esi_applicable', true)) ->> 'id' as emp \gset
reset role;  -- biometric import runs as a system job
insert into hr_attendance (tenant_id, company_id, location_id, doc_date, employee_id, mark, ot_hours)
select '11000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000001', d::date, :'emp',
       case when extract(dow from d) = 0 then 'weekly_off' when extract(day from d) in (10, 11) then 'absent' else 'present' end,
       case when extract(day from d) = 5 then 4 else 0 end
from generate_series(date '2026-09-01', date '2026-09-30', interval '1 day') d;
select t.login('41000000-0000-0000-0000-00000000000a');
select erp_save('hr.advance', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'employee_id', :'emp', 'amount', 3000, 'recover_in_months', 3)) ->> 'id' as adv \gset
select erp_set_status('hr.advance', :'adv', 'submit');
select erp_save('hr.payroll_run', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'month', '2026-09')) ->> 'id' as run \gset
select hr_generate_payroll(:'run');
select t.ok((select paid_days from hr_payroll_run_lines where parent_id = :'run') = 28, '28 paid days (2 absent) in September');
select t.ok((select earned_basic_da from hr_payroll_run_lines where parent_id = :'run') = round(14000 * 28 / 30.0, 2), 'basic + DA pro-rated');
select t.ok((select pf_employee from hr_payroll_run_lines where parent_id = :'run') = round(round(14000 * 28 / 30.0, 2) * 0.12), 'PF 12% of basic + DA');
select t.ok((select esi_employee from hr_payroll_run_lines where parent_id = :'run') > 0, 'ESI deducted (gross under ₹21,000)');
select t.ok((select advance_recovery from hr_payroll_run_lines where parent_id = :'run') = 1000, 'advance recovered ₹1,000 (₹3,000 over 3 months)');
select t.ok((select ot_amount from hr_payroll_run_lines where parent_id = :'run') = round(18000 / 30.0 / 8 * 2 * 4, 2), '4 OT hours at double rate');
select erp_set_status('hr.payroll_run', :'run', 'submit');
select t.ok((select recovered from hr_advance where id = :'adv') = 1000, 'approved payroll marks ₹1,000 of the advance recovered');
select t.ok((select total_debit = total_credit from finance_journal where source_entity = 'hr.payroll_run'), 'payroll journal balances');
reset role;

-- ===========================================================================
\echo '== Locked records, hidden-by-switch fields, audit of module records'
-- ===========================================================================
select set_config('t.dpr_id', (select id::text from infra_dpr limit 1), false);
select t.login('41000000-0000-0000-0000-00000000000c');
do $$ begin
  perform erp_save('infra.dpr', jsonb_build_object('id', current_setting('t.dpr_id'), 'weather', 'rain'));
  raise exception 'FAIL: edited an approved DPR';
exception when others then perform t.ok(sqlerrm like '%can no longer be changed%' or sqlerrm like 'You are not allowed to change%', 'approved DPR is locked for the engineer [' || sqlerrm || ']');
end $$;
reset role;

-- Admin hides "water dip" at this bunk: gone from everyone's dip form there.
insert into feature_flag (tenant_id, feature_key, level, level_id, config) values
  ('11000000-0000-0000-0000-000000000001', 'bunk.tanks.daily_dip', 'location', '31000000-0000-0000-0000-000000000002', '{"hidden_fields": ["water_mm"]}');
select t.login('41000000-0000-0000-0000-00000000000a');
select t.ok(not exists (select 1 from jsonb_array_elements(erp_catalog('21000000-0000-0000-0000-000000000002', '31000000-0000-0000-0000-000000000002')) e,
                        jsonb_array_elements(e -> 'fields') fl where e ->> 'key' = 'bunk.dip' and fl ->> 'name' = 'water_mm'),
            'a field hidden by a location switch disappears even for the owner');
select t.ok(exists (select 1 from record_history where table_name = 'public.bunk_shift' and actor_name = 'Bunk Cashier' and action = 'INSERT'),
            'history shows the cashier opened the shift');
select t.ok(exists (select 1 from record_history where table_name = 'public.bunk_shift' and action = 'UPDATE' and 'status' = any(changed_fields)),
            'and when its status changed');
select t.ok((select count(*) from audit.verify_chain('11000000-0000-0000-0000-000000000001')) = 0, 'audit chain for the group is intact');
reset role;

-- ===========================================================================
\echo '== Owner dashboard and leakage board'
-- ===========================================================================
select t.login('41000000-0000-0000-0000-00000000000a');
select t.ok((select count(*) from owner_dashboard()) = 2, 'owner sees both companies on the dashboard');
select t.ok((select fuel_litres_sold from owner_dashboard() where company_code = 'LFUEL') = 995, 'bunk litres sold this month');
select t.ok((select rmc_m3 from owner_dashboard() where company_code = 'LRMC') = 17.5, 'RMC m³ delivered this month');
select t.ok(exists (select 1 from leakage_board('21000000-0000-0000-0000-000000000002') where kind = 'tank_variance'), 'leakage board: tank variance');
select t.ok(exists (select 1 from leakage_board('21000000-0000-0000-0000-000000000002') where kind = 'cash_short'), 'leakage board: cash short');
select t.ok(exists (select 1 from leakage_board('21000000-0000-0000-0000-000000000001') where kind = 'tare_drift'), 'leakage board: tare drift');
select t.ok(exists (select 1 from leakage_board('21000000-0000-0000-0000-000000000001') where kind = 'batch_deviation'), 'leakage board: batch deviation');
select t.ok(not exists (select 1 from leakage_board('21000000-0000-0000-0000-000000000001') where kind = 'unbilled_work'), 'leakage board: fully billed project work is not flagged');
select t.ok((select array_agg(e ->> 'key' order by e ->> 'key') from jsonb_array_elements(
              preview_screens('41000000-0000-0000-0000-00000000000b', '21000000-0000-0000-0000-000000000002', '31000000-0000-0000-0000-000000000002')) e)
            = '{bunk.dip,bunk.shift}', 'owner previews the cashier: exactly the shift and dip screens');
select t.ok(my_context() -> 'user' ->> 'name' = 'Lakshmi Owner', 'after the preview the owner is still the owner');
select t.ok(jsonb_array_length(my_context() -> 'companies') = 2, 'my_context lists the owner''s companies');
select t.ok((select count(*) from erp_history('rmc.order', :'order_id')) >= 1, 'History tab for an RMC order');
reset role;
select t.login('41000000-0000-0000-0000-00000000000b');
select t.ok((select count(*) from owner_dashboard()) = 0, 'cashier gets no owner dashboard');
select t.ok((select count(*) from leakage_board('21000000-0000-0000-0000-000000000002')) = 0, 'or leakage board');
select t.ok(jsonb_array_length(my_context() -> 'companies' -> 0 -> 'locations') = 1, 'cashier''s context: just the bunk');
reset role;

-- ===========================================================================
\echo '== AI: scopes follow switches and roles; AI reads are audited as AI'
-- ===========================================================================
select t.login('41000000-0000-0000-0000-00000000000b');
select t.ok('bunk.shift.create' = any(ai_scopes('21000000-0000-0000-0000-000000000002', '31000000-0000-0000-0000-000000000002'))
            and not ('rmc.orders.view' = any(ai_scopes('21000000-0000-0000-0000-000000000002', '31000000-0000-0000-0000-000000000002')))
            and 'agent.bunk_assistant' = any(ai_scopes('21000000-0000-0000-0000-000000000002', '31000000-0000-0000-0000-000000000002'))
            and not ('agent.owner_assistant' = any(ai_scopes('21000000-0000-0000-0000-000000000002', '31000000-0000-0000-0000-000000000002'))),
            'cashier''s AI token: bunk shift tools and the bunk assistant, nothing from RMC, no owner assistant');
do $$ begin
  perform ai_call('erp_list', '{}');
  raise exception 'FAIL: user called the AI door directly';
exception when insufficient_privilege then perform t.ok(true, 'only the AI service can use ai_call');
end $$;
reset role;
insert into feature_flag (tenant_id, feature_key, level, level_id, state) values
  ('11000000-0000-0000-0000-000000000001', 'ai', 'company', '21000000-0000-0000-0000-000000000002', 'off');
select t.login('41000000-0000-0000-0000-00000000000b');
select t.ok(not exists (select 1 from unnest(ai_scopes('21000000-0000-0000-0000-000000000002')) s where s like 'agent.%' or s like 'extract.%'),
            'AI switched off for the bunk company: no agents, no document reading');
reset role;
delete from feature_flag where feature_key = 'ai' and level = 'company';
select t.login('41000000-0000-0000-0000-00000000000a');
select set_config('request.jwt.claims', json_build_object('sub', '41000000-0000-0000-0000-00000000000a', 'role', 'authenticated',
                                                          'via', 'zentrix', 'correlation_id', 'zadk-test-1')::text, false);
select t.ok(jsonb_array_length(ai_call('leakage_board', '{"company": "21000000-0000-0000-0000-000000000002"}') ) > 0, 'AI agent reads the leakage board as the owner');
reset role;
select t.ok((select actor_type || '|' || on_behalf_of::text || '|' || correlation_id from audit.log where action = 'ai.tool_call' order by id desc limit 1)
            = 'ai_agent|41000000-0000-0000-0000-00000000000a|zadk-test-1', 'AI read is in the audit log as AI, for the owner, with the Zentrix id');

-- ===========================================================================
\echo '== Reports, GST files, period lock, owner summary'
-- ===========================================================================
select t.login('41000000-0000-0000-0000-00000000000a');
select t.ok((select amount from profit_and_loss('21000000-0000-0000-0000-000000000002', current_date - 30, current_date) where section = 'Net profit')
            = (select coalesce(sum(credit - debit), 0) from trial_balance('21000000-0000-0000-0000-000000000002') where ledger_group in ('sales','direct_income','indirect_income','purchases','direct_expenses','indirect_expenses')),
            'P&L net profit equals income minus expenses in the trial balance');
select t.ok((select round(sum(case when side = 'Assets' then amount else -amount end), 2) from balance_sheet('21000000-0000-0000-0000-000000000002')) = 0,
            'balance sheet balances (assets = liabilities + profit)');
select t.ok((select total from ageing('21000000-0000-0000-0000-000000000002') where party_id = '61000000-0000-0000-0000-000000000001') = 9050
            and (select d0_30 from ageing('21000000-0000-0000-0000-000000000002') where party_id = '61000000-0000-0000-0000-000000000001') = 9050,
            'ageing: Sai Builders owes the bunk ₹9,050, all under 30 days');
select t.ok((select balance from party_statement('21000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000001') order by doc_date desc nulls last, doc_no desc nulls last limit 1) = 9050,
            'party statement ends at the same balance');
select t.ok((select sales from bunk_dsr('21000000-0000-0000-0000-000000000002', '31000000-0000-0000-0000-000000000002', current_date - 1)) = 995,
            'DSR: yesterday''s HSD sales 995 L');
select t.ok((select book_closing from bunk_dsr('21000000-0000-0000-0000-000000000002', '31000000-0000-0000-0000-000000000002', current_date - 1)) = 11255,
            'DSR: book closing matches the next morning''s book stock');
select erp_save('finance.sales_invoice', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'party_id', '61000000-0000-0000-0000-000000000001', 'place_of_supply', '37', 'vehicle_no', 'AP16TX4521',
  'lines', jsonb_build_array(jsonb_build_object('item_id', '71000000-0000-0000-0000-000000000001', 'qty', 100, 'uom', 'BAG', 'rate', 380, 'gst_rate', 18)))) ->> 'id' as einv \gset
select t.ok((einvoice_json(:'einv') #>> '{ValDtls,TotInvVal}')::numeric = 44840 and (einvoice_json(:'einv') #>> '{ValDtls,CgstVal}')::numeric = 3420
            and einvoice_json(:'einv') #>> '{ItemList,0,Unit}' = 'BAG', 'e-invoice JSON: totals, CGST/SGST split, unit code');
select t.ok(einvoice_json(:'einv') -> '_missing' ? 'customer GSTIN (B2B e-invoice needs it)', 'e-invoice lists what is missing before upload');
select t.ok((ewaybill_json(:'einv') #>> '{billLists,0,vehicleNo}') = 'AP16TX4521', 'e-way bill JSON carries the vehicle');
select erp_set_status('finance.sales_invoice', :'einv'::uuid, 'submit');
select t.ok(jsonb_array_length(gstr1_json('22000000-0000-0000-0000-000000000001', to_char(current_date, 'YYYY-MM')) -> 'b2cs') >= 1,
            'GSTR-1: invoice to a customer without GSTIN goes to B2C small');
insert into period_lock (company_id, tenant_id, locked_upto) values ('21000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000001', current_date - 1);
reset role;
select set_config('t.tank', (select id::text from bunk_tank where tenant_id = '11000000-0000-0000-0000-000000000001' limit 1), false);
select t.login('41000000-0000-0000-0000-00000000000b');
do $$ begin
  perform erp_save('bunk.dip', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000002', 'location_id', '31000000-0000-0000-0000-000000000002',
    'doc_date', current_date - 3, 'tank_id', current_setting('t.tank'), 'dip_mm', 1000));
  raise exception 'FAIL: entry in a locked period';
exception when others then perform t.ok(sqlerrm like 'Entries up to % are locked%', 'cashier cannot enter a dip in a locked (filed) period');
end $$;
reset role;
select t.login('41000000-0000-0000-0000-00000000000a');
select t.ok(owner_summary_text(current_date - 1) like '*Lakshmi Group%Sales:%', 'owner''s WhatsApp summary is ready to send');
reset role;

-- ===========================================================================
\echo '== Bank matching, Tally export, documents, devices'
-- ===========================================================================
select t.login('41000000-0000-0000-0000-00000000000a');
select erp_save('finance.ledger', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'name', 'SBI Current A/c', 'code', 'BANK_SBI',
  'ledger_group', 'bank', 'nature', 'asset', 'is_bank', true)) ->> 'id' as bank \gset
select erp_save('finance.receipt', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000001', 'location_id', '31000000-0000-0000-0000-000000000001',
  'party_id', '61000000-0000-0000-0000-000000000001', 'amount', 50000, 'mode', 'neft_rtgs', 'reference_no', 'UTR555123', 'bank_ledger_id', :'bank'));
select t.ok((bank_import('21000000-0000-0000-0000-000000000001', :'bank', jsonb_build_array(
  jsonb_build_object('date', current_date, 'narration', 'NEFT-UTR555123-SAI BUILDERS', 'credit', 50000),
  jsonb_build_object('date', current_date, 'narration', 'BANK CHARGES', 'debit', 118))) ->> 'matched')::int = 1,
  'bank statement imported; the NEFT credit matches the receipt by amount and UTR');
select t.ok((bank_import('21000000-0000-0000-0000-000000000001', :'bank', jsonb_build_array(
  jsonb_build_object('date', current_date, 'narration', 'BANK CHARGES', 'debit', 118))) ->> 'duplicates')::int = 1, 'importing the same line twice is skipped');
select t.ok(tally_export('21000000-0000-0000-0000-000000000001', current_date - 60, current_date) like '%<VOUCHER VCHTYPE=%<LEDGERNAME>Sai Builders</LEDGERNAME>%',
            'Tally XML has vouchers with the party as ledger');
select erp_save('core.document', jsonb_build_object('company_id', '21000000-0000-0000-0000-000000000002', 'category', 'peso_licence',
  'title', 'PESO storage licence NH16 bunk', 'doc_number', 'P/HQ/AP/15/1234', 'expires_on', current_date + 10));
select t.ok(exists (select 1 from leakage_board('21000000-0000-0000-0000-000000000002') where kind = 'licence_expiry'), 'leakage board warns about the PESO licence expiring');
select device_register('21000000-0000-0000-0000-000000000001', '31000000-0000-0000-0000-000000000001', 'weighbridge', 'Plant weighbridge') as dev \gset
select device_register('21000000-0000-0000-0000-000000000001', null, 'gps', 'GPS feed') as gps \gset
reset role;
select set_config('role', 'anon', false);
select t.ok(device_ingest(:'dev'::jsonb ->> 'serial', :'dev'::jsonb ->> 'key', '{"weight_kg": 14300, "stable_seconds": 4, "vehicle_no": "AP16 TX 4521"}') ->> 'weighment' = 'first',
            'scale sends a stable weight: first weighment ticket created');
select t.ok(device_ingest(:'dev'::jsonb ->> 'serial', :'dev'::jsonb ->> 'key', '{"weight_kg": 21300, "stable_seconds": 5, "vehicle_no": "AP16TX4521"}') ->> 'weighment' = 'second',
            'same truck again: second weighment on the same ticket');
do $$ begin
  perform device_ingest('weighbridge-x', 'wrong', '{}');
  raise exception 'FAIL: unknown device accepted';
exception when insufficient_privilege then perform t.ok(true, 'a device with a wrong key is refused');
end $$;
select device_ingest(:'gps'::jsonb ->> 'serial', :'gps'::jsonb ->> 'key', '{"vehicle_no": "AP16TX4521", "lat": 16.5, "lng": 80.6, "speed_kmph": 0, "fuel_l": 180}');
select t.ok(device_ingest(:'gps'::jsonb ->> 'serial', :'gps'::jsonb ->> 'key', '{"vehicle_no": "AP16TX4521", "lat": 16.5, "lng": 80.6, "speed_kmph": 0, "fuel_l": 150}') ->> 'alert' = 'fuel_drop',
            'GPS: 30 L gone while parked raises a fuel-drop alert');
reset role;
select t.ok((select net_kg from weighbridge_ticket where vehicle_no = 'AP16TX4521' and second_mode = 'scale' order by created_at desc limit 1) = 7000
            and (select actor_type from audit.log where table_name = 'public.weighbridge_ticket' order by id desc limit 1) = 'hardware',
            'ticket net 7,000 kg, recorded in the audit log as the scale');

\echo '== all module tests passed'
