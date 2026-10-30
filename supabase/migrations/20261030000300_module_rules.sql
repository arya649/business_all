-- Business rules per module: the things that make each module "know its domain".
-- Everything here runs in the database, so the web app, the mobile app, AI agents and imports all get it.

-- Shift posting: cash, UPI, cards, expenses and per-customer credit on one side; fuel sales on the other.
-- Fuel given to group vehicles is posted by its own document, so it is taken out of the shift's sales.
alter table public.bunk_shift add column net_fuel_sales numeric(14, 2)
  generated always as (coalesce(sale_value, 0) - coalesce(internal_issues, 0)) stored;
update public.erp_entity set posting = '{
  "voucher": "receipt", "lines": [
    {"side": "Dr", "ledger": "CASH", "amount": "cash_counted"},
    {"side": "Dr", "ledger": "BANK_POS", "amount": "upi_pos"},
    {"side": "Dr", "ledger": "FLEET_CARDS", "amount": "fleet_card"},
    {"side": "Dr", "ledger": "EXPENSES", "amount": "expenses_paid"},
    {"side": "Dr", "ledger": "@party", "amount": "amount", "child": "credit"},
    {"side": "Cr", "ledger": "FUEL_SALES", "amount": "net_fuel_sales"},
    {"side": "Cr", "ledger": "CASH_SHORT_EXCESS", "amount": "short_excess"}
  ]}'::jsonb
where key = 'bunk.shift';
-- the Dr @party for credit customers uses "sales" logic (debtors)
update public.erp_entity set posting = jsonb_set(posting, '{voucher}', '"sales"') where key = 'bunk.shift';
insert into public.erp_field (entity_key, name, label, type, computed, sensitive, sort)
values ('bunk.shift', 'net_fuel_sales', 'Fuel sales (excl. group vehicles)', 'money', true, null, 99);

update public.erp_entity set posting = '{
  "voucher": "sales", "party": "party_id", "lines": [
    {"side": "Dr", "ledger": "@party", "amount": "amount"},
    {"side": "Cr", "ledger": "FUEL_SALES", "amount": "amount"}
  ]}'::jsonb
where key = 'bunk.internal_issue';
alter table public.bunk_internal_issue add column party_id uuid references public.party;
alter table public.bunk_internal_issue add column shift_id uuid references public.bunk_shift;
alter table public.bunk_internal_issue add column fleet_fuel_id uuid references public.fleet_fuel;

-- Lube sales: cash by default; credit / UPI / card through posting variants below.
update public.erp_entity set posting = '{
  "voucher": "receipt", "lines": [
    {"side": "Dr", "ledger": "CASH", "amount": "total"},
    {"side": "Cr", "ledger": "SALES", "amount": "total"}
  ]}'::jsonb
where key = 'bunk.lube_sale';
create function public.bunk_lube_party() returns trigger language plpgsql as $$
begin
  if new.payment_mode = 'credit' and new.party_id is null then
    raise exception 'Choose the credit customer.';
  end if;
  return new;
end $$;
create trigger bunk_lube_party before insert or update on public.bunk_lube_sale for each row execute function public.bunk_lube_party();
-- credit lube sales: Dr party instead of cash
create table public.posting_variant (
  entity_key text not null,
  field      text not null,
  value      text not null,
  rule       jsonb not null,
  primary key (entity_key, field, value)
);
insert into public.posting_variant values ('bunk.lube_sale', 'payment_mode', 'credit', '{
  "voucher": "sales", "party": "party_id", "lines": [
    {"side": "Dr", "ledger": "@party", "amount": "total"},
    {"side": "Cr", "ledger": "SALES", "amount": "total"}
  ]}'::jsonb),
  ('bunk.lube_sale', 'payment_mode', 'upi', '{
  "voucher": "receipt", "lines": [
    {"side": "Dr", "ledger": "BANK_POS", "amount": "total"},
    {"side": "Cr", "ledger": "SALES", "amount": "total"}
  ]}'::jsonb),
  ('bunk.lube_sale', 'payment_mode', 'card', '{
  "voucher": "receipt", "lines": [
    {"side": "Dr", "ledger": "BANK_POS", "amount": "total"},
    {"side": "Cr", "ledger": "SALES", "amount": "total"}
  ]}'::jsonb),
  ('finance.receipt', 'mode', 'adjustment', '{
  "voucher": "journal", "party": "party_id", "lines": [
    {"side": "Dr", "ledger": "INTERCO_SUSPENSE", "amount": "amount"},
    {"side": "Cr", "ledger": "@party", "amount": "amount"}
  ]}'::jsonb);

-- fin_post_document picks a variant when the document's field matches.
create or replace function public.fin_rule_for(p_entity text, p_row jsonb, p_default jsonb) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select pr.rule from posting_rule pr
     where pr.entity_key = p_entity and pr.is_active and pr.tenant_id = (p_row ->> 'tenant_id')::uuid
       and (pr.company_id is null or pr.company_id = (p_row ->> 'company_id')::uuid)
     order by pr.company_id nulls last limit 1),
    (select v.rule from posting_variant v where v.entity_key = p_entity and p_row ->> v.field = v.value limit 1),
    p_default)
$$;

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

-- Litres in a tank for a dip reading, interpolated from its calibration chart [[mm, litres], ...].
create function public.tank_litres(p_tank uuid, p_mm numeric) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare
  v_chart jsonb;
  lo jsonb;
  hi jsonb;
begin
  if p_mm is null then return null; end if;
  select calibration_chart into v_chart from bunk_tank where id = p_tank;
  if v_chart is null or jsonb_array_length(v_chart) < 2 then return null; end if;
  select x into lo from jsonb_array_elements(v_chart) x where (x ->> 0)::numeric <= p_mm order by (x ->> 0)::numeric desc limit 1;
  select x into hi from jsonb_array_elements(v_chart) x where (x ->> 0)::numeric >= p_mm order by (x ->> 0)::numeric limit 1;
  if lo is null then return (hi ->> 1)::numeric * p_mm / nullif((hi ->> 0)::numeric, 0); end if;
  if hi is null or (hi ->> 0)::numeric = (lo ->> 0)::numeric then return (lo ->> 1)::numeric; end if;
  return round((lo ->> 1)::numeric + ((hi ->> 1)::numeric - (lo ->> 1)::numeric)
               * (p_mm - (lo ->> 0)::numeric) / ((hi ->> 0)::numeric - (lo ->> 0)::numeric), 1);
end;
$$;

create function public.bunk_rate(p_location uuid, p_product text, p_at timestamptz default now()) returns numeric
language sql stable security definer set search_path = public as $$
  select rsp from bunk_price where location_id = p_location and product = p_product and effective_from <= p_at
  order by effective_from desc limit 1
$$;

-- ---------------------------------------------------------------------------
-- Petrol bunk
-- ---------------------------------------------------------------------------

-- Readings: product, rate and opening fill themselves in.
create function public.bunk_reading_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_loc uuid;
  v_at  timestamptz;
begin
  select location_id, coalesce(opened_at, now()) into v_loc, v_at from bunk_shift where id = new.parent_id;
  if new.product is null then
    select t.product into new.product from bunk_nozzle n join bunk_tank t on t.id = n.tank_id where n.id = new.nozzle_id;
  end if;
  if new.rate is null then
    new.rate := public.bunk_rate(v_loc, new.product, v_at);
  end if;
  if new.closing is not null and new.closing < new.opening then
    raise exception 'Closing reading % is lower than opening %. Check again?', new.closing, new.opening;
  end if;
  return new;
