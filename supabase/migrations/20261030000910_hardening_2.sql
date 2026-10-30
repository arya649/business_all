-- Second pass on the security advisor list: helpers used only inside the rules are not callable directly,
-- and party balances are only visible to people in that company.

create or replace function public.party_balance(p_company uuid, p_party uuid) returns numeric
language sql stable security definer set search_path = public, extensions as $$
  select case when p_company in (select public.my_company_ids()) or auth.uid() is null then
    (select coalesce(sum(l.debit - l.credit), 0)
     from finance_journal_lines l join finance_journal j on j.id = l.parent_id
     where j.company_id = p_company and l.party_id = p_party and j.status = 'approved')
  end
$$;

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('match_approval_rule', 'step_required_approvers', 'is_step_approver', 'leakage_board_extra')
  loop
    execute format('revoke execute on function %s from authenticated, anon, public', f.sig);
  end loop;
end $$;
