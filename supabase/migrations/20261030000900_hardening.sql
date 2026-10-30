-- Security hardening (from the Supabase security advisor).

-- 1. Reference tables: readable by signed-in users, changed only by migrations.
alter table public.fin_default_ledger enable row level security;
alter table public.fin_mirror_code enable row level security;
alter table public.posting_variant enable row level security;
create policy read_all on public.fin_default_ledger for select to authenticated using (true);
create policy read_all on public.fin_mirror_code for select to authenticated using (true);
create policy read_all on public.posting_variant for select to authenticated using (true);

-- 2. Signed-out callers get nothing except the device feed (devices authenticate with their own key).
revoke execute on all functions in schema public from anon, public;
grant execute on all functions in schema public to authenticated, service_role;
grant execute on function public.device_ingest(text, text, jsonb) to anon;
alter default privileges in schema public revoke execute on functions from anon, public;

-- 3. Internal machinery is called only by the rules themselves, never by people directly:
--    writing journals or stock, numbering without a check, re-installing triggers.
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'fin_ledger', 'fin_build_lines', 'fin_line', 'fin_write_journal', 'fin_mirror_lines', 'fin_post_document',
      'fin_reverse_journal', 'fin_party_of', 'fin_rule_for', 'stock_apply_document', 'erp_install_post_triggers',
      'billing_item', 'erp_ensure_series', 'get_series', 'doc_number_internal', 'erp_write_row', 'bank_auto_match',
      'purchase_three_way_match', 'erp_after_change')
  loop
    execute format('revoke execute on function %s from authenticated, anon, public', f.sig);
  end loop;
  -- audit internals: only the triggers and definer functions use them
  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'audit' and p.proname in ('append', 'capture', 'capture_role_permission', 'capture_party_company', 'track', 'set_context')
  loop
    execute format('revoke execute on function %s from authenticated, anon, public', f.sig);
  end loop;
end $$;

-- 4. Every function gets a fixed search path.
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    left join pg_depend d on d.objid = p.oid and d.deptype = 'e'
    where n.nspname in ('public', 'audit', 'deploy') and d.objid is null
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
  loop
    execute format('alter function %s set search_path = public, extensions', f.sig);
  end loop;
end $$;

-- ai_call marks its audit records as AI; it runs as owner (each erp function still checks the signed-in user).
alter function public.ai_call(text, jsonb) security definer;