end;
$$;
create trigger bunk_reading_defaults before insert or update on public.bunk_shift_readings
  for each row execute function public.bunk_reading_defaults();

create function public.bunk_credit_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_loc uuid;
  v_co  uuid;
  v_lim numeric;
  v_bal numeric;
begin
  select location_id, company_id into v_loc, v_co from bunk_shift where id = new.parent_id;
  if new.rate is null and new.product <> 'LUBE' then
    new.rate := public.bunk_rate(v_loc, new.product);
  end if;
  select credit_limit into v_lim from party_company where party_id = new.party_id and company_id = v_co;
  if (select status from party where id = new.party_id) = 'blocked' then
    raise exception 'This customer is blocked for credit: %', (select blocked_reason from party where id = new.party_id);
  end if;
  v_bal := public.party_balance(v_co, new.party_id);
  if v_lim is not null and v_lim > 0 and v_bal + new.litres * coalesce(new.rate, 0) > v_lim then
    raise exception 'Credit limit crossed for this customer: outstanding ₹% + this ₹% > limit ₹%.',
      round(v_bal), round(new.litres * coalesce(new.rate, 0)), round(v_lim);
  end if;
  return new;
end;
$$;
create trigger bunk_credit_defaults before insert or update on public.bunk_shift_credit
  for each row execute function public.bunk_credit_defaults();

-- New shift: opening readings for every active nozzle from the last closing.
create function public.bunk_shift_open() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from bunk_shift_readings where parent_id = new.id) then
    insert into bunk_shift_readings (tenant_id, parent_id, line_no, nozzle_id, opening)
    select new.tenant_id, new.id, row_number() over (order by n.name), n.id, coalesce(n.current_totaliser, 0)
    from bunk_nozzle n where n.location_id = new.location_id and n.is_active;
  end if;
  return null;
end;
$$;
create trigger bunk_shift_open after insert on public.bunk_shift for each row execute function public.bunk_shift_open();

-- Approved shift: totalisers move on; group-vehicle issues are summed in.
create function public.bunk_shift_close() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    update bunk_nozzle n set current_totaliser = r.closing
    from bunk_shift_readings r where r.parent_id = new.id and r.nozzle_id = n.id and r.closing is not null;
  end if;
  return null;
end;
$$;
create trigger bunk_shift_close after update of status on public.bunk_shift for each row execute function public.bunk_shift_close();

create function public.bunk_shift_internal() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status in ('draft', 'sent_back') or tg_op = 'INSERT' then
    new.internal_issues := coalesce((select sum(amount) from bunk_internal_issue where shift_id = new.id), 0);
  end if;
  return new;
end;
$$;
create trigger bunk_shift_internal before insert or update on public.bunk_shift for each row execute function public.bunk_shift_internal();

-- Dip: litres from the chart, book stock from the last dip + receipts − sales, variance vs tolerance.
create function public.bunk_dip_compute() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  p    bunk_dip;
  v_tol numeric;
begin
  new.dip_litres := coalesce(public.tank_litres(new.tank_id, new.dip_mm) - coalesce(public.tank_litres(new.tank_id, new.water_mm), 0),
                             new.dip_litres);
  select * into p from bunk_dip where tank_id = new.tank_id and doc_date < new.doc_date and id <> new.id
  order by doc_date desc, created_at desc limit 1;
  if found then
    new.book_litres := p.dip_litres
      + coalesce((select sum(received_litres) from bunk_tanker_receipt r where r.tank_id = new.tank_id
                  and r.doc_date >= p.doc_date and r.doc_date < new.doc_date and r.status <> 'cancelled'), 0)
      - coalesce((select sum(rd.sale_litres) from bunk_shift_readings rd join bunk_shift s on s.id = rd.parent_id
                  join bunk_nozzle n on n.id = rd.nozzle_id
                  where n.tank_id = new.tank_id and s.doc_date >= p.doc_date and s.doc_date < new.doc_date
                    and s.status <> 'cancelled'), 0);
    select variance_tolerance_pct into v_tol from bunk_tank where id = new.tank_id;
    new.variance_alert := abs(coalesce(new.dip_litres, 0) - new.book_litres)
                          > greatest(new.book_litres, 1) * coalesce(v_tol, 0.5) / 100;
  end if;
  return new;
end;
$$;
create trigger bunk_dip_compute before insert or update on public.bunk_dip for each row execute function public.bunk_dip_compute();

create function public.bunk_tanker_compute() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.received_litres is null and new.dip_before_mm is not null and new.dip_after_mm is not null then
    new.received_litres := public.tank_litres(new.tank_id, new.dip_after_mm) - public.tank_litres(new.tank_id, new.dip_before_mm);
  end if;
  if new.product is null then
    select product into new.product from bunk_tank where id = new.tank_id;
  end if;
  return new;
end;
$$;
create trigger bunk_tanker_compute before insert or update on public.bunk_tanker_receipt for each row execute function public.bunk_tanker_compute();

-- Fuel to a group vehicle: price, billing party, link to shift, and the vehicle's fuel log entry.
create function public.bunk_internal_before() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid;
begin
  if new.transfer_rate is null then
    new.transfer_rate := public.bunk_rate(new.location_id, new.product);
  end if;
  select owning_company_id into v_owner from vehicle where id = new.vehicle_id;
  new.to_company_id := coalesce(new.to_company_id, v_owner, new.company_id);
  if new.party_id is null then
    select id into new.party_id from party where group_company_id = new.to_company_id and tenant_id = new.tenant_id limit 1;
    if new.party_id is null then
      raise exception 'Add % as a party (group company) so fuel to its vehicles can be billed.',
        (select legal_name from company where id = new.to_company_id);
    end if;
  end if;
  if new.shift_id is null then
    select id into new.shift_id from bunk_shift where location_id = new.location_id and doc_date = new.doc_date
      and status in ('draft', 'sent_back') order by created_at desc limit 1;
  end if;
  return new;
end;
$$;
create trigger bunk_internal_before before insert or update on public.bunk_internal_issue
  for each row execute function public.bunk_internal_before();

create function public.bunk_internal_after() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_fuel uuid;
  v_loc  uuid;
begin
  -- the vehicle's fuel log lives in the vehicle owner's company, at its current location if known
  select coalesce(v.current_location_id, (select id from location where company_id = new.to_company_id order by created_at limit 1))
    into v_loc from vehicle v where v.id = new.vehicle_id;
  if new.fleet_fuel_id is null and v_loc is not null then
    insert into fleet_fuel (tenant_id, company_id, location_id, doc_date, vehicle_id, source, litres, rate, odometer, meter_photo, bunk_issue_id)
    values (new.tenant_id, (select company_id from location where id = v_loc), v_loc, new.doc_date, new.vehicle_id, 'own_bunk',
            new.litres, new.transfer_rate, new.odometer, new.meter_photo, new.id::text)
    returning id into v_fuel;
    update bunk_internal_issue set fleet_fuel_id = v_fuel where id = new.id;
  elsif new.fleet_fuel_id is not null then
    update fleet_fuel set litres = new.litres, rate = new.transfer_rate, odometer = new.odometer where id = new.fleet_fuel_id;
  end if;
  if new.shift_id is not null then
    update bunk_shift set updated_at = now() where id = new.shift_id;
  end if;
  return null;
