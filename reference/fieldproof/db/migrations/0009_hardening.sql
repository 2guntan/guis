-- =============================================================================
-- 0009_hardening.sql — corrections de l'audit Supabase (database advisors, 20/11/2026)
--   - core.organization_capabilities sans RLS (ERROR) : RLS + lecture pour les connectés
--     (les déclencheurs de rattachement la lisent avec le rôle de l'appelant) ;
--   - public.spatial_ref_sys (PostGIS) : plus lisible par anon / authenticated ;
--   - st_estimatedextent (PostGIS, security definer) : plus exécutable par les clients ;
--   - search_path figé sur toutes les fonctions qui ne l'avaient pas ;
--   - policies : auth.uid() évalué une fois par requête ((select auth.uid())).
-- Restent assumés : RPC security definer exposées (c'est le modèle : écriture par RPC),
-- extensions dans public (comme Agriva), protection des mots de passe divulgués (réglage Auth).
-- =============================================================================

alter table core.organization_capabilities enable row level security;
alter table core.event_consumers enable row level security;   -- workers seulement (service_role contourne la RLS)
drop policy if exists organization_capabilities_read on core.organization_capabilities;
create policy organization_capabilities_read on core.organization_capabilities for select to authenticated using (true);

do $$ begin
  execute 'revoke all on table public.spatial_ref_sys from anon, authenticated';
exception when others then raise notice 'spatial_ref_sys : %', sqlerrm;
end $$;
do $$ declare r record; begin
  for r in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = 'st_estimatedextent' loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

alter function core.current_profile_id() set search_path = core, pg_temp;
alter function core.domain_events_check() set search_path = core, pg_temp;
alter function core.has_capability(uuid, core.organization_capability) set search_path = core, pg_temp;
alter function core.in_my_org(uuid) set search_path = core, pg_temp;
alter function core.in_my_unit(uuid) set search_path = core, pg_temp;
alter function core.is_owner(uuid, uuid) set search_path = core, pg_temp;
alter function core.lock_down_functions(text) set search_path = pg_catalog, pg_temp;
alter function core.memberships_check() set search_path = core, pg_temp;
alter function core.org_unit_subtree(uuid) set search_path = core, pg_temp;
alter function core.org_units_check_tree() set search_path = core, pg_temp;
alter function core.scrub_job_secrets() set search_path = core, pg_temp;
alter function dossier.branch_routes_check() set search_path = dossier, core, pg_temp;
alter function dossier.lender_configs_touch() set search_path = dossier, core, pg_temp;
alter function dossier.path_file_id(text) set search_path = pg_temp;
alter function identity.parcels_check_geometry() set search_path = identity, public, extensions, pg_temp;
alter function identity.touch() set search_path = pg_temp;

drop policy memberships_read on core.memberships;
create policy memberships_read on core.memberships for select to authenticated
  using (profile_id = (select auth.uid()) or core.is_platform_admin() or core.in_my_org(organization_id));
drop policy profiles_self on core.profiles;
create policy profiles_self on core.profiles for select to authenticated
  using (id = (select auth.uid()) or core.is_platform_admin()
         or exists (select 1 from core.memberships mm join core.my_memberships() m on m.organization_id = mm.organization_id where mm.profile_id = profiles.id));
drop policy profiles_update_self on core.profiles;
create policy profiles_update_self on core.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
