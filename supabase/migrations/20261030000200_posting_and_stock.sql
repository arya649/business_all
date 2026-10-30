-- Posting engine (every module document → double-entry journal) and stock ledger.
--
-- Posting rules come from config/modules (erp_entity.posting) and can be overridden per tenant or company in
-- posting_rule. A rule line is {side: Dr|Cr, ledger, amount} where
--   ledger = a ledger code (SALES, GST_OUTPUT...), "@party" (the party's debtors/creditors account),
--            or "$field|CODE" (a ledger id held in a field of the document, else CODE)
--   amount = a field of the document; a negative amount posts on the other side
--   child  = optional line table name: one journal line per document line (e.g. credit sales per customer)
-- Journals are re-derived whenever the document changes: if the amounts differ from what was posted,
-- the old journal is reversed and a new one posted. Nothing is ever deleted from the books.
-- When the party is a group company the journal is tagged inter-company and the mirror entry is
-- posted in the other company's books, so group reports can eliminate both.

-- ---------------------------------------------------------------------------
-- Ledgers created on first use
-- ---------------------------------------------------------------------------

create table public.fin_default_ledger (
  code   text primary key,
  name   text not null,
  ledger_group text not null,
  nature text not null
);

insert into public.fin_default_ledger values
  ('CASH', 'Cash', 'cash', 'asset'),
  ('PETTY_CASH', 'Petty cash', 'cash', 'asset'),
  ('BANK', 'Bank', 'bank', 'asset'),
  ('BANK_POS', 'UPI / card collections', 'bank', 'asset'),
  ('FLEET_CARDS', 'Fleet card receivable', 'current_assets', 'asset'),
  ('DEBTORS', 'Sundry debtors', 'sundry_debtors', 'asset'),
  ('CREDITORS', 'Sundry creditors', 'sundry_creditors', 'liability'),
  ('SALES', 'Sales', 'sales', 'income'),
  ('FUEL_SALES', 'Fuel sales', 'sales', 'income'),
  ('CONTRACT_REVENUE', 'Contract revenue', 'sales', 'income'),
  ('PURCHASES', 'Purchases', 'purchases', 'expense'),
  ('GST_OUTPUT', 'GST output', 'duties_taxes', 'liability'),
  ('GST_INPUT', 'GST input credit', 'duties_taxes', 'asset'),
  ('TDS_PAYABLE', 'TDS payable', 'duties_taxes', 'liability'),
  ('TCS_PAYABLE', 'TCS payable', 'duties_taxes', 'liability'),
  ('TDS_RECEIVABLE', 'TDS receivable', 'loans_advances_asset', 'asset'),
  ('GST_TDS_RECEIVABLE', 'GST TDS receivable', 'loans_advances_asset', 'asset'),
  ('ROUND_OFF', 'Round off', 'indirect_expenses', 'expense'),
  ('EXPENSES', 'Site & plant expenses', 'direct_expenses', 'expense'),
  ('CASH_SHORT_EXCESS', 'Cash short / excess', 'indirect_expenses', 'expense'),
  ('RETENTION_RECEIVABLE', 'Retention money receivable', 'loans_advances_asset', 'asset'),
  ('RETENTION_PAYABLE', 'Retention money payable', 'current_liabilities', 'liability'),
  ('SECURITY_DEPOSIT_RECEIVABLE', 'Security deposits with clients', 'loans_advances_asset', 'asset'),
  ('MOBILISATION_ADVANCE', 'Mobilisation advance from clients', 'current_liabilities', 'liability'),
  ('LABOUR_CESS', 'Labour cess', 'direct_expenses', 'expense'),
  ('MATERIAL_RECOVERY', 'Material recoveries', 'direct_expenses', 'expense'),
  ('OTHER_DEDUCTIONS', 'Other bill deductions', 'direct_expenses', 'expense'),
  ('SUBCONTRACT_EXPENSE', 'Sub-contract work', 'direct_expenses', 'expense'),
  ('ADVANCE_TO_SUPPLIERS', 'Advances to suppliers / sub-contractors', 'loans_advances_asset', 'asset'),
  ('STAFF_ADVANCES', 'Staff advances', 'loans_advances_asset', 'asset'),
  ('SALARIES', 'Salaries and wages', 'direct_expenses', 'expense'),
  ('EMPLOYER_PF_ESI', 'Employer PF / ESI', 'direct_expenses', 'expense'),
  ('PF_PAYABLE', 'PF payable', 'duties_taxes', 'liability'),
  ('ESI_PAYABLE', 'ESI payable', 'duties_taxes', 'liability'),
  ('PT_PAYABLE', 'Professional tax payable', 'duties_taxes', 'liability'),
  ('SALARY_PAYABLE', 'Salary payable', 'current_liabilities', 'liability'),
  ('INTERCO_SUSPENSE', 'Inter-company suspense', 'current_liabilities', 'liability');

-- In a mirror (inter-company) entry, the other company books the opposite account.
create table public.fin_mirror_code (
  code text primary key,
  mirror_code text not null
);
insert into public.fin_mirror_code values
  ('SALES', 'PURCHASES'), ('FUEL_SALES', 'PURCHASES'), ('CONTRACT_REVENUE', 'SUBCONTRACT_EXPENSE'),
  ('GST_OUTPUT', 'GST_INPUT'), ('GST_INPUT', 'GST_OUTPUT'), ('PURCHASES', 'SALES'),
  ('TCS_PAYABLE', 'TDS_RECEIVABLE'), ('TDS_PAYABLE', 'TDS_RECEIVABLE'), ('TDS_RECEIVABLE', 'TDS_PAYABLE'),
  ('RETENTION_RECEIVABLE', 'RETENTION_PAYABLE'), ('RETENTION_PAYABLE', 'RETENTION_RECEIVABLE');

create function public.fin_ledger(p_company uuid, p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  d    fin_default_ledger;
begin
  select id into v_id from finance_ledger where company_id = p_company and code = p_code;
  if v_id is not null then
    return v_id;
  end if;
  select * into d from fin_default_ledger where code = p_code;
  insert into finance_ledger (tenant_id, company_id, name, code, ledger_group, nature, is_bank)
  select c.tenant_id, c.id, coalesce(d.name, initcap(replace(p_code, '_', ' '))), p_code,
         coalesce(d.ledger_group, 'indirect_expenses'), coalesce(d.nature, 'expense'), coalesce(d.ledger_group = 'bank', false)
  from company c where c.id = p_company
  on conflict (company_id, code) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from finance_ledger where company_id = p_company and code = p_code;
  end if;
  return v_id;
end;
$$;

-- Admin override of a module's default posting.
create table public.posting_rule (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenant on delete cascade,
  company_id uuid references public.company on delete cascade,
  entity_key text not null references public.erp_entity,
  rule       jsonb not null,
  is_active  boolean not null default true,
  unique nulls not distinct (tenant_id, company_id, entity_key)
);
alter table public.posting_rule enable row level security;
create policy posting_rule_read on public.posting_rule for select using (tenant_id = public.auth_tenant_id());
create policy posting_rule_write on public.posting_rule for all
  using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));