end;
$$;
create trigger bunk_internal_after after insert or update of litres, transfer_rate, odometer on public.bunk_internal_issue
  for each row execute function public.bunk_internal_after();

-- ---------------------------------------------------------------------------
-- Fleet
-- ---------------------------------------------------------------------------

create function public.fleet_fuel_compute() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  p fleet_fuel;
  v vehicle;
begin
  select * into v from vehicle where id = new.vehicle_id;
  if v.tank_capacity_l is not null and new.litres > v.tank_capacity_l * 1.05 then
    raise exception '% litres is more than this vehicle''s tank (% L).', new.litres, v.tank_capacity_l;
  end if;
  select * into p from fleet_fuel where vehicle_id = new.vehicle_id and id <> new.id
    and (doc_date < new.doc_date or (doc_date = new.doc_date and created_at < coalesce(new.created_at, now())))
  order by doc_date desc, created_at desc limit 1;
  if found then
    if new.odometer is not null and p.odometer is not null then
      if new.odometer < p.odometer then
        raise exception 'Odometer % is lower than the last fill (%). Check again?', new.odometer, p.odometer;
      end if;
      new.km_since_last := new.odometer - p.odometer;
      new.km_per_l := round(new.km_since_last / nullif(new.litres, 0), 2);
      if v.norm_km_per_l > 0 and new.km_per_l is not null then
        new.variance_pct := round((v.norm_km_per_l - new.km_per_l) / v.norm_km_per_l * 100, 1);
      end if;
    end if;
    if new.hour_meter is not null and p.hour_meter is not null then
      new.hours_since_last := new.hour_meter - p.hour_meter;
      new.l_per_hour := round(new.litres / nullif(new.hours_since_last, 0), 2);
      if v.norm_l_per_hour > 0 and new.l_per_hour is not null then
        new.variance_pct := round((new.l_per_hour - v.norm_l_per_hour) / v.norm_l_per_hour * 100, 1);
      end if;
    end if;
  end if;
  new.mismatch_alert := coalesce(new.variance_pct > 15, false)
    or coalesce(new.sensor_rise_l is not null and abs(new.sensor_rise_l - new.litres) > greatest(new.litres * 0.05, 5), false);
  return new;
end;
$$;
create trigger fleet_fuel_compute before insert or update on public.fleet_fuel for each row execute function public.fleet_fuel_compute();

create function public.fleet_update_meters() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_vehicle uuid := new.vehicle_id;
  v_km numeric;
  v_hr numeric;
begin
  if tg_table_name = 'fleet_fuel' then
    v_km := new.odometer; v_hr := new.hour_meter;
  elsif tg_table_name = 'fleet_trip' then
    v_km := new.end_odometer;
  elsif tg_table_name = 'fleet_machine_log' then
    v_hr := new.end_hours;
  end if;
  update vehicle set current_odometer = greatest(coalesce(current_odometer, 0), coalesce(v_km, 0)),
                     current_hours = greatest(coalesce(current_hours, 0), coalesce(v_hr, 0))
  where id = v_vehicle and (v_km is not null or v_hr is not null);
  return null;
end;
$$;
create trigger fleet_meters after insert or update on public.fleet_fuel for each row execute function public.fleet_update_meters();
create trigger fleet_meters after insert or update on public.fleet_trip for each row execute function public.fleet_update_meters();
create trigger fleet_meters after insert or update on public.fleet_machine_log for each row execute function public.fleet_update_meters();

-- ---------------------------------------------------------------------------
-- Weighbridge
-- ---------------------------------------------------------------------------

create function public.weighbridge_compute() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_tol numeric;
begin
  new.vehicle_no := upper(regexp_replace(new.vehicle_no, '[^A-Za-z0-9]', '', 'g'));
  if new.vehicle_id is null then
    select id into new.vehicle_id from vehicle where tenant_id = new.tenant_id and reg_no = new.vehicle_no;
  end if;
  if new.vehicle_id is not null and new.standard_tare_kg is null then
    select standard_tare_kg into new.standard_tare_kg from vehicle where id = new.vehicle_id;
  end if;
  if new.first_weight_kg is not null and new.first_weight_at is null then
    new.first_weight_at := now();
  end if;
  if new.second_weight_kg is not null and new.second_weight_at is null then
    new.second_weight_at := now();
  end if;
  if 'manual' in (new.first_mode, new.second_mode) and coalesce(trim(new.manual_reason), '') = '' then
    raise exception 'A typed (manual) weight needs a reason.';
  end if;
  if new.second_weight_kg is not null and new.first_weight_kg is not null then
    new.ticket_status := case when new.ticket_status = 'cancelled' then 'cancelled' else 'completed' end;
    new.minutes_between := (extract(epoch from new.second_weight_at - new.first_weight_at) / 60)::int;
    select coalesce((r.config ->> 'tolerance_kg')::numeric, 100) into v_tol
    from public.resolved_features(new.company_id, new.location_id, coalesce(auth.uid(), new.created_by)) r
    where r.feature_key = 'weighbridge.tare_check';
    new.tare_alert := new.standard_tare_kg is not null
      and abs(least(new.first_weight_kg, new.second_weight_kg) - new.standard_tare_kg) > coalesce(v_tol, 100);
  end if;
  return new;
end;
$$;
create trigger weighbridge_compute before insert or update on public.weighbridge_ticket
  for each row execute function public.weighbridge_compute();

-- ---------------------------------------------------------------------------
-- RMC
-- ---------------------------------------------------------------------------

create function public.grade_strength(p_grade text) returns numeric
language sql immutable as $$
  select case when p_grade ~ '^M[0-9.]+$' then substr(p_grade, 2)::numeric end
$$;

create function public.rmc_order_compute() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_lim numeric;
  v_days int;
  v_over boolean;
begin
  if new.mix_design_id is null then
    select id into new.mix_design_id from rmc_mix_design
    where location_id = new.location_id and grade = new.grade and is_active and status = 'approved'
    order by effective_from desc limit 1;
  end if;
  if new.rate_per_m3 is null and new.mix_design_id is not null then
    select selling_price_per_m3 into new.rate_per_m3 from rmc_mix_design where id = new.mix_design_id;
  end if;
  -- credit check when the order is first saved and again when submitted
  if tg_op = 'INSERT' or (new.status = 'submitted' and old.status is distinct from 'submitted')
     or new.credit_check = 'not_checked' then
    select credit_limit, credit_days into v_lim, v_days from party_company where party_id = new.party_id and company_id = new.company_id;
    new.outstanding_at_order := public.party_balance(new.company_id, new.party_id);
    if (select status from party where id = new.party_id) = 'blocked' then
      new.credit_check := 'over_limit';
    elsif v_lim is not null and v_lim > 0 then
      v_over := new.outstanding_at_order + coalesce(new.order_value, new.qty_m3 * coalesce(new.rate_per_m3, 0)) > v_lim;
      new.credit_check := case when v_over then 'over_limit' else 'ok' end;
    else
      new.credit_check := 'ok';
    end if;
  end if;
  if new.status = 'approved' and old.status is distinct from 'approved' and new.credit_check = 'over_limit'
     and (select rule_id from approval_request where id = new.approval_request_id) is null then
    raise exception 'This customer is over the credit limit (outstanding ₹%). Collect payment, or ask the admin to add a credit-override approval rule for RMC orders.',
      round(new.outstanding_at_order);
  end if;
  return new;
