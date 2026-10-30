-- Document number series, including blocks reserved by mobile devices for offline use.
--
-- Pattern tokens: {CO} company code, {LOC} location code, {FY} e.g. 26-27, {SEQ:n} zero-padded sequence.
-- GST rule: an invoice number is at most 16 characters, unique per financial year per GSTIN.

create table public.number_series (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenant,
  company_id  uuid not null references public.company on delete cascade,
  location_id uuid references public.location on delete cascade,     -- null = company-wide
  doc_type    text not null,                                          -- a feature key, e.g. rmc.delivery_challan
  pattern     text not null default '{LOC}/{FY}/{SEQ:5}',
  fy          text not null,                                          -- '26-27'
  next_value  bigint not null default 1 check (next_value > 0),
  max_length  integer not null default 16,
  unique nulls not distinct (company_id, location_id, doc_type, fy)
);

create table public.number_block (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenant,
  series_id   uuid not null references public.number_series on delete cascade,
  device_id   text not null,
  user_id     uuid not null references public.app_user default auth.uid(),
  from_value  bigint not null,
  to_value    bigint not null,
  last_used   bigint,                      -- reported back by the device on sync
  reserved_at timestamptz not null default now(),
  check (to_value >= from_value)
);
create index on public.number_block (series_id);

create function public.financial_year(p_date date, p_start_month int default 4) returns text
language sql immutable as $$
  select case when extract(month from p_date) >= p_start_month
    then to_char(p_date, 'YY') || '-' || to_char(p_date + interval '1 year', 'YY')
    else to_char(p_date - interval '1 year', 'YY') || '-' || to_char(p_date, 'YY')
  end
$$;

create function public.format_doc_number(p_pattern text, p_co text, p_loc text, p_fy text, p_seq bigint)
returns text language plpgsql immutable as $$
declare
  v text := p_pattern;
  m text[];
begin
  v := replace(replace(replace(v, '{CO}', coalesce(p_co, '')), '{LOC}', coalesce(p_loc, '')), '{FY}', p_fy);
  m := regexp_match(v, '\{SEQ:(\d+)\}');
  if m is not null then
    v := replace(v, '{SEQ:' || m[1] || '}', lpad(p_seq::text, m[1]::int, '0'));
  else
    v := replace(v, '{SEQ}', p_seq::text);
  end if;
  return v;
end;
$$;

-- Find (or create from the company-wide template) the series for a document.
create function public.get_series(p_company uuid, p_location uuid, p_doc_type text, p_date date)
returns public.number_series
language plpgsql security definer set search_path = public as $$
declare
  v_fy text;
  s    number_series;
  t    number_series;
begin
  select public.financial_year(p_date, tn.fy_start_month) into v_fy
  from company c join tenant tn on tn.id = c.tenant_id where c.id = p_company;

  select * into s from number_series
  where company_id = p_company and location_id is not distinct from p_location
    and doc_type = p_doc_type and fy = v_fy
  for update;
  if found then return s; end if;

  -- New financial year or new location: copy the latest pattern we have.
  select * into t from number_series
  where company_id = p_company and doc_type = p_doc_type
    and (location_id is not distinct from p_location or location_id is null)
  order by (location_id is not distinct from p_location) desc, fy desc limit 1;

  insert into number_series (tenant_id, company_id, location_id, doc_type, pattern, fy, max_length)
  select c.tenant_id, p_company, p_location, p_doc_type,
         coalesce(t.pattern, '{LOC}/{FY}/{SEQ:5}'), v_fy, coalesce(t.max_length, 16)
  from company c where c.id = p_company
  on conflict do nothing;

  select * into s from number_series
  where company_id = p_company and location_id is not distinct from p_location
    and doc_type = p_doc_type and fy = v_fy
  for update;
  return s;
end;
$$;

-- Online numbering: next number for a document.
create function public.next_doc_number(p_company uuid, p_location uuid, p_doc_type text, p_date date default current_date)
returns text
language plpgsql security definer set search_path = public as $$
declare
  s     number_series;
  v_co  text;
  v_loc text;
  v_num text;
begin
  if not public.user_can(p_doc_type, 'create', p_company, p_location) then
    raise exception 'not allowed to create % here', p_doc_type using errcode = '42501';
  end if;

  s := public.get_series(p_company, p_location, p_doc_type, p_date);
  select short_code into v_co from company where id = p_company;
  select short_code into v_loc from location where id = p_location;

  v_num := public.format_doc_number(s.pattern, v_co, v_loc, s.fy, s.next_value);
  if length(v_num) > s.max_length then
    raise exception 'document number % is longer than % characters; shorten the pattern', v_num, s.max_length;
  end if;

  update number_series set next_value = next_value + 1 where id = s.id;
  return v_num;
end;
$$;

-- Offline numbering: a device reserves a block while it has signal and uses it locally.
create function public.reserve_number_block(
  p_company uuid, p_location uuid, p_doc_type text, p_device_id text, p_count int default 50
) returns table (series_id uuid, pattern text, company_code text, location_code text, fy text,
                 from_value bigint, to_value bigint)
language plpgsql security definer set search_path = public as $$
declare
  s number_series;
begin
  if p_count not between 1 and 500 then
    raise exception 'block size must be between 1 and 500';
  end if;
  if not public.user_can(p_doc_type, 'create', p_company, p_location) then
    raise exception 'not allowed to create % here', p_doc_type using errcode = '42501';
  end if;

  s := public.get_series(p_company, p_location, p_doc_type, current_date);
  update number_series set next_value = next_value + p_count where id = s.id;

  insert into number_block (tenant_id, series_id, device_id, from_value, to_value)
  values (s.tenant_id, s.id, p_device_id, s.next_value, s.next_value + p_count - 1);

  return query
  select s.id, s.pattern, (select short_code from company where id = p_company),
         (select short_code from location where id = p_location), s.fy,
         s.next_value, s.next_value + p_count - 1;
end;
$$;

alter table public.number_series enable row level security;
alter table public.number_block  enable row level security;

create policy series_read  on public.number_series for select using (company_id in (select public.my_company_ids()));
create policy series_write on public.number_series for all
  using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));

create policy block_read on public.number_block for select
  using (user_id = auth.uid() or public.is_tenant_admin(tenant_id));
-- Devices report last_used on sync; reservation itself goes through reserve_number_block().
create policy block_update on public.number_block for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

select audit.track('public.number_series');
select audit.track('public.number_block');
