-- =============================================================================
-- 0008_service_role_execute.sql — service_role exécute les fonctions des schémas métier
--
-- lock_down_functions révoque PUBLIC : service_role (workers, scripts d'administration)
-- perdait aussi l'exécution des helpers appelés par les déclencheurs (ex. has_capability
-- depuis memberships_check). service_role contourne déjà la RLS : lui accorder
-- l'exécution ne change pas la surface exposée aux clients (anon, authenticated).
-- lock_down_functions le fait désormais pour chaque schéma verrouillé.
-- =============================================================================
create or replace function core.lock_down_functions(p_schema text) returns void language plpgsql as $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig, p.prosecdef, p.prorettype
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = p_schema loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    execute format('grant execute on function %s to service_role', r.sig);
    if not r.prosecdef and r.prorettype <> 'trigger'::regtype then
      execute format('grant execute on function %s to authenticated, anon', r.sig);
    end if;
  end loop;
end $$;
revoke execute on function core.lock_down_functions(text) from public, anon, authenticated;

grant execute on all functions in schema core, identity, dossier, watch to service_role;