end;
$$;
create trigger rmc_order_compute before insert or update on public.rmc_order for each row execute function public.rmc_order_compute();

create function public.rmc_batch_material_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  b rmc_batch;
begin
  if new.target_qty is null then
    select * into b from rmc_batch where id = new.parent_id;
    select round(m.qty_per_m3 * b.qty_m3, 3) into new.target_qty
    from rmc_order o join rmc_mix_design_materials m on m.parent_id = o.mix_design_id
    where o.id = b.order_id and m.item_id = new.item_id;
  end if;
  return new;
end;
$$;
create trigger rmc_batch_material_defaults before insert on public.rmc_batch_materials
  for each row execute function public.rmc_batch_material_defaults();

create function public.rmc_batch_after() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- no weights sent: assume the mix design was batched exactly (plant controller import replaces this)
  if tg_op = 'INSERT' and not exists (select 1 from rmc_batch_materials where parent_id = new.id) then
    insert into rmc_batch_materials (tenant_id, parent_id, line_no, item_id, target_qty, actual_qty)
    select new.tenant_id, new.id, row_number() over (), m.item_id, round(m.qty_per_m3 * new.qty_m3, 3), round(m.qty_per_m3 * new.qty_m3, 3)
    from rmc_order o join rmc_mix_design_materials m on m.parent_id = o.mix_design_id where o.id = new.order_id;
    update rmc_batch set updated_at = now() where id = new.id;
  end if;
  return null;
end;
$$;
create trigger rmc_batch_after after insert on public.rmc_batch for each row execute function public.rmc_batch_after();

create function public.rmc_batch_compute() returns trigger
language plpgsql as $$
begin
  new.deviation_alert := coalesce(new.max_deviation_pct > 3, false);
  return new;
end;
$$;
create trigger rmc_batch_zcompute before insert or update on public.rmc_batch for each row execute function public.rmc_batch_compute();

create function public.rmc_challan_compute() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  o rmc_order;
begin
  select * into o from rmc_order where id = new.order_id;
  new.party_id := coalesce(new.party_id, o.party_id);
  new.grade := coalesce(new.grade, o.grade);
  if new.batch_id is not null and new.vehicle_id is null then
    select vehicle_id into new.vehicle_id from rmc_batch where id = new.batch_id;
  end if;
  return new;
end;
$$;
create trigger rmc_challan_compute before insert or update on public.rmc_challan for each row execute function public.rmc_challan_compute();

create function public.rmc_order_progress() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_order uuid := coalesce(new.order_id, old.order_id);
  v_done numeric;
begin
  select coalesce(sum(qty_m3 - coalesce(returned_m3, 0)), 0) into v_done from rmc_challan where order_id = v_order;
  update rmc_order set delivered_m3 = v_done,
    delivery_status = case when delivery_status in ('cancelled', 'short_closed') then delivery_status
                           when v_done >= qty_m3 then 'completed' when v_done > 0 then 'in_progress' else 'scheduled' end
  where id = v_order;
  return null;
end;
$$;
create trigger rmc_order_progress after insert or update or delete on public.rmc_challan for each row execute function public.rmc_order_progress();

create function public.rmc_cube_compute() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_28 numeric;
  v_n  int;
  v_min int;
begin
  new.required_strength := coalesce(new.required_strength, public.grade_strength(new.grade));
  select avg(strength), count(*) into v_28, v_n from rmc_cube_test_results where parent_id = new.id and age_days = 28;
  new.avg_28_day := round(v_28, 2);
  v_min := 3;
  if v_n >= v_min then
    -- IS 456 acceptance (simplified): mean ≥ fck + 0.825 × 4 (approx. for small samples) is not applied;
    -- here: mean ≥ fck and no single cube below fck − 4
    new.result := case when v_28 >= new.required_strength
                        and not exists (select 1 from rmc_cube_test_results where parent_id = new.id and age_days = 28
                                        and strength < new.required_strength - 4)
                       then 'pass' else 'fail' end;
  end if;
  return new;
end;
$$;
create trigger rmc_cube_compute before insert or update on public.rmc_cube_test for each row execute function public.rmc_cube_compute();

-- ---------------------------------------------------------------------------
-- Billing runs: unbilled challans / dispatches → one draft GST invoice per customer
-- ---------------------------------------------------------------------------

