-- Reports and GST files: P&L, balance sheet, ageing, party statement, day book, bunk DSR,
-- e-invoice (NIC INV-01 v1.1), e-way bill and GSTR-1 JSON, period lock, owner's daily summary.

create function public.fin_can_view(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_company in (select public.my_company_ids()) and public.user_can('finance.ledger', 'view', p_company, null)
$$;

-- Lines of approved journals in the companies the person can see; p_company null = whole group.
create function public.fin_lines(p_company uuid, p_from date, p_to date, p_eliminate boolean default true)
returns table (company_id uuid, doc_date date, ledger_id uuid, code text, name text, ledger_group text, nature text,
               party_id uuid, debit numeric, credit numeric, is_intercompany boolean, journal_id uuid, doc_no text, narration text)
language sql stable security definer set search_path = public as $$
  select j.company_id, j.doc_date, fl.id, fl.code, fl.name, fl.ledger_group, fl.nature, l.party_id, l.debit, l.credit,
         j.is_intercompany, j.id, j.doc_no, j.narration
  from finance_journal j
  join finance_journal_lines l on l.parent_id = j.id
  join finance_ledger fl on fl.id = l.ledger_id
  where j.status = 'approved'
    and (p_company is null or j.company_id = p_company)
    and public.fin_can_view(j.company_id)
    and (p_from is null or j.doc_date >= p_from) and (p_to is null or j.doc_date <= p_to)
    and not (p_eliminate and p_company is null and j.is_intercompany)
$$;

-- Profit and loss: income and expense by group and ledger, with the net profit line.
create function public.profit_and_loss(p_company uuid default null,
                                       p_from date default make_date(extract(year from current_date - interval '3 months')::int, 4, 1),
                                       p_to date default current_date)
returns table (section text, ledger_group text, ledger_name text, amount numeric)
language sql stable security definer set search_path = public as $$
  with x as (
    select case when nature = 'income' then 'Income' else 'Expenses' end as section, ledger_group, name,
           sum(case when nature = 'income' then credit - debit else debit - credit end) as amount
    from public.fin_lines(p_company, p_from, p_to)
    where nature in ('income', 'expense')
    group by 1, 2, 3
  )
  select * from x where amount <> 0
  union all
  select 'Net profit', null, 'Net profit (income − expenses)',
         coalesce(sum(case when section = 'Income' then amount else -amount end), 0) from x
  order by 1 desc, 2, 3
$$;

-- Balance sheet as on a date; profit to date is shown under capital & reserves.
create function public.balance_sheet(p_company uuid default null, p_as_of date default current_date)
returns table (side text, ledger_group text, ledger_name text, amount numeric)
language sql stable security definer set search_path = public as $$
  with x as (
    select nature, ledger_group, name, sum(debit - credit) as bal
    from public.fin_lines(p_company, null, p_as_of) group by 1, 2, 3
  )
  select 'Assets', ledger_group, name, bal from x where nature = 'asset' and bal <> 0
  union all
  select 'Liabilities', ledger_group, name, -bal from x where nature = 'liability' and bal <> 0
  union all
  select 'Liabilities', 'reserves', 'Profit to date', coalesce(-sum(bal) filter (where nature in ('income', 'expense')), 0) from x
  order by 1, 2, 3
$$;

-- Who owes how much and for how long (oldest bills first).
create function public.ageing(p_company uuid, p_kind text default 'receivable', p_as_of date default current_date)
returns table (party_id uuid, party_name text, mobile text, total numeric, d0_30 numeric, d31_60 numeric, d61_90 numeric,
               over_90 numeric, oldest_days int)
language sql stable security definer set search_path = public as $$
  with lines as (
    select l.party_id, l.doc_date,
           case when p_kind = 'receivable' then l.debit - l.credit else l.credit - l.debit end as amt
    from public.fin_lines(p_company, null, p_as_of, false) l
    where l.party_id is not null and l.code = case when p_kind = 'receivable' then 'DEBTORS' else 'CREDITORS' end
  ),
  bal as (select party_id, sum(amt) as total from lines group by 1 having sum(amt) > 0.5),
  bills as (   -- the outstanding balance is made of the newest bills
    select l.party_id, l.doc_date, l.amt,
           sum(l.amt) over (partition by l.party_id order by l.doc_date desc rows unbounded preceding) as running
    from lines l join bal b using (party_id) where l.amt > 0
  ),
  open as (
    select b.party_id, b.doc_date, least(b.amt, greatest(bal.total - (b.running - b.amt), 0)) as open_amt
    from bills b join bal using (party_id)
  )
  select o.party_id, p.display_name, p.mobile, bal.total,
         sum(open_amt) filter (where p_as_of - doc_date <= 30),
         sum(open_amt) filter (where p_as_of - doc_date between 31 and 60),
         sum(open_amt) filter (where p_as_of - doc_date between 61 and 90),
         sum(open_amt) filter (where p_as_of - doc_date > 90),
         max(p_as_of - doc_date) filter (where open_amt > 0)
  from open o join bal using (party_id) join party p on p.id = o.party_id
  group by o.party_id, p.display_name, p.mobile, bal.total
  order by bal.total desc
$$;

create function public.party_statement(p_company uuid, p_party uuid, p_from date default current_date - 90, p_to date default current_date)
returns table (doc_date date, doc_no text, narration text, debit numeric, credit numeric, balance numeric)
language sql stable security definer set search_path = public as $$
  with opening as (
    select coalesce(sum(debit - credit), 0) as ob from public.fin_lines(p_company, null, p_from - 1, false) where party_id = p_party
  ), x as (
    select doc_date, doc_no, narration, debit, credit, journal_id from public.fin_lines(p_company, p_from, p_to, false) where party_id = p_party
  )
  select p_from, null, 'Opening balance', null, null, ob from opening
  union all
  select x.doc_date, x.doc_no, x.narration, x.debit, x.credit,
         (select ob from opening) + sum(x.debit - x.credit) over (order by x.doc_date, x.doc_no rows unbounded preceding)
  from x
  order by 1, 2 nulls first
$$;

create function public.day_book(p_company uuid, p_date date default current_date)
returns table (doc_no text, voucher_type text, narration text, ledger_name text, party_name text, debit numeric, credit numeric)
language sql stable security definer set search_path = public as $$
  select j.doc_no, j.voucher_type, j.narration, fl.name, p.display_name, l.debit, l.credit
  from finance_journal j join finance_journal_lines l on l.parent_id = j.id join finance_ledger fl on fl.id = l.ledger_id
  left join party p on p.id = l.party_id
  where j.company_id = p_company and j.doc_date = p_date and j.status = 'approved' and public.fin_can_view(p_company)
  order by j.doc_no, l.line_no
$$;

-- ---------------------------------------------------------------------------
-- Petrol bunk daily stock & sales register (DSR), per tank / product
-- ---------------------------------------------------------------------------
create function public.bunk_dsr(p_company uuid, p_location uuid, p_date date default current_date - 1)
returns table (tank text, product text, opening_dip numeric, receipts numeric, sales numeric, testing numeric, book_closing numeric,
               closing_dip numeric, variance numeric, variance_pct numeric, rate numeric, sale_value numeric)
language sql stable security definer set search_path = public as $$
  select t.name, t.product,
    (select d.dip_litres from bunk_dip d where d.tank_id = t.id and d.doc_date <= p_date order by d.doc_date desc limit 1),
    coalesce((select sum(r.received_litres) from bunk_tanker_receipt r where r.tank_id = t.id and r.doc_date = p_date and r.status <> 'cancelled'), 0),
    coalesce((select sum(rd.sale_litres) from bunk_shift_readings rd join bunk_shift s on s.id = rd.parent_id join bunk_nozzle n on n.id = rd.nozzle_id
              where n.tank_id = t.id and s.doc_date = p_date and s.status <> 'cancelled'), 0),
    coalesce((select sum(rd.testing) from bunk_shift_readings rd join bunk_shift s on s.id = rd.parent_id join bunk_nozzle n on n.id = rd.nozzle_id
              where n.tank_id = t.id and s.doc_date = p_date and s.status <> 'cancelled'), 0),
    (select d.book_litres from bunk_dip d where d.tank_id = t.id and d.doc_date = p_date + 1 order by d.created_at desc limit 1),
    (select d.dip_litres from bunk_dip d where d.tank_id = t.id and d.doc_date = p_date + 1 order by d.created_at desc limit 1),
    (select d.variance_litres from bunk_dip d where d.tank_id = t.id and d.doc_date = p_date + 1 order by d.created_at desc limit 1),
    (select round(d.variance_litres / nullif(d.book_litres, 0) * 100, 2) from bunk_dip d where d.tank_id = t.id and d.doc_date = p_date + 1
     order by d.created_at desc limit 1),
    public.bunk_rate(p_location, t.product, (p_date + time '12:00')::timestamptz),
    coalesce((select sum(rd.sale_value) from bunk_shift_readings rd join bunk_shift s on s.id = rd.parent_id join bunk_nozzle n on n.id = rd.nozzle_id
              where n.tank_id = t.id and s.doc_date = p_date and s.status <> 'cancelled'), 0)
  from bunk_tank t
  where t.location_id = p_location and t.company_id = p_company and public.user_can('bunk.dsr', 'view', p_company, p_location)
  order by t.name
$$;

-- ---------------------------------------------------------------------------
-- GST files
-- ---------------------------------------------------------------------------
create function public.gst_unit(p_uom text) returns text
language sql immutable as $$
  select case upper(coalesce(p_uom, '')) when 'M3' then 'CBM' when 'MT' then 'MTS' when 'KG' then 'KGS' when 'NOS' then 'NOS'
    when 'BAG' then 'BAG' when 'L' then 'LTR' when 'LTR' then 'LTR' when 'TON' then 'TON' else 'OTH' end
$$;

-- e-Invoice JSON (NIC schema INV-01, version 1.1) for one sales invoice, with a list of anything missing.
create function public.einvoice_json(p_invoice uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  inv finance_sales_invoice;
  co company;
  loc location;
  g company_gstin;
  p party;
  pg text;
  inter boolean;
  items jsonb;
  missing text[] := '{}';
begin
  select * into inv from finance_sales_invoice where id = p_invoice;
  if not found or not public.user_can('finance.gst.e_invoice', 'view', inv.company_id, inv.location_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into co from company where id = inv.company_id;
  select * into loc from location where id = inv.location_id;
  select * into g from company_gstin where id = loc.gstin_id;
  select * into p from party where id = inv.party_id;
  pg := coalesce(inv.billing_gstin, (select gstin from party_gstin where party_id = p.id limit 1));
  inter := left(coalesce(g.gstin, '00'), 2) <> inv.place_of_supply;
  if g.gstin is null then missing := array_append(missing, 'our GSTIN for this location'); end if;
  if pg is null then missing := array_append(missing, 'customer GSTIN (B2B e-invoice needs it)'); end if;
  if loc.address is null then missing := array_append(missing, 'our address'); end if;

  select jsonb_agg(jsonb_build_object(
    'SlNo', l.line_no::text, 'PrdDesc', coalesce(l.description, i.name), 'IsServc', case when i.category = 'service' then 'Y' else 'N' end,
    'HsnCd', coalesce(l.hsn_sac, i.hsn_sac), 'Qty', l.qty, 'Unit', public.gst_unit(coalesce(l.uom, i.base_uom)),
    'UnitPrice', l.rate, 'TotAmt', round(l.qty * l.rate, 2), 'Discount', round(l.qty * l.rate, 2) - l.taxable_value,
    'AssAmt', l.taxable_value, 'GstRt', l.gst_rate,
    'IgstAmt', case when inter then l.gst_amount else 0 end,
    'CgstAmt', case when inter then 0 else round(l.gst_amount / 2, 2) end,
    'SgstAmt', case when inter then 0 else l.gst_amount - round(l.gst_amount / 2, 2) end,
    'TotItemVal', l.line_total) order by l.line_no)
  into items
  from finance_sales_invoice_lines l join item i on i.id = l.item_id where l.parent_id = p_invoice;

  return jsonb_build_object(
    'Version', '1.1',
    'TranDtls', jsonb_build_object('TaxSch', 'GST', 'SupTyp', 'B2B', 'RegRev', case when inv.reverse_charge then 'Y' else 'N' end, 'IgstOnIntra', 'N'),
    'DocDtls', jsonb_build_object('Typ', 'INV', 'No', inv.doc_no, 'Dt', to_char(inv.doc_date, 'DD/MM/YYYY')),
    'SellerDtls', jsonb_build_object('Gstin', g.gstin, 'LglNm', co.legal_name, 'TrdNm', co.trade_name, 'Addr1', coalesce(loc.address, loc.name),
                                     'Loc', loc.name, 'Pin', null, 'Stcd', left(g.gstin, 2)),
    'BuyerDtls', jsonb_build_object('Gstin', pg, 'LglNm', coalesce(p.legal_name, p.display_name), 'Pos', inv.place_of_supply,
                                    'Addr1', coalesce(inv.shipping_address, (select address from party_address where party_id = p.id and kind = 'billing' limit 1), '-'),
                                    'Loc', '-', 'Pin', (select pincode from party_address where party_id = p.id and kind = 'billing' limit 1),
                                    'Stcd', left(coalesce(pg, inv.place_of_supply), 2)),
    'ItemList', coalesce(items, '[]'),
    'ValDtls', jsonb_build_object('AssVal', inv.taxable_value,
                                  'CgstVal', case when inter then 0 else round(inv.gst_amount / 2, 2) end,
                                  'SgstVal', case when inter then 0 else inv.gst_amount - round(inv.gst_amount / 2, 2) end,
                                  'IgstVal', case when inter then inv.gst_amount else 0 end,
                                  'RndOffAmt', inv.round_off, 'TotInvVal', inv.grand_total),
    '_missing', to_jsonb(missing));
end;
$$;

-- e-Way bill JSON (NIC bulk generation format) for one sales invoice.
create function public.ewaybill_json(p_invoice uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  e jsonb := public.einvoice_json(p_invoice);
  inv finance_sales_invoice;
begin
  select * into inv from finance_sales_invoice where id = p_invoice;
  return jsonb_build_object('version', '1.0.0621', 'billLists', jsonb_build_array(jsonb_build_object(
    'userGstin', e #>> '{SellerDtls,Gstin}', 'supplyType', 'O', 'subSupplyType', 1, 'docType', 'INV',
    'docNo', inv.doc_no, 'docDate', to_char(inv.doc_date, 'DD/MM/YYYY'),
    'fromGstin', e #>> '{SellerDtls,Gstin}', 'fromTrdName', e #>> '{SellerDtls,LglNm}', 'fromAddr1', e #>> '{SellerDtls,Addr1}',
    'fromPlace', e #>> '{SellerDtls,Loc}', 'fromStateCode', (e #>> '{SellerDtls,Stcd}')::int, 'actualFromStateCode', (e #>> '{SellerDtls,Stcd}')::int,
    'toGstin', coalesce(e #>> '{BuyerDtls,Gstin}', 'URP'), 'toTrdName', e #>> '{BuyerDtls,LglNm}', 'toAddr1', e #>> '{BuyerDtls,Addr1}',
    'toStateCode', inv.place_of_supply::int, 'actualToStateCode', inv.place_of_supply::int,
    'totalValue', inv.taxable_value, 'cgstValue', (e #>> '{ValDtls,CgstVal}')::numeric, 'sgstValue', (e #>> '{ValDtls,SgstVal}')::numeric,
    'igstValue', (e #>> '{ValDtls,IgstVal}')::numeric, 'totInvValue', inv.grand_total,
    'transMode', 1, 'transDistance', coalesce(inv.distance_km, 0), 'vehicleNo', inv.vehicle_no, 'vehicleType', 'R',
    'itemList', (select jsonb_agg(jsonb_build_object('itemNo', (i ->> 'SlNo')::int, 'productName', i ->> 'PrdDesc', 'hsnCode', (i ->> 'HsnCd')::bigint,
                   'quantity', (i ->> 'Qty')::numeric, 'qtyUnit', i ->> 'Unit', 'taxableAmount', (i ->> 'AssAmt')::numeric,
                   'cgstRate', case when (i ->> 'CgstAmt')::numeric > 0 then (i ->> 'GstRt')::numeric / 2 else 0 end,
                   'sgstRate', case when (i ->> 'SgstAmt')::numeric > 0 then (i ->> 'GstRt')::numeric / 2 else 0 end,
                   'igstRate', case when (i ->> 'IgstAmt')::numeric > 0 then (i ->> 'GstRt')::numeric else 0 end))
                 from jsonb_array_elements(e -> 'ItemList') i))),
    '_missing', e -> '_missing' || case when inv.vehicle_no is null then '["vehicle number"]'::jsonb else '[]'::jsonb end);
end;
$$;

-- GSTR-1 JSON for one GSTIN and month (B2B, B2C small, HSN summary), as the GST offline tool takes it.
create function public.gstr1_json(p_gstin uuid, p_month text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  g company_gstin;
  v_from date := to_date(p_month || '-01', 'YYYY-MM-DD');
  v_to date := (to_date(p_month || '-01', 'YYYY-MM-DD') + interval '1 month - 1 day')::date;
  b2b jsonb; b2cs jsonb; hsn jsonb;
begin
  select * into g from company_gstin where id = p_gstin;
  if not public.user_can('finance.gst.gstr1', 'view', g.company_id, null) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  with inv as (
    select i.*, coalesce(i.billing_gstin, (select pg.gstin from party_gstin pg where pg.party_id = i.party_id limit 1)) as ctin
    from finance_sales_invoice i join location l on l.id = i.location_id
    where l.gstin_id = p_gstin and i.status = 'approved' and i.doc_date between v_from and v_to
  ),
  lines as (
    select inv.*, l.gst_rate, l.taxable_value as txval, l.gst_amount as tax, l.hsn_sac, l.qty, l.uom, left(g.gstin, 2) <> inv.place_of_supply as inter
    from inv join finance_sales_invoice_lines l on l.parent_id = inv.id
  )
  select
    (select jsonb_agg(jsonb_build_object('ctin', ctin, 'inv', invs)) from (
       select ctin, jsonb_agg(jsonb_build_object('inum', doc_no, 'idt', to_char(doc_date, 'DD-MM-YYYY'), 'val', grand_total, 'pos', place_of_supply,
              'rchrg', case when reverse_charge then 'Y' else 'N' end, 'inv_typ', 'R',
              'itms', (select jsonb_agg(jsonb_build_object('num', rn, 'itm_det', jsonb_build_object('rt', gst_rate, 'txval', txval,
                         'iamt', case when inter then tax else 0 end, 'camt', case when inter then 0 else round(tax / 2, 2) end,
                         'samt', case when inter then 0 else tax - round(tax / 2, 2) end, 'csamt', 0)))
                       from (select gst_rate, sum(txval) txval, sum(tax) tax, bool_or(inter) inter, row_number() over () rn
                             from lines x where x.id = inv.id group by gst_rate) r))) as invs
       from inv where ctin is not null group by ctin) b),
    (select jsonb_agg(jsonb_build_object('sply_ty', case when inter then 'INTER' else 'INTRA' end, 'pos', place_of_supply, 'typ', 'OE', 'rt', gst_rate,
            'txval', txval, 'iamt', case when inter then tax else 0 end, 'camt', case when inter then 0 else round(tax / 2, 2) end,
            'samt', case when inter then 0 else tax - round(tax / 2, 2) end, 'csamt', 0))
     from (select place_of_supply, gst_rate, inter, sum(txval) txval, sum(tax) tax from lines where ctin is null group by 1, 2, 3) s),
    (select jsonb_agg(jsonb_build_object('num', rn, 'hsn_sc', hsn_sac, 'uqc', public.gst_unit(uom), 'qty', qty, 'rt', gst_rate, 'txval', txval,
            'iamt', iamt, 'camt', camt, 'samt', samt, 'csamt', 0))
     from (select hsn_sac, uom, gst_rate, sum(qty) qty, sum(txval) txval, sum(case when inter then tax else 0 end) iamt,
                  sum(case when inter then 0 else round(tax / 2, 2) end) camt, sum(case when inter then 0 else tax - round(tax / 2, 2) end) samt,
                  row_number() over () rn
           from lines group by 1, 2, 3) h)
  into b2b, b2cs, hsn
  from (select 1) one;
  return jsonb_build_object('gstin', g.gstin, 'fp', to_char(v_from, 'MMYYYY'), 'version', 'GST3.1.6', 'hash', 'hash',
                            'b2b', coalesce(b2b, '[]'), 'b2cs', coalesce(b2cs, '[]'), 'hsn', jsonb_build_object('data', coalesce(hsn, '[]')));
end;
$$;

-- ---------------------------------------------------------------------------
-- Period lock: after GST filing nobody but an admin can add or change entries dated on or before the lock date.
-- ---------------------------------------------------------------------------
create table public.period_lock (
  company_id  uuid primary key references public.company on delete cascade,
  tenant_id   uuid not null references public.tenant,
  locked_upto date not null,
  reason      text,
  locked_by   uuid default auth.uid(),
  locked_at   timestamptz not null default now()
);
alter table public.period_lock enable row level security;
create policy period_lock_read on public.period_lock for select using (company_id in (select public.my_company_ids()));
create policy period_lock_write on public.period_lock for all using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));
select audit.track('public.period_lock');

create function public.period_lock_check() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_lock date;
  v_date date;
begin
  v_date := case when tg_op = 'DELETE' then old.doc_date else new.doc_date end;
  select locked_upto into v_lock from period_lock where company_id = coalesce(new.company_id, old.company_id);
  if v_lock is not null and (v_date <= v_lock or (tg_op = 'UPDATE' and old.doc_date <= v_lock))
     and auth.uid() is not null and not public.is_tenant_admin() then
    raise exception 'Entries up to % are locked (GST filed). Ask the admin.', to_char(v_lock, 'DD Mon YYYY');
  end if;
  return coalesce(new, old);
end;
$$;

do $$
declare
  e record;
begin
  for e in select table_name from erp_entity where parent_key is null and dated loop
    execute format('create trigger aa_period_lock before insert or update or delete on public.%I
                    for each row execute function public.period_lock_check()', e.table_name);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Owner's daily summary, ready to send on WhatsApp
-- ---------------------------------------------------------------------------
create function public.owner_summary_text(p_date date default current_date - 1) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  r record;
  v text;
  v_sales numeric := 0; v_today numeric := 0; v_recv numeric := 0; v_cash numeric := 0; v_diesel numeric := 0; v_rmc numeric := 0;
  v_fuel numeric := 0; v_alerts int := 0; v_pending int := 0;
  fmt text;
begin
  for r in select * from public.owner_dashboard(p_date, p_date) loop
    v_today := v_today + r.sales - r.intercompany_sales; v_recv := v_recv + r.receivables; v_cash := v_cash + r.cash_bank;
    v_diesel := v_diesel + r.diesel_litres; v_rmc := v_rmc + r.rmc_m3; v_fuel := v_fuel + r.fuel_litres_sold;
    v_alerts := v_alerts + r.alerts; v_pending := v_pending + r.pending_approvals;
  end loop;
  select coalesce(sum(sales - intercompany_sales), 0) into v_sales from public.owner_dashboard(date_trunc('month', p_date)::date, p_date);
  v := format(E'*%s — %s*\n', (select name from tenant where id = public.auth_tenant_id()), to_char(p_date, 'DD Mon'))
    || format(E'Sales: %s (month %s)\n', public.inr_short(v_today), public.inr_short(v_sales))
    || format(E'Cash & bank: %s\n', public.inr_short(v_cash))
    || format(E'To collect: %s\n', public.inr_short(v_recv))
    || case when v_rmc > 0 then format(E'RMC: %s m³\n', trim_scale(v_rmc)) else '' end
    || case when v_fuel > 0 then format(E'Fuel sold: %s L\n', trim_scale(v_fuel)) else '' end
    || case when v_diesel > 0 then format(E'Diesel used: %s L\n', trim_scale(v_diesel)) else '' end
    || format(E'⚠ %s alerts · %s waiting for approval', v_alerts, v_pending);
  return v;
end;
$$;

create function public.inr_short(p numeric) returns text
language sql immutable as $$
  select case when abs(p) >= 1e7 then '₹' || trim_scale(round(p / 1e7, 2)) || ' Cr'
              when abs(p) >= 1e5 then '₹' || trim_scale(round(p / 1e5, 1)) || ' L'
              else '₹' || trim_scale(round(p)) end
$$;