select audit.track('public.posting_rule');

alter table public.finance_journal add column posting_hash text;
create index on public.finance_journal (source_entity, source_id);

-- Numbering without a permission check, for documents the system writes on someone's behalf.
create function public.doc_number_internal(p_company uuid, p_location uuid, p_doc_type text, p_date date)
returns text
language plpgsql security definer set search_path = public as $$
declare
  s   number_series;
  e   erp_entity;
begin
  select * into e from erp_entity where key = p_doc_type;
  if found then
    perform public.erp_ensure_series(e, p_company);
  end if;
  s := public.get_series(p_company, p_location, p_doc_type, p_date);
  update number_series set next_value = next_value + 1 where id = s.id;
  return public.format_doc_number(s.pattern, (select short_code from company where id = p_company),
                                  (select short_code from location where id = p_location), s.fy, s.next_value);
end;
$$;
revoke execute on function public.doc_number_internal(uuid, uuid, text, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Building journal lines from a rule
-- ---------------------------------------------------------------------------

create function public.fin_party_of(p_entity text, p_rule jsonb, p_row jsonb) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare
  v_field text := p_rule ->> 'party';
begin
  if v_field is null then
    return null;
  elsif v_field = '$client' then
    return (select client_id from infra_project where id = (p_row ->> 'project_id')::uuid);
  else
    return (p_row ->> v_field)::uuid;
  end if;
end;
$$;

-- Returns [{ledger_id, party_id, debit, credit, code}] for the document, or [] if nothing to post.
create function public.fin_build_lines(p_entity text, p_row jsonb, p_company uuid, p_rule jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  l        jsonb;
  v_lines  jsonb := '[]';
  v_party  uuid := public.fin_party_of(p_entity, p_rule, p_row);
  v_amt    numeric;
  v_lparty uuid;
  v_voucher text := p_rule ->> 'voucher';
  c        erp_entity;
  r        jsonb;
begin
  for l in select * from jsonb_array_elements(p_rule -> 'lines') loop
    if l ? 'child' then
      select * into c from erp_entity where parent_key = p_entity and child_name = l ->> 'child';
      for r in execute format('select to_jsonb(t) from public.%I t where t.parent_id = $1 order by line_no', c.table_name)
               using (p_row ->> 'id')::uuid loop
        v_amt := coalesce((r ->> (l ->> 'amount'))::numeric, 0);
        v_lparty := coalesce((r ->> coalesce(l ->> 'party_field', 'party_id'))::uuid, v_party);
        v_lines := v_lines || public.fin_line(p_company, l ->> 'side', l ->> 'ledger', v_amt, v_lparty, v_voucher, p_row);
      end loop;
    else
      v_amt := coalesce((p_row ->> (l ->> 'amount'))::numeric, 0);
      v_lines := v_lines || public.fin_line(p_company, l ->> 'side', l ->> 'ledger', v_amt, v_party, v_voucher, p_row);
    end if;
  end loop;
  return v_lines;
end;
$$;

create function public.fin_line(p_company uuid, p_side text, p_ledger text, p_amount numeric, p_party uuid,
                                p_voucher text, p_row jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_code   text;
  v_ledger uuid;
  v_side   text := p_side;
  v_amt    numeric := round(coalesce(p_amount, 0), 2);
  v_party  uuid;
begin
  if v_amt = 0 then
    return '[]';
  end if;
  if v_amt < 0 then
    v_amt := -v_amt;
    v_side := case v_side when 'Dr' then 'Cr' else 'Dr' end;
  end if;

  if p_ledger = '@party' then
    if p_party is null then
      raise exception 'Posting needs a party but the document has none.';
    end if;
    v_code := case when p_voucher in ('sales', 'receipt') then 'DEBTORS' else 'CREDITORS' end;
    v_party := p_party;
  elsif p_ledger like '$%' then
    v_ledger := (p_row ->> split_part(substr(p_ledger, 2), '|', 1))::uuid;
    v_code := nullif(split_part(p_ledger, '|', 2), '');
  else
    v_code := p_ledger;
  end if;
  if v_ledger is null then
    v_ledger := public.fin_ledger(p_company, v_code);
  else
    v_code := (select code from finance_ledger where id = v_ledger);
  end if;

  return jsonb_build_array(jsonb_build_object(
    'ledger_id', v_ledger, 'code', v_code, 'party_id', v_party,
    'debit', case when v_side = 'Dr' then v_amt else 0 end,
    'credit', case when v_side = 'Cr' then v_amt else 0 end));
end;
$$;

-- Write one journal (already balanced) and its lines; returns the journal id.
create function public.fin_write_journal(
  p_company uuid, p_location uuid, p_date date, p_voucher text, p_narration text, p_entity text, p_source uuid,
  p_source_no text, p_lines jsonb, p_hash text, p_reversal boolean, p_ic boolean, p_counterparty uuid, p_ic_ref text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := gen_random_uuid();
  v_tenant uuid := (select tenant_id from company where id = p_company);
  l jsonb;
  n int := 0;
begin
  insert into finance_journal (id, tenant_id, company_id, location_id, doc_no, doc_date, status, approved_at, voucher_type,
                               narration, source_entity, source_id, source_doc_no, is_intercompany, counterparty_company_id,
                               ic_reference, is_reversal, posting_hash)
  values (v_id, v_tenant, p_company, p_location,
          public.doc_number_internal(p_company, null, 'finance.journal', p_date), p_date, 'draft', null,
          p_voucher, p_narration, p_entity, p_source::text, p_source_no, p_ic, p_counterparty, p_ic_ref, p_reversal, p_hash);
  for l in select * from jsonb_array_elements(p_lines) loop
    n := n + 1;
    insert into finance_journal_lines (tenant_id, parent_id, line_no, ledger_id, party_id, debit, credit, cost_location_id)
    values (v_tenant, v_id, n, (l ->> 'ledger_id')::uuid, (l ->> 'party_id')::uuid,
            (l ->> 'debit')::numeric, (l ->> 'credit')::numeric, p_location);
  end loop;
  -- totals roll up from the lines as it is approved
  update finance_journal set status = 'approved', approved_at = now() where id = v_id;
  return v_id;
end;
$$;

-- Lines for the other group company's books.
create function public.fin_mirror_lines(p_lines jsonb, p_from_company uuid, p_to_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  l jsonb;
  v_out jsonb := '[]';
  v_code text;
  v_party uuid;
begin
  -- the selling company appears as a party in the buyer's books
  select id into v_party from party where group_company_id = p_from_company
    and tenant_id = (select tenant_id from company where id = p_to_company) limit 1;
  if v_party is null then
    raise exception 'Create a party for group company % so inter-company entries can be mirrored.',
      (select legal_name from company where id = p_from_company);
  end if;
  for l in select * from jsonb_array_elements(p_lines) loop
    if l ->> 'code' in ('DEBTORS', 'CREDITORS') then
      v_code := case l ->> 'code' when 'DEBTORS' then 'CREDITORS' else 'DEBTORS' end;
      v_out := v_out || jsonb_build_object('ledger_id', public.fin_ledger(p_to_company, v_code), 'code', v_code,
                                           'party_id', v_party, 'debit', l -> 'credit', 'credit', l -> 'debit');
    else
      v_code := coalesce((select mirror_code from fin_mirror_code where code = l ->> 'code'), 'INTERCO_SUSPENSE');
      v_out := v_out || jsonb_build_object('ledger_id', public.fin_ledger(p_to_company, v_code), 'code', v_code,
                                           'party_id', null, 'debit', l -> 'credit', 'credit', l -> 'debit');
    end if;
  end loop;
  return v_out;
end;
$$;

-- ---------------------------------------------------------------------------
-- Post / re-post / reverse one document
-- ---------------------------------------------------------------------------

create function public.fin_post_document(p_entity text, p_id uuid) returns void
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

  select pr.rule into v_rule from posting_rule pr
  where pr.entity_key = p_entity and pr.is_active and pr.tenant_id = (v_row ->> 'tenant_id')::uuid
    and (pr.company_id is null or pr.company_id = v_co)
  order by pr.company_id nulls last limit 1;
  v_rule := coalesce(v_rule, e.posting);
  if v_rule is null then return; end if;

  v_should := case when e.workflow then v_row ->> 'status' = 'approved' else true end;
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

  -- current active journal(s) for this document in this company (not reversed, not reversals)
  for j in select fj.id, fj.posting_hash from finance_journal fj
           where fj.source_entity = p_entity and fj.source_id = p_id::text and fj.company_id = v_co
             and not fj.is_reversal and fj.status = 'approved'
             and not exists (select 1 from finance_journal r where r.source_entity = 'finance.journal'
                             and r.source_id = fj.id::text and r.is_reversal) loop
    if j.posting_hash is not distinct from v_hash then
      return;                                     -- already posted exactly this
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

create function public.fin_reverse_journal(p_journal uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  j finance_journal;
  v_lines jsonb;
begin
  select * into j from finance_journal where id = p_journal;
  select jsonb_agg(jsonb_build_object('ledger_id', l.ledger_id, 'party_id', l.party_id, 'debit', l.credit, 'credit', l.debit))
    into v_lines from finance_journal_lines l where l.parent_id = p_journal;
  perform public.fin_write_journal(j.company_id, j.location_id, current_date, j.voucher_type,
    'Reversal of ' || j.doc_no || coalesce(' (' || j.source_doc_no || ')', ''), 'finance.journal', j.id, j.doc_no,
    v_lines, null, true, j.is_intercompany, j.counterparty_company_id, j.ic_reference);
  -- mirror journal in the other company, if any
  for j in select * from finance_journal m where m.source_entity = j.source_entity and m.source_id = j.source_id
           and m.company_id = j.counterparty_company_id and m.posting_hash = j.posting_hash and not m.is_reversal
           and not exists (select 1 from finance_journal r where r.source_entity = 'finance.journal' and r.source_id = m.id::text) loop
    select jsonb_agg(jsonb_build_object('ledger_id', l.ledger_id, 'party_id', l.party_id, 'debit', l.credit, 'credit', l.debit))
      into v_lines from finance_journal_lines l where l.parent_id = j.id;
    perform public.fin_write_journal(j.company_id, j.location_id, current_date, j.voucher_type,
      'Reversal of ' || j.doc_no, 'finance.journal', j.id, j.doc_no, v_lines, null, true, true,
      j.counterparty_company_id, j.ic_reference);
  end loop;
end;
$$;

-- Manual journals must balance before they are approved.
create function public.fin_check_manual_journal() returns trigger
language plpgsql as $$
begin
  if new.status = 'approved' and new.source_entity is null and new.total_debit <> new.total_credit then
    raise exception 'Journal does not balance: debit % vs credit %', new.total_debit, new.total_credit;
  end if;
  return new;
end;
$$;
create trigger fin_balance before update on public.finance_journal
  for each row when (new.status = 'approved') execute function public.fin_check_manual_journal();

-- Books are append-only once posted.
create function public.fin_lock_posted() returns trigger
language plpgsql as $$
begin
  if old.status = 'approved' and old.source_entity is not null then
    if tg_op = 'DELETE' or new.total_debit <> old.total_debit or new.total_credit <> old.total_credit
       or new.status <> old.status then
      raise exception 'Posted journals cannot be changed; reverse them instead.';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;
create trigger fin_lock before update or delete on public.finance_journal
  for each row execute function public.fin_lock_posted();

-- ---------------------------------------------------------------------------
-- Stock ledger
-- ---------------------------------------------------------------------------

create table public.stock_move (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenant,
  company_id    uuid not null references public.company,
  location_id   uuid not null references public.location,
  item_id       uuid not null references public.item,
  qty           numeric(16, 3) not null,          -- + in, − out
  rate          numeric(14, 4),
  value         numeric(16, 2) generated always as (round(qty * coalesce(rate, 0), 2)) stored,
  doc_date      date not null,
  source_entity text not null,
  source_id     uuid not null,
  source_doc_no text,
  created_at    timestamptz not null default now()
);
create index on public.stock_move (company_id, location_id, item_id);
create index on public.stock_move (source_entity, source_id);
alter table public.stock_move enable row level security;
create policy stock_move_read on public.stock_move for select
  using (public.user_can('purchase.stock', 'view', company_id, location_id));

create function public.stock_apply_document(p_entity text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  e      erp_entity := public.erp_entity_row(p_entity);
  c      erp_entity;
  v_row  jsonb;
  r      jsonb;
  ln     jsonb;
  v_ok   boolean;
  v_loc  uuid;
  v_qty  numeric;
begin
  delete from stock_move where source_entity = p_entity and source_id = p_id;
  if e.stock_rules is null then return; end if;
  execute format('select to_jsonb(t) from public.%I t where t.id = $1', e.table_name) using p_id into v_row;
  if v_row is null or v_row ->> 'status' = 'cancelled' then return; end if;

  for r in select * from jsonb_array_elements(e.stock_rules) loop
    v_ok := case coalesce(r ->> 'when', 'saved')
              when 'approved' then v_row ->> 'status' = 'approved'
              else coalesce(v_row ->> 'status', 'approved') not in ('rejected', 'cancelled') end;
    continue when not v_ok;
    v_loc := coalesce((v_row ->> coalesce(r ->> 'location', 'location_id'))::uuid, (v_row ->> 'location_id')::uuid);
    select * into c from erp_entity where parent_key = p_entity and child_name = r ->> 'child';
    for ln in execute format('select to_jsonb(t) from public.%I t where t.parent_id = $1', c.table_name) using p_id loop
      v_qty := coalesce((ln ->> (r ->> 'qty'))::numeric, 0);
      continue when v_qty = 0 or ln ->> (r ->> 'item') is null;
      insert into stock_move (tenant_id, company_id, location_id, item_id, qty, rate, doc_date, source_entity, source_id, source_doc_no)
      values ((v_row ->> 'tenant_id')::uuid,
              coalesce((select company_id from location where id = v_loc), (v_row ->> 'company_id')::uuid),
              v_loc, (ln ->> (r ->> 'item'))::uuid,
              case r ->> 'dir' when 'in' then abs(v_qty) when 'out' then -abs(v_qty) else v_qty end,
              (ln ->> (r ->> 'rate'))::numeric,
              coalesce((v_row ->> 'doc_date')::date, current_date), p_entity, p_id, v_row ->> 'doc_no');
    end loop;
  end loop;
end;
$$;

-- Stock on hand for the app.
create function public.stock_on_hand(p_company uuid, p_location uuid default null, p_item uuid default null)
returns table (location_id uuid, location_name text, item_id uuid, item_name text, uom text, qty numeric, value numeric,
               reorder_level numeric, below_reorder boolean)
language sql stable security definer set search_path = public as $$
  select m.location_id, l.name, m.item_id, i.name, i.base_uom, sum(m.qty), sum(m.value), il.reorder_level,
         coalesce(sum(m.qty) < il.reorder_level, false)
  from stock_move m
  join location l on l.id = m.location_id
  join item i on i.id = m.item_id
  left join item_location il on il.item_id = m.item_id and il.location_id = m.location_id
  where m.company_id = p_company
    and (p_location is null or m.location_id = p_location)
    and (p_item is null or m.item_id = p_item)
    and public.user_can('purchase.stock', 'view', m.company_id, m.location_id)
  group by m.location_id, l.name, m.item_id, i.name, i.base_uom, il.reorder_level
  order by l.name, i.name
$$;

-- ---------------------------------------------------------------------------
-- One trigger for every module table: post to the books and to stock after each change.
-- Runs after the statement's row is final (including rollups from lines).
-- ---------------------------------------------------------------------------

create function public.erp_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_key text := tg_argv[0];
begin
  if tg_op = 'DELETE' then
    delete from stock_move where source_entity = v_key and source_id = old.id;
    return null;
  end if;
  perform public.stock_apply_document(v_key, new.id);
  perform public.fin_post_document(v_key, new.id);
  return null;
end;
$$;

-- Installs the trigger on every module table that posts or moves stock. Run again whenever rules change.
create function public.erp_install_post_triggers() returns void
language plpgsql as $$
declare
  e record;
begin
  for e in select key, table_name, (posting is not null or stock_rules is not null) as needed
           from erp_entity where parent_key is null loop
    execute format('drop trigger if exists zz_post on public.%I', e.table_name);
    if e.needed then
      execute format('create trigger zz_post after insert or update or delete on public.%I
                      for each row execute function public.erp_after_change(%L)', e.table_name, e.key);
    end if;
  end loop;
end;
$$;
select public.erp_install_post_triggers();

-- Party outstanding in one company's books (Dr − Cr across debtors/creditors).
create function public.party_balance(p_company uuid, p_party uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.debit - l.credit), 0)
  from finance_journal_lines l join finance_journal j on j.id = l.parent_id
  where j.company_id = p_company and l.party_id = p_party and j.status = 'approved'
$$;

-- Trial balance (company or whole group with inter-company eliminated).
create function public.trial_balance(p_company uuid default null, p_from date default null, p_to date default null,
                                     p_eliminate_intercompany boolean default true)
returns table (company_code text, ledger_code text, ledger_name text, ledger_group text, debit numeric, credit numeric, balance numeric)
language sql stable security definer set search_path = public as $$
  select c.short_code, fl.code, fl.name, fl.ledger_group, sum(l.debit), sum(l.credit), sum(l.debit - l.credit)
  from finance_journal j
  join finance_journal_lines l on l.parent_id = j.id
  join finance_ledger fl on fl.id = l.ledger_id
  join company c on c.id = j.company_id
  where j.status = 'approved'
    and (p_company is null or j.company_id = p_company)
    and j.company_id in (select public.my_company_ids())
    and public.user_can('finance.ledger', 'view', j.company_id, null)
    and (p_from is null or j.doc_date >= p_from) and (p_to is null or j.doc_date <= p_to)
    and not (p_eliminate_intercompany and p_company is null and j.is_intercompany)
  group by c.short_code, fl.code, fl.name, fl.ledger_group
  order by c.short_code, fl.ledger_group, fl.name
$$;