create function public.billing_item(p_tenant uuid, p_code text, p_name text, p_hsn text, p_gst numeric, p_uom text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  select id into v_id from item where tenant_id = p_tenant and item_code = p_code;
  if v_id is null then
    insert into item (tenant_id, item_code, name, category, base_uom, hsn_sac, gst_rate)
    values (p_tenant, p_code, p_name, 'finished_good', p_uom, p_hsn, p_gst) returning id into v_id;
  end if;
  return v_id;
end;
$$;

-- Creates draft invoices for everything delivered and not yet billed up to a date. Returns the invoices made.
create function public.billing_run(p_source text, p_company uuid, p_location uuid, p_date_to date default current_date,
                                   p_party uuid default null)
returns table (invoice_id uuid, party_id uuid, lines int, amount numeric)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_tenant uuid := (select tenant_id from company where id = p_company);
  v_state text;
  r record;
  v_inv uuid;
  v_n int;
begin
  if not public.user_can('finance.sales_invoice', 'create', p_company, p_location) then
    raise exception 'You are not allowed to create invoices here.' using errcode = '42501';
  end if;
  select left(g.gstin, 2) into v_state from location l left join company_gstin g on g.id = l.gstin_id where l.id = p_location;

  for r in
    select x.party_id, jsonb_agg(x.line order by x.doc_date, x.doc_no) as lines, array_agg(x.id) as ids
    from (
      select c.party_id, c.id, c.doc_date, c.doc_no, jsonb_build_object(
        'item_id', public.billing_item(v_tenant, 'RMC-' || c.grade, 'Ready mix concrete ' || c.grade, '38245010', 18, 'M3'),
        'description', 'Challan ' || c.doc_no || ' dt ' || to_char(c.doc_date, 'DD-MM-YYYY'),
        'hsn_sac', '38245010', 'qty', c.qty_m3 - coalesce(c.returned_m3, 0), 'uom', 'M3',
        'rate', coalesce(o.rate_per_m3, 0), 'gst_rate', 18) as line
      from rmc_challan c join rmc_order o on o.id = c.order_id
      where p_source = 'rmc.challan' and c.company_id = p_company and c.location_id = p_location
        and c.billing_status = 'unbilled' and c.doc_date <= p_date_to and (p_party is null or c.party_id = p_party)
        and c.receiver_name is not null
      union all
      select d.party_id, d.id, d.doc_date, d.doc_no, jsonb_build_object(
        'item_id', public.billing_item(v_tenant, 'HOTMIX-' || d.mix_type, 'Bituminous mix ' || d.mix_type, '27150090', 18, 'MT'),
        'description', 'Dispatch ' || d.doc_no || ' ' || coalesce(d.vehicle_no, ''),
        'hsn_sac', '27150090', 'qty', d.net_mt, 'uom', 'MT', 'rate', coalesce(d.rate_per_mt, 0), 'gst_rate', 18)
      from bitumen_dispatch d
      where p_source = 'bitumen.dispatch' and d.company_id = p_company and d.location_id = p_location
        and d.billing_status = 'unbilled' and d.doc_date <= p_date_to and (p_party is null or d.party_id = p_party)
        and coalesce(d.site_acceptance, 'accepted') = 'accepted'
      union all
      select d.party_id, d.id, d.doc_date, d.doc_no, jsonb_build_object(
        'item_id', d.product_id, 'description', 'Dispatch ' || d.doc_no, 'hsn_sac', coalesce(i.hsn_sac, '6815'),
        'qty', d.qty, 'uom', 'NOS', 'rate', round(coalesce(d.rate_per_1000, 0) / 1000, 4), 'gst_rate', coalesce(i.gst_rate, 5))
      from bricks_dispatch d join item i on i.id = d.product_id
      where p_source = 'bricks.dispatch' and d.company_id = p_company and d.location_id = p_location
        and d.billing_status = 'unbilled' and d.doc_date <= p_date_to and (p_party is null or d.party_id = p_party)
    ) x
    group by x.party_id
  loop
    v_inv := gen_random_uuid();
    insert into finance_sales_invoice (id, tenant_id, company_id, location_id, doc_no, doc_date, party_id, place_of_supply,
                                       source_entity, source_ids, due_date)
    values (v_inv, v_tenant, p_company, p_location,
            public.doc_number_internal(p_company, p_location, 'finance.sales_invoice', p_date_to), p_date_to, r.party_id,
            coalesce((select state_code from party_gstin where party_id = r.party_id limit 1), v_state, '00'),
            p_source, to_jsonb(r.ids),
            p_date_to + coalesce((select credit_days from party_company where party_id = r.party_id and company_id = p_company), 0));
    insert into finance_sales_invoice_lines (tenant_id, parent_id, line_no, item_id, description, hsn_sac, qty, uom, rate, gst_rate)
    select v_tenant, v_inv, n, (l ->> 'item_id')::uuid, l ->> 'description', l ->> 'hsn_sac', (l ->> 'qty')::numeric,
           l ->> 'uom', (l ->> 'rate')::numeric, (l ->> 'gst_rate')::numeric
    from jsonb_array_elements(r.lines) with ordinality j(l, n);
    update finance_sales_invoice set updated_at = now(),
      is_interstate = place_of_supply <> coalesce(v_state, place_of_supply)
    where id = v_inv;
    v_n := jsonb_array_length(r.lines);

    if p_source = 'rmc.challan' then
      update rmc_challan set billing_status = 'billed', invoice_id = v_inv where id = any(r.ids);
    elsif p_source = 'bitumen.dispatch' then
      update bitumen_dispatch set billing_status = 'billed' where id = any(r.ids);
    else
      update bricks_dispatch set billing_status = 'billed' where id = any(r.ids);
    end if;

    invoice_id := v_inv; party_id := r.party_id; lines := v_n;
    amount := (select grand_total from finance_sales_invoice where id = v_inv);
    return next;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Purchase & stores
-- ---------------------------------------------------------------------------

-- PO lines show the last rate paid for the item anywhere in the group.
create function public.po_line_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select l.rate into new.last_rate
  from purchase_po_lines l join purchase_po p on p.id = l.parent_id
  where l.item_id = new.item_id and p.tenant_id = new.tenant_id and l.parent_id <> new.parent_id and p.status = 'approved'
  order by p.doc_date desc, p.created_at desc limit 1;
  if new.hsn_sac is null or new.gst_rate is null then
    select coalesce(new.hsn_sac, hsn_sac), coalesce(new.gst_rate, gst_rate) into new.hsn_sac, new.gst_rate from item where id = new.item_id;
  end if;
  return new;
end;
$$;
create trigger po_line_defaults before insert on public.purchase_po_lines for each row execute function public.po_line_defaults();

create function public.grn_line_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_po uuid;
begin
  if new.rate is null then
    select po_id into v_po from purchase_grn where id = new.parent_id;
    select rate into new.rate from purchase_po_lines where parent_id = v_po and item_id = new.item_id limit 1;
  end if;
  return new;
end;
$$;
create trigger grn_line_defaults before insert on public.purchase_grn_lines for each row execute function public.grn_line_defaults();

-- After a GRN: PO received quantities and status.
create function public.grn_update_po() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_po uuid := coalesce(new.po_id, old.po_id);
begin
  if v_po is null then return null; end if;
  update purchase_po_lines pl set received_qty = coalesce((
    select sum(gl.accepted_qty) from purchase_grn_lines gl join purchase_grn g on g.id = gl.parent_id
    where g.po_id = v_po and gl.item_id = pl.item_id), 0)
  where pl.parent_id = v_po;
  update purchase_po p set receipt_status = case
      when receipt_status = 'short_closed' then receipt_status
      when not exists (select 1 from purchase_po_lines where parent_id = v_po and received_qty < qty) then 'complete'
      when exists (select 1 from purchase_po_lines where parent_id = v_po and received_qty > 0) then 'partly'
      else 'pending' end
  where p.id = v_po;
  return null;
end;
$$;
create trigger grn_update_po after insert or update or delete on public.purchase_grn for each row execute function public.grn_update_po();

-- 3-way match for a purchase invoice: PO rate × GRN qty vs invoice, within the tolerance set in admin.
create function public.purchase_three_way_match(p_invoice uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  inv finance_purchase_invoice;
  v_rate_tol numeric;
  v_qty_tol numeric;
  v_notes text := '';
  v_status text := 'matched';
  r record;
begin
  select * into inv from finance_purchase_invoice where id = p_invoice;
  select coalesce((config ->> 'rate_tolerance_pct')::numeric, 1), coalesce((config ->> 'qty_tolerance_pct')::numeric, 0.5)
    into v_rate_tol, v_qty_tol
  from public.resolved_features(inv.company_id, inv.location_id, coalesce(auth.uid(), inv.created_by)) where feature_key = 'purchase.three_way_match';
  if inv.grn_id is null then
    v_status := 'no_grn';
  else
    for r in
      select il.item_id, (select name from item where id = il.item_id) as name, il.qty as inv_qty, il.rate as inv_rate,
             (select sum(gl.accepted_qty) from purchase_grn_lines gl where gl.parent_id = inv.grn_id and gl.item_id = il.item_id) as grn_qty,
             (select pl.rate from purchase_po_lines pl where pl.parent_id = inv.po_id and pl.item_id = il.item_id limit 1) as po_rate
      from finance_purchase_invoice_lines il where il.parent_id = p_invoice
    loop
      if r.po_rate is not null and abs(r.inv_rate - r.po_rate) > r.po_rate * coalesce(v_rate_tol, 1) / 100 then
        v_status := 'rate_mismatch';
        v_notes := v_notes || format('%s: billed ₹%s, PO ₹%s. ', r.name, trim_scale(r.inv_rate), trim_scale(r.po_rate));
      end if;
      if coalesce(r.grn_qty, 0) = 0 or abs(r.inv_qty - r.grn_qty) > r.grn_qty * coalesce(v_qty_tol, 0.5) / 100 then
        v_status := case when v_status = 'rate_mismatch' then v_status else 'qty_mismatch' end;
        v_notes := v_notes || format('%s: billed %s, received %s. ', r.name, trim_scale(r.inv_qty), trim_scale(coalesce(r.grn_qty, 0)));
      end if;
    end loop;
  end if;
  update finance_purchase_invoice set match_status = v_status, match_notes = nullif(trim(v_notes), '') where id = p_invoice;
  return v_status;
end;
$$;

update public.erp_entity set submit_hook = 'purchase_three_way_match' where key = 'finance.purchase_invoice';

-- A bill that does not match its PO and GRN cannot slip through on auto-approval.
create function public.purchase_invoice_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved'
     and new.match_status in ('rate_mismatch', 'qty_mismatch')
     and (select rule_id from approval_request where id = new.approval_request_id) is null then
    raise exception 'Bill does not match PO/GRN: %. Correct it, raise a debit note, or ask the admin for an approval rule for mismatched bills.',
      new.match_notes;
  end if;
  return new;
end;
$$;
create trigger purchase_invoice_guard before update of status on public.finance_purchase_invoice
  for each row execute function public.purchase_invoice_guard();

-- Stock count: system qty captured when the count is saved (the counter never sees it on the form).
create function public.stock_count_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_loc uuid;
begin
  select location_id into v_loc from purchase_stock_count where id = new.parent_id;
  new.system_qty := coalesce((select sum(qty) from stock_move where location_id = v_loc and item_id = new.item_id), 0);
  return new;
end;
$$;
create trigger stock_count_defaults before insert on public.purchase_stock_count_lines for each row execute function public.stock_count_defaults();
-- Counters do not see system stock: hidden for everyone below approver level via role masks; set up in admin.

-- ---------------------------------------------------------------------------
-- Construction projects
-- ---------------------------------------------------------------------------

create function public.infra_dpr_approved() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and (new.status = 'approved' or old.status = 'approved') then
    update infra_boq_item b set done_qty = coalesce((
      select sum(w.qty) from infra_dpr_work w join infra_dpr d on d.id = w.parent_id
      where w.boq_item_id = b.id and d.status = 'approved'), 0)
    where b.id in (select boq_item_id from infra_dpr_work where parent_id = new.id);
    update infra_project p set physical_progress_pct = (
      select round(sum(least(b.done_qty, b.contract_qty) * b.rate) / nullif(sum(b.contract_qty * b.rate), 0) * 100, 1)
      from infra_boq_item b where b.project_id = p.id)
    where p.id = new.project_id;
  end if;
  return null;
end;
$$;
create trigger infra_dpr_approved after update of status on public.infra_dpr for each row execute function public.infra_dpr_approved();

create function public.infra_ra_line_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.previous_qty, 0) = 0 then
    select coalesce(sum(l.this_qty), 0) into new.previous_qty
    from infra_ra_bill_lines l join infra_ra_bill r on r.id = l.parent_id
    where l.boq_item_id = new.boq_item_id and r.status = 'approved' and r.id <> new.parent_id;
  end if;
  if new.rate is null then
    select rate into new.rate from infra_boq_item where id = new.boq_item_id;
  end if;
  return new;
end;
$$;
create trigger infra_ra_line_defaults before insert on public.infra_ra_bill_lines for each row execute function public.infra_ra_line_defaults();

-- Deductions from the contract's percentages unless typed in.
create function public.infra_ra_compute() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  p infra_project;
  v_recovered numeric;
begin
  select * into p from infra_project where id = new.project_id;
  if new.bill_no is null then
    select coalesce(max(bill_no), 0) + 1 into new.bill_no from infra_ra_bill where project_id = new.project_id and id <> new.id;
  end if;
  if new.status in ('draft', 'sent_back') then
    new.retention := round(coalesce(new.this_bill_value, 0) * coalesce(p.retention_pct, 0) / 100, 2);
    new.security_deposit := round(coalesce(new.this_bill_value, 0) * coalesce(p.security_deposit_pct, 0) / 100, 2);
    new.income_tax_tds := round(coalesce(new.this_bill_value, 0) * coalesce(p.income_tax_tds_pct, 0) / 100, 2);
    new.gst_tds := round(coalesce(new.this_bill_value, 0) * coalesce(p.gst_tds_pct, 0) / 100, 2);
    new.labour_cess := round(coalesce(new.this_bill_value, 0) * coalesce(p.labour_cess_pct, 0) / 100, 2);
    select coalesce(sum(mobilisation_recovery), 0) into v_recovered from infra_ra_bill
    where project_id = new.project_id and status = 'approved' and id <> new.id;
    new.mobilisation_recovery := least(round(coalesce(new.this_bill_value, 0) * coalesce(p.mobilisation_recovery_pct, 0) / 100, 2),
                                       greatest(coalesce(p.mobilisation_advance, 0) - v_recovered, 0));
    new.gst_amount := round(coalesce(new.this_bill_value, 0) * 0.18, 2);
  end if;
  return new;
end;
$$;
create trigger infra_ra_zcompute before insert or update on public.infra_ra_bill for each row execute function public.infra_ra_compute();

create function public.infra_ra_approved() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and (new.status = 'approved' or old.status = 'approved') then
    update infra_boq_item b set billed_qty = coalesce((
      select sum(l.this_qty) from infra_ra_bill_lines l join infra_ra_bill r on r.id = l.parent_id
      where l.boq_item_id = b.id and r.status = 'approved'), 0)
    where b.id in (select boq_item_id from infra_ra_bill_lines where parent_id = new.id);
  end if;
  return null;
end;
$$;
create trigger infra_ra_approved after update of status on public.infra_ra_bill for each row execute function public.infra_ra_approved();

-- Project health one-pager.
create function public.project_health(p_project uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  p infra_project;
  v jsonb;
begin
  select * into p from infra_project where id = p_project;
  if not public.user_can('infra.project_health', 'view', p.company_id, p.location_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'project', p.name,
    'physical_pct', p.physical_progress_pct,
    'time_elapsed_pct', round(greatest(0, least(100, (current_date - p.start_date)::numeric / nullif(p.end_date - p.start_date, 0) * 100)), 1),
    'billed', (select coalesce(sum(this_bill_value), 0) from infra_ra_bill where project_id = p.id and status = 'approved'),
    'certified', (select coalesce(sum(certified_value), 0) from infra_ra_bill where project_id = p.id and status = 'approved'),
    'received', (select coalesce(sum(received), 0) from infra_ra_bill where project_id = p.id),
    'financial_pct', round((select coalesce(sum(this_bill_value), 0) from infra_ra_bill where project_id = p.id and status = 'approved')
                            / nullif(p.contract_value, 0) * 100, 1),
    'unbilled_work', (select coalesce(sum(greatest(done_qty - billed_qty, 0) * rate), 0) from infra_boq_item where project_id = p.id),
    'hindrance_days', (select count(*) from infra_dpr where project_id = p.id and hindrance_cause <> 'none' and status = 'approved'),
    'manpower_last_7_days', (select coalesce(avg(total_manpower), 0)::int from infra_dpr where project_id = p.id and doc_date > current_date - 7)
  ) into v;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Bricks
-- ---------------------------------------------------------------------------

create function public.bricks_production_after() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r bricks_recipe;
begin
  select * into r from bricks_recipe where location_id = new.location_id and product_id = new.product_id order by created_at desc limit 1;
  if tg_op = 'INSERT' then
    if not exists (select 1 from bricks_production_materials where parent_id = new.id) and r.id is not null then
      insert into bricks_production_materials (tenant_id, parent_id, line_no, item_id, qty)
      select new.tenant_id, new.id, m.line_no, m.item_id, round(m.qty * (new.good_units + coalesce(new.rejected_units, 0)) / nullif(r.per_units, 0), 3)
      from bricks_recipe_materials m where m.parent_id = r.id;
      update bricks_production set updated_at = now() where id = new.id;
    end if;
    insert into bricks_curing_lot (tenant_id, company_id, location_id, doc_no, doc_date, production_id, product_id, qty, curing_block, ready_on)
    values (new.tenant_id, new.company_id, new.location_id,
            public.doc_number_internal(new.company_id, new.location_id, 'bricks.curing_lot', new.doc_date),
            new.doc_date, new.id, new.product_id, new.good_units, new.curing_block, new.doc_date + coalesce(r.curing_days, 14));
  elsif new.good_units <> old.good_units then
    update bricks_curing_lot set qty = new.good_units where production_id = new.id;
  end if;
  return null;
end;
$$;
create trigger bricks_production_after after insert or update of good_units on public.bricks_production
  for each row execute function public.bricks_production_after();

create function public.bricks_lot_compute() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.broken := coalesce((select sum(qty) from bricks_breakage where lot_id = new.id), 0);
  new.dispatched := coalesce((select sum(qty) from bricks_dispatch where lot_id = new.id and coalesce(billing_status, '') <> 'cancelled'), 0);
  new.lot_status := case
    when new.qty - new.broken - new.dispatched <= 0 then 'finished'
    when new.dispatched > 0 then 'partly_dispatched'
    when new.ready_on <= current_date then 'ready'
    else 'curing' end;
  return new;
end;
$$;
create trigger bricks_lot_compute before insert or update on public.bricks_curing_lot for each row execute function public.bricks_lot_compute();

create function public.bricks_touch_lot() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_lot uuid := coalesce(new.lot_id, old.lot_id);
  v_avail int;
begin
  if tg_table_name = 'bricks_dispatch' and tg_op <> 'DELETE' and new.lot_id is not null then
    select qty - broken - dispatched + coalesce(case when tg_op = 'UPDATE' and old.lot_id = new.lot_id then old.qty end, 0)
      into v_avail from bricks_curing_lot where id = new.lot_id;
    if (select ready_on from bricks_curing_lot where id = new.lot_id) > new.doc_date then
      raise exception 'This lot is still curing until %.', (select to_char(ready_on, 'DD Mon') from bricks_curing_lot where id = new.lot_id);
    end if;
    if new.qty > v_avail then
      raise exception 'Only % units are available in this lot.', v_avail;
    end if;
  end if;
  if v_lot is not null then
    update bricks_curing_lot set updated_at = now() where id = v_lot;
  end if;
  return null;
end;
$$;
create trigger bricks_touch_lot after insert or update or delete on public.bricks_dispatch for each row execute function public.bricks_touch_lot();
create trigger bricks_touch_lot after insert or update or delete on public.bricks_breakage for each row execute function public.bricks_touch_lot();

-- ---------------------------------------------------------------------------
-- Bitumen / hot-mix
-- ---------------------------------------------------------------------------

create function public.bitumen_batch_compute() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  j bitumen_jmf;
begin
  select * into j from bitumen_jmf where id = new.jmf_id;
  new.temp_alert := new.mix_temp_c < coalesce(j.mix_temp_min_c, 0) or new.mix_temp_c > coalesce(j.mix_temp_max_c, 999);
  if new.bitumen_kg is null then
    new.bitumen_kg := round(new.batch_mt * 1000 * coalesce(j.bitumen_pct, 0) / 100, 1);
  end if;
  return new;
end;
$$;
create trigger bitumen_batch_compute before insert or update on public.bitumen_batch for each row execute function public.bitumen_batch_compute();

create function public.bitumen_dispatch_compute() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  t weighbridge_ticket;
begin
  if new.weighbridge_ticket_id is not null then
    select * into t from weighbridge_ticket where id = new.weighbridge_ticket_id;
    new.net_mt := coalesce(new.net_mt, round(t.final_kg / 1000, 3));
    new.vehicle_no := coalesce(new.vehicle_no, t.vehicle_no);
  end if;
  return new;
end;
$$;
create trigger bitumen_dispatch_compute before insert or update on public.bitumen_dispatch for each row execute function public.bitumen_dispatch_compute();

-- ---------------------------------------------------------------------------
-- HR & payroll
-- ---------------------------------------------------------------------------

-- Builds the payroll run's lines from attendance, salary structure, advances and statutory rules.
-- Rules (editable in the hr.payroll switch config): PF 12% of basic+DA up to a 15,000 wage ceiling, ESI 0.75% / 3.25%
-- when gross ≤ 21,000, professional tax by state slab, OT at double the hourly rate.
create function public.hr_generate_payroll(p_run uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  run hr_payroll_run;
  cfg jsonb;
  e   hr_employee;
  v_start date;
  v_end date;
  v_days int;
  v_paid numeric;
  v_ot numeric;
  v_basic numeric;
  v_other numeric;
  v_ot_amt numeric;
  v_gross numeric;
  v_pf_wage numeric;
  v_pf numeric;
  v_esi_e numeric;
  v_esi_r numeric;
  v_pt numeric;
  v_adv numeric;
  v_n int := 0;
  v_anom jsonb;
begin
  select * into run from hr_payroll_run where id = p_run;
  if not public.user_can('hr.payroll', 'create', run.company_id, run.location_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if run.status not in ('draft', 'sent_back') then
    raise exception 'This payroll run is already %.', run.status;
  end if;
  select config into cfg from public.resolved_features(run.company_id, run.location_id) where feature_key = 'hr.payroll';
  cfg := coalesce(cfg, '{}');
  v_start := to_date(run.month || '-01', 'YYYY-MM-DD');
  v_end := (v_start + interval '1 month - 1 day')::date;
  v_days := v_end - v_start + 1;

  delete from hr_payroll_run_lines where parent_id = p_run;
  for e in select * from hr_employee where location_id = run.location_id and emp_status in ('active', 'on_notice')
           and date_of_joining <= v_end order by emp_code loop
    v_anom := '[]';
    select coalesce(sum(case mark when 'present' then 1 when 'half_day' then 0.5 when 'leave' then 1 when 'weekly_off' then 1
                                   when 'holiday' then 1 when 'on_duty' then 1 else 0 end), 0),
           coalesce(sum(ot_hours), 0)
      into v_paid, v_ot
    from hr_attendance where employee_id = e.id and doc_date between v_start and v_end;
    -- unpaid leave reduces paid days
    v_paid := v_paid - coalesce((select sum(days) from hr_leave where employee_id = e.id and status = 'approved' and leave_type = 'unpaid'
                                  and from_date between v_start and v_end), 0);
    if v_paid > v_days then
      v_anom := v_anom || to_jsonb(format('%s paid days in a %s-day month', v_paid, v_days));
      v_paid := v_days;
    end if;
    if v_ot > 60 then
      v_anom := v_anom || to_jsonb(format('very high overtime: %s hours', v_ot));
    end if;
    if e.pay_basis = 'daily' then
      v_basic := round(coalesce(e.daily_wage, 0) * v_paid, 2);
      v_other := 0;
      v_ot_amt := round(coalesce(e.daily_wage, 0) / 8 * 2 * v_ot, 2);
    else
      v_basic := round((coalesce(e.basic, 0) + coalesce(e.da, 0)) * v_paid / v_days, 2);
      v_other := round((coalesce(e.hra, 0) + coalesce(e.other_allowance, 0)) * v_paid / v_days, 2);
      v_ot_amt := round(coalesce(e.monthly_gross, 0) / v_days / 8 * 2 * v_ot, 2);
    end if;
    v_gross := v_basic + v_other + v_ot_amt;
    v_pf_wage := least(v_basic, coalesce((cfg ->> 'pf_wage_ceiling')::numeric, 15000));
    v_pf := case when e.pf_applicable then round(v_pf_wage * 0.12) else 0 end;
    if e.esi_applicable and v_gross <= coalesce((cfg ->> 'esi_wage_ceiling')::numeric, 21000) then
      v_esi_e := ceil(v_gross * 0.0075);
      v_esi_r := ceil(v_gross * 0.0325);
    else
      v_esi_e := 0; v_esi_r := 0;
    end if;
    -- Andhra Pradesh / Telangana slab by default; override with {"pt_slabs": [[15000,0],[20000,150],[null,200]]}
    v_pt := coalesce((select (s ->> 1)::numeric from jsonb_array_elements(coalesce(cfg -> 'pt_slabs', '[[15000,0],[20000,150],[null,200]]')) s
                      where s ->> 0 is null or v_gross <= (s ->> 0)::numeric
                      order by (s ->> 0)::numeric nulls last limit 1), 0);
    select coalesce(sum(least(balance, round(amount / greatest(recover_in_months, 1), 2))), 0) into v_adv
    from hr_advance where employee_id = e.id and status = 'approved' and balance > 0;
    if v_adv > v_gross * 0.5 then
      v_anom := v_anom || to_jsonb(format('advance recovery ₹%s is more than half the salary', v_adv));
    end if;
    if v_paid = 0 then
      v_anom := v_anom || to_jsonb('no attendance this month'::text);
    end if;

    v_n := v_n + 1;
    insert into hr_payroll_run_lines (tenant_id, parent_id, line_no, employee_id, paid_days, ot_hours, earned_basic_da, earned_other,
      ot_amount, incentive, pf_employee, pf_employer, esi_employee, esi_employer, pt, tds, advance_recovery, anomalies)
    values (run.tenant_id, p_run, v_n, e.id, v_paid, v_ot, v_basic, v_other, v_ot_amt, 0, v_pf, v_pf, v_esi_e, v_esi_r,
            v_pt, 0, v_adv, case when jsonb_array_length(v_anom) > 0 then v_anom end);
  end loop;
  update hr_payroll_run set updated_at = now(), days_in_month = v_days where id = p_run;
  return jsonb_build_object('employees', v_n,
    'with_checks', (select count(*) from hr_payroll_run_lines where parent_id = p_run and anomalies is not null));
end;
$$;

-- Approved payroll: advances recovered.
create function public.hr_payroll_approved() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  l record;
  v_left numeric;
  a hr_advance;
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    for l in select employee_id, advance_recovery from hr_payroll_run_lines where parent_id = new.id and advance_recovery > 0 loop
      v_left := l.advance_recovery;
      for a in select * from hr_advance where employee_id = l.employee_id and status = 'approved' and balance > 0 order by doc_date loop
        exit when v_left <= 0;
        update hr_advance set recovered = recovered + least(v_left, a.balance) where id = a.id;
        v_left := v_left - least(v_left, a.balance);
      end loop;
    end loop;
  end if;
  return null;
end;
$$;
create trigger hr_payroll_approved after update of status on public.hr_payroll_run for each row execute function public.hr_payroll_approved();

-- Posting rule variants are consulted by fin_post_document.
create or replace function public.fin_post_document(p_entity text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  e        erp_entity := public.erp_entity_row(p_entity);
  v_row    jsonb;
  v_rule   jsonb;
  v_lines  jsonb := '[]';
  v_hash   text;
  v_should boolean;
  v_co     uuid;
  v_loc    uuid;
  v_date   date;
  v_dr     numeric;
  v_cr     numeric;
  v_party  uuid;
  v_icco   uuid;
  j        record;
  v_ref    text;
begin
  execute format('select to_jsonb(t) from public.%I t where t.id = $1', e.table_name) using p_id into v_row;
  if v_row is null then return; end if;
  v_co := (v_row ->> 'company_id')::uuid;
  v_loc := (v_row ->> 'location_id')::uuid;
  v_date := coalesce((v_row ->> 'doc_date')::date, current_date);
  v_rule := public.fin_rule_for(p_entity, v_row, e.posting);
  if v_rule is null then return; end if;

  v_should := case when e.workflow then v_row ->> 'status' = 'approved' else coalesce(v_row ->> 'status', '') <> 'cancelled' end;
  if v_should then
    v_lines := public.fin_build_lines(p_entity, v_row, v_co, v_rule);
    select coalesce(sum((l ->> 'debit')::numeric), 0), coalesce(sum((l ->> 'credit')::numeric), 0)
      into v_dr, v_cr from jsonb_array_elements(v_lines) l;
    if v_dr <> v_cr then
      raise exception 'Posting for % % does not balance (Dr % / Cr %). Check the posting rule.',
        e.label, coalesce(v_row ->> 'doc_no', ''), v_dr, v_cr;
    end if;
  end if;
  v_hash := case when jsonb_array_length(v_lines) = 0 then null else md5(v_lines::text || v_date::text) end;

  for j in select fj.id, fj.posting_hash from finance_journal fj
           where fj.source_entity = p_entity and fj.source_id = p_id::text and fj.company_id = v_co
             and not fj.is_reversal and fj.status = 'approved'
             and not exists (select 1 from finance_journal r where r.source_entity = 'finance.journal'
                             and r.source_id = fj.id::text and r.is_reversal) loop
    if j.posting_hash is not distinct from v_hash then
      return;
    end if;
    perform public.fin_reverse_journal(j.id);
  end loop;

  if v_hash is null then return; end if;

  v_party := public.fin_party_of(p_entity, v_rule, v_row);
  select group_company_id into v_icco from party where id = v_party;
  v_ref := case when v_icco is not null then 'IC-' || left(p_id::text, 8) end;

  perform public.fin_write_journal(v_co, v_loc, v_date, v_rule ->> 'voucher',
    e.label || ' ' || coalesce(v_row ->> 'doc_no', ''), p_entity, p_id, v_row ->> 'doc_no', v_lines, v_hash,
    false, v_icco is not null, v_icco, v_ref);

  if v_icco is not null and v_icco <> v_co then
    perform public.fin_write_journal(v_icco, null, v_date,
      case v_rule ->> 'voucher' when 'sales' then 'purchase' when 'purchase' then 'sales'
                                 when 'receipt' then 'payment' when 'payment' then 'receipt' else 'journal' end,
      'Inter-company: ' || e.label || ' ' || coalesce(v_row ->> 'doc_no', '') || ' from ' ||
        (select short_code from company where id = v_co),
      p_entity, p_id, v_row ->> 'doc_no', public.fin_mirror_lines(v_lines, v_co, v_icco), v_hash,
      false, true, v_co, v_ref);
  end if;
end;
$$;

select public.erp_install_post_triggers();
