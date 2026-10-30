-- Photos and files (bill photos, totaliser photos, signatures, site photos). Only on real Supabase.
do $$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;
  insert into storage.buckets (id, name, public) values ('erp-files', 'erp-files', true) on conflict (id) do nothing;
  -- files go under <tenant id>/...; people upload only into their own group's folder
  execute $p$create policy erp_files_insert on storage.objects for insert to authenticated
            with check (bucket_id = 'erp-files' and (storage.foldername(name))[1] = public.auth_tenant_id()::text)$p$;
  execute $p$create policy erp_files_read on storage.objects for select to authenticated
            using (bucket_id = 'erp-files' and (storage.foldername(name))[1] = public.auth_tenant_id()::text)$p$;
end $$;
