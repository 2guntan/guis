-- =============================================================================
-- 0006_storage.sql — bucket privé « documents »
--   files/<file_id>/<document_id>.<ext>      pièces et photos (agent, tant qu'il peut écrire)
--   packages/<file_id>/<package_id>/<nom>    paquets générés (worker-docs, service_role)
-- Lecture : qui lit le dossier. Le prêteur ne lit jamais Storage : le serveur web
-- signe une URL courte après dossier.link_document (journalisé).
-- Aucune suppression ni remplacement par un client (pièces versionnées, ADR-0007).
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('documents', 'documents', false, 15728640,
        array['image/jpeg', 'image/png', 'image/webp', 'application/pdf', 'application/json',
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function dossier.path_file_id(p_name text) returns uuid
language plpgsql immutable as $$
declare v text := split_part(p_name, '/', 2);
begin
  if v ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return v::uuid; end if;
  return null;
end $$;
grant execute on function dossier.path_file_id(text) to authenticated;

drop policy if exists documents_agent_insert on storage.objects;
create policy documents_agent_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'documents' and split_part(name, '/', 1) = 'files'
              and name ~ '^files/[0-9a-f-]{36}/[0-9a-f-]{36}\.[a-z0-9]{2,5}$'
              and dossier.agent_can_write(dossier.path_file_id(name)));

drop policy if exists documents_read on storage.objects;
create policy documents_read on storage.objects for select to authenticated
  using (bucket_id = 'documents' and split_part(name, '/', 1) in ('files', 'packages')
         and dossier.can_read_file(dossier.path_file_id(name)));
