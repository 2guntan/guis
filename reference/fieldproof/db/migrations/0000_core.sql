-- =============================================================================
-- 0000_core.sql — Fieldproof : organisations, unités, rattachements, rôles,
-- axes RLS, bac à sable, événements de domaine.
--
-- Copié d'Agriva (packages/db/migrations/0000_core.sql, commit ee8fbe1) et
-- réduit au besoin des modules Dossier et Watch (ADR-0001). Voir PROVENANCE.md.
--
-- Règle structurelle : le test/démo n'est pas un motif de nom, c'est une
-- organisation « bac à sable » (core.organizations.is_sandbox = true). Tout ce
-- que créent ses membres est invisible aux autres organisations et exclu des
-- KPI par construction (core.sandbox_visible()).
--
-- Logique en Postgres standard (ADR-0004). Seuls prérequis Supabase :
-- auth.users, auth.uid() et les rôles anon / authenticated / service_role ;
-- en local, db/tests/run_local.sh crée ces stubs.
-- =============================================================================

create extension if not exists pgcrypto;
create extension if not exists citext;

create schema if not exists core;

-- Politique d'exécution : par défaut Postgres accorde EXECUTE à PUBLIC sur toute fonction.
-- Chaque migration appelle core.lock_down_functions('<schéma>') avant ses grants explicites :
--   - tout est révoqué de public / anon / authenticated ;
--   - les helpers de lecture (ni security definer, ni trigger) sont ré-ouverts à authenticated et anon (policies) ;
--   - les RPC security definer sont ensuite accordées une à une.
create or replace function core.lock_down_functions(p_schema text) returns void language plpgsql as $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig, p.prosecdef, p.prorettype
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = p_schema loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    if not r.prosecdef and r.prorettype <> 'trigger'::regtype then
      execute format('grant execute on function %s to authenticated, anon', r.sig);
    end if;
  end loop;
end $$;
revoke all on function core.lock_down_functions(text) from public;

-- -----------------------------------------------------------------------------
-- Types
-- -----------------------------------------------------------------------------
create type core.organization_kind as enum (
  'platform',      -- Fieldproof elle-même (admin plateforme, bac à sable QA)
  'originator',    -- originateur : collecte les dossiers clients sur le terrain (IBRIZ)
  'lender'         -- prêteur : reçoit les paquets, ouvre le compte, décide du crédit (PAMECAS)
);

-- Une organisation peut cumuler des capacités au-delà de sa nature principale
create type core.organization_capability as enum ('originate', 'lend');

create type core.org_unit_kind as enum (
  'headquarters',  -- une et une seule par organisation (siège du prêteur : adresse centrale)
  'branch',        -- caisse du prêteur
  'team'           -- équipe terrain de l'originateur (une par zone)
);

-- Le prêteur n'a pas de compte utilisateur au départ (ADR-0002) : aucun rôle prêteur.
create type core.role as enum (
  'platform_admin',
  'org_admin',
  'field_agent',       -- agent terrain
  'field_supervisor'   -- superviseur
);

-- -----------------------------------------------------------------------------
-- Organisations
-- -----------------------------------------------------------------------------
create table core.organizations (
  id            uuid primary key default gen_random_uuid(),
  code          citext not null unique,
  name          text   not null check (char_length(btrim(name)) between 2 and 200),
  kind          core.organization_kind not null,
  is_sandbox    boolean not null default false,   -- données de test/démo
  settings      jsonb   not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  archived_at   timestamptz,
  constraint organizations_sandbox_is_platform check (not is_sandbox or kind = 'platform')
);
comment on table  core.organizations is 'Tenant. Le code ne teste jamais un code d''organisation ; il teste kind ou une capacité.';
comment on column core.organizations.is_sandbox is 'Organisation bac à sable : comptes de test, démos, QA. Invisible hors de ses membres, exclue des KPI.';
comment on column core.organizations.settings is 'Réglages propres à l''organisation (jsonb). La configuration prêteur (ADR-0003) a sa propre migration.';

create table core.organization_capabilities (
  organization_id uuid not null references core.organizations(id) on delete cascade,
  capability      core.organization_capability not null,
  granted_at      timestamptz not null default now(),
  primary key (organization_id, capability)
);

-- Capacité implicite de la nature principale
create or replace function core.has_capability(p_org uuid, p_cap core.organization_capability)
returns boolean language sql stable as $$
  select exists (select 1 from core.organization_capabilities where organization_id = p_org and capability = p_cap)
      or exists (
        select 1 from core.organizations o where o.id = p_org and (
             (o.kind = 'originator' and p_cap = 'originate')
          or (o.kind = 'lender'     and p_cap = 'lend')
        ));
$$;

-- -----------------------------------------------------------------------------
-- Référentiel géographique (localité du client → caisse ; zones des caisses)
-- -----------------------------------------------------------------------------
create table core.geo_regions (
  id         uuid primary key default gen_random_uuid(),
  name       citext not null unique,
  code       char(3),
  created_at timestamptz not null default now()
);
create table core.geo_communes (
  id         uuid primary key default gen_random_uuid(),
  region_id  uuid not null references core.geo_regions(id),
  name       citext not null,
  created_at timestamptz not null default now(),
  unique (region_id, name)
);
create table core.geo_villages (
  id         uuid primary key default gen_random_uuid(),
  commune_id uuid not null references core.geo_communes(id),
  name       citext not null,
  created_at timestamptz not null default now(),
  unique (commune_id, name)
);
create index geo_villages_name_idx on core.geo_villages (name);

-- -----------------------------------------------------------------------------
-- Unités d'organisation (arbre : siège → caisses / équipes)
-- -----------------------------------------------------------------------------
create table core.org_units (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references core.organizations(id) on delete cascade,
  kind            core.org_unit_kind not null,
  parent_id       uuid references core.org_units(id),
  code            citext not null,
  name            text not null check (char_length(btrim(name)) between 2 and 200),
  region_id       uuid references core.geo_regions(id),
  commune_id      uuid references core.geo_communes(id),
  created_at      timestamptz not null default now(),
  archived_at     timestamptz,
  unique (organization_id, code),
  constraint org_units_headquarters_has_no_parent check (kind <> 'headquarters' or parent_id is null),
  constraint org_units_non_headquarters_has_parent check (kind = 'headquarters' or parent_id is not null)
);
create unique index org_units_one_headquarters_per_org
  on core.org_units (organization_id) where kind = 'headquarters' and archived_at is null;
create index org_units_parent_idx on core.org_units (parent_id);

-- Descendance d'une unité (contrôle de cycle)
create or replace function core.org_unit_subtree(p_unit uuid)
returns setof uuid language sql stable as $$
  with recursive t as (
    select id from core.org_units where id = p_unit
    union all
    select u.id from core.org_units u join t on u.parent_id = t.id
  ) select id from t;
$$;

-- Invariants d'arbre : parent dans la même organisation, feuilles sans enfants, pas de cycle
create or replace function core.org_units_check_tree() returns trigger language plpgsql as $$
declare
  v_parent core.org_units;
begin
  if new.parent_id is not null then
    select * into v_parent from core.org_units where id = new.parent_id;
    if v_parent.organization_id <> new.organization_id then
      raise exception 'org_units: parent % appartient à une autre organisation', new.parent_id;
    end if;
    if v_parent.kind in ('branch', 'team') then
      raise exception 'org_units: une unité de type % ne peut pas avoir d''enfants', v_parent.kind;
    end if;
    -- pas de cycle : le nouveau parent ne doit pas être dans la descendance de l'unité (CTE récursive infinie sinon)
    if tg_op = 'UPDATE' and new.parent_id in (select core.org_unit_subtree(new.id)) then
      raise exception 'org_units: cycle détecté (le parent % est un descendant)', new.parent_id;
    end if;
  end if;
  return new;
end $$;
create trigger org_units_check_tree before insert or update on core.org_units
  for each row execute function core.org_units_check_tree();

-- -----------------------------------------------------------------------------
-- Profils et rattachements
-- -----------------------------------------------------------------------------
create table core.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  full_name    text not null default '',
  phone        text,
  email        citext,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz
);

create table core.memberships (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references core.profiles(id) on delete cascade,
  organization_id uuid not null references core.organizations(id) on delete cascade,
  org_unit_id     uuid references core.org_units(id),
  role            core.role not null,
  active          boolean not null default true,
  valid_from      timestamptz not null default now(),
  valid_until     timestamptz,
  created_at      timestamptz not null default now(),
  constraint memberships_validity check (valid_until is null or valid_until > valid_from),
  -- rôle de niveau unité : rattachement obligatoire
  constraint memberships_unit_required check (role <> 'field_agent' or org_unit_id is not null),
  -- rôles de niveau organisation : pas de rattachement d'unité
  constraint memberships_unit_forbidden check (
    role not in ('platform_admin', 'org_admin', 'field_supervisor') or org_unit_id is null
  )
);
-- Un compte = un rôle actif par organisation
create unique index memberships_one_active_role_per_org
  on core.memberships (profile_id, organization_id) where active;
create index memberships_profile_idx on core.memberships (profile_id) where active;

-- Cohérence rôle ↔ nature d'organisation et rôle ↔ type d'unité
create or replace function core.memberships_check() returns trigger language plpgsql as $$
declare
  v_org  core.organizations;
  v_unit core.org_units;
begin
  select * into v_org from core.organizations where id = new.organization_id;
  if new.role = 'platform_admin' and (v_org.kind <> 'platform' or v_org.is_sandbox) then
    raise exception 'memberships: platform_admin réservé à l''organisation plateforme de production';
  end if;
  if new.role in ('field_agent', 'field_supervisor') and not core.has_capability(v_org.id, 'originate') then
    raise exception 'memberships: rôle % requiert la capacité originate', new.role;
  end if;
  if new.org_unit_id is not null then
    select * into v_unit from core.org_units where id = new.org_unit_id;
    if v_unit.organization_id <> new.organization_id then
      raise exception 'memberships: unité % hors de l''organisation', new.org_unit_id;
    end if;
    if new.role = 'field_agent' and v_unit.kind <> 'team' then
      raise exception 'memberships: rôle % incompatible avec une unité de type %', new.role, v_unit.kind;
    end if;
  end if;
  return new;
end $$;
create trigger memberships_check before insert or update on core.memberships
  for each row execute function core.memberships_check();

-- -----------------------------------------------------------------------------
-- Événements de domaine (append-only) — alimentent worker-docs et worker-sat (ADR-0005)
-- -----------------------------------------------------------------------------
create table core.domain_events (
  id              bigint generated always as identity primary key,
  occurred_at     timestamptz not null default now(),
  event_type      text not null,          -- '<contexte>.<agrégat>.<fait_passé>'
  aggregate_type  text not null,
  aggregate_id    uuid not null,
  organization_id uuid references core.organizations(id),
  actor_id        uuid references core.profiles(id),
  payload         jsonb not null default '{}'::jsonb
);
create index domain_events_aggregate_idx on core.domain_events (aggregate_type, aggregate_id, occurred_at);
create index domain_events_type_idx on core.domain_events (event_type, occurred_at);
revoke update, delete on core.domain_events from public;

-- Catalogue des types d'événements : un type non catalogué est refusé.
-- Nommage : <contexte>.<agrégat>.<fait_passé>, snake_case anglais.
create table core.event_types (
  event_type     text primary key check (event_type ~ '^[a-z]+\.[a-z_]+\.[a-z_]+$'),
  context        text not null generated always as (split_part(event_type, '.', 1)) stored,
  description    text not null,
  payload_schema jsonb,                   -- optionnel : schéma JSON indicatif du payload
  introduced_in  text not null,           -- migration qui l'a ajouté
  deprecated_at  timestamptz
);

-- Refus des types non catalogués + payload versionné
create or replace function core.domain_events_check() returns trigger language plpgsql as $$
begin
  if not exists (select 1 from core.event_types t where t.event_type = new.event_type and t.deprecated_at is null) then
    raise exception 'domain_events: type % non catalogué dans core.event_types', new.event_type;
  end if;
  if not (new.payload ? 'v') then
    new.payload := new.payload || '{"v": 1}'::jsonb;
  end if;
  return new;
end $$;
create trigger domain_events_check before insert on core.domain_events
  for each row execute function core.domain_events_check();

-- Émission unique : toute RPC / trigger passe par ici (même transaction que l'écriture métier)
create or replace function core.emit_event(
  p_event_type      text,
  p_aggregate_type  text,
  p_aggregate_id    uuid,
  p_payload         jsonb default '{}'::jsonb,
  p_organization_id uuid default null,
  p_actor_id        uuid default auth.uid()
) returns bigint language plpgsql security definer set search_path = core, pg_temp as $$
declare v_id bigint;
begin
  -- migration de données (superuser) : les écritures ne sont pas des faits métier, aucun événement ni réaction
  if current_setting('core.suppress_events', true) = 'on' and current_user not in ('authenticated', 'anon') then return null; end if;
  insert into core.domain_events (event_type, aggregate_type, aggregate_id, organization_id, actor_id, payload)
  values (p_event_type, p_aggregate_type, p_aggregate_id, p_organization_id, p_actor_id, coalesce(p_payload, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;
-- Jamais exécutable par un client : seules les RPC (security definer, propriétaire) et les workers émettent.
-- Un client qui pourrait émettre forgerait des soumissions, des envois, des retours du prêteur.
revoke all on function core.emit_event(text, text, uuid, jsonb, uuid, uuid) from public, anon, authenticated;
grant execute on function core.emit_event(text, text, uuid, jsonb, uuid, uuid) to service_role;

-- Consommateurs hors base (workers) : un curseur par consommateur, au-moins-une-fois.
-- Chaque consommateur est enregistré par la migration qui en a besoin.
create table core.event_consumers (
  consumer          text primary key,
  last_processed_id bigint not null default 0,
  last_processed_at timestamptz,
  event_types       text[],                -- null = tous
  updated_at        timestamptz not null default now()
);

-- Lecture par curseur : ce qu'un worker appelle en boucle
create or replace function core.next_events(p_consumer text, p_limit integer default 100)
returns setof core.domain_events language sql stable security definer set search_path = core, pg_temp as $$
  select e.* from core.domain_events e
  join core.event_consumers c on c.consumer = p_consumer
  where e.id > c.last_processed_id
    and (c.event_types is null or e.event_type = any (c.event_types))
  order by e.id
  limit p_limit;
$$;

create or replace function core.ack_events(p_consumer text, p_last_id bigint) returns void
language sql security definer set search_path = core, pg_temp as $$
  update core.event_consumers
  set last_processed_id = greatest(last_processed_id, p_last_id), last_processed_at = now(), updated_at = now()
  where consumer = p_consumer;
$$;
revoke all on function core.next_events(text, integer) from public;
revoke all on function core.ack_events(text, bigint) from public;
grant execute on function core.next_events(text, integer), core.ack_events(text, bigint) to service_role;

-- Catalogue de core (chaque contexte ajoute les siens dans sa migration)
insert into core.event_types (event_type, description, introduced_in) values
  ('core.organization.created', 'Organisation créée',               '0000_core'),
  ('core.membership.granted',   'Rattachement accordé à un profil', '0000_core'),
  ('core.membership.revoked',   'Rattachement révoqué',             '0000_core')
on conflict (event_type) do nothing;

-- -----------------------------------------------------------------------------
-- Fonctions d'axe (RLS) — toutes STABLE, security definer pour lire memberships
-- -----------------------------------------------------------------------------
create or replace function core.current_profile_id() returns uuid
language sql stable as $$ select auth.uid() $$;

create or replace function core.my_memberships()
returns table (organization_id uuid, org_unit_id uuid, role core.role)
language sql stable security definer set search_path = core, pg_temp as $$
  select organization_id, org_unit_id, role
  from core.memberships
  where profile_id = auth.uid() and active
    and valid_from <= now() and (valid_until is null or valid_until > now());
$$;

-- platform_admin n'existe que dans l'organisation plateforme de production (jamais dans le bac à sable)
create or replace function core.is_platform_admin() returns boolean
language sql stable security definer set search_path = core, pg_temp as $$
  select exists (select 1 from core.my_memberships() m join core.organizations o on o.id = m.organization_id
                  where m.role = 'platform_admin' and o.kind = 'platform' and not o.is_sandbox);
$$;

-- Axe org
create or replace function core.in_my_org(p_org uuid) returns boolean
language sql stable as $$
  select exists (select 1 from core.my_memberships() where organization_id = p_org);
$$;

-- Axe unit (équipe de l'agent terrain)
create or replace function core.in_my_unit(p_unit uuid) returns boolean
language sql stable as $$
  select exists (select 1 from core.my_memberships() where org_unit_id = p_unit);
$$;

-- Axe own
create or replace function core.is_owner(p_created_by uuid, p_assigned_to uuid default null) returns boolean
language sql stable as $$
  select auth.uid() is not null and (p_created_by = auth.uid() or p_assigned_to = auth.uid());
$$;

-- Règle bac à sable : une ligne créée par une organisation sandbox n'est visible
-- que des membres de cette sandbox (et des platform_admin).
create or replace function core.sandbox_visible(p_created_by_org uuid) returns boolean
language sql stable security definer set search_path = core, pg_temp as $$
  select case
    when p_created_by_org is null then true
    when not exists (select 1 from core.organizations o where o.id = p_created_by_org and o.is_sandbox) then true
    else core.is_platform_admin() or core.in_my_org(p_created_by_org)
  end;
$$;

-- Vue « production seule » pour les KPI : à utiliser dans toute agrégation
create or replace view core.production_organizations with (security_invoker = true) as
  select * from core.organizations where not is_sandbox and archived_at is null;

-- -----------------------------------------------------------------------------
-- RLS sur core
-- -----------------------------------------------------------------------------
alter table core.organizations             enable row level security;
alter table core.org_units                 enable row level security;
alter table core.profiles                  enable row level security;
alter table core.memberships               enable row level security;
alter table core.domain_events             enable row level security;
alter table core.event_types               enable row level security;
create policy event_types_read on core.event_types for select to authenticated using (true);

create policy organizations_read on core.organizations for select to authenticated
  using (core.is_platform_admin() or core.in_my_org(id) or not is_sandbox);
create policy organizations_admin on core.organizations for all to authenticated
  using (core.is_platform_admin()) with check (core.is_platform_admin());

create policy org_units_read on core.org_units for select to authenticated
  using (core.is_platform_admin() or core.in_my_org(organization_id)
         or exists (select 1 from core.organizations o where o.id = organization_id and not o.is_sandbox));
create policy org_units_admin on core.org_units for all to authenticated
  using (core.is_platform_admin() or exists (select 1 from core.my_memberships() m where m.organization_id = org_units.organization_id and m.role = 'org_admin'))
  with check (core.is_platform_admin() or exists (select 1 from core.my_memberships() m where m.organization_id = org_units.organization_id and m.role = 'org_admin'));

-- Un profil naît avec le compte Auth (jamais inséré par un client). to_jsonb(new) : tolère l'absence de raw_user_meta_data (harnais local).
create or replace function core.on_auth_user_created() returns trigger language plpgsql security definer set search_path = core, pg_temp as $$
declare j jsonb := to_jsonb(new);
begin
  insert into core.profiles (id, email, full_name)
  values (new.id, j->>'email', coalesce(j->'raw_user_meta_data'->>'full_name', ''))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function core.on_auth_user_created();

create policy profiles_self on core.profiles for select to authenticated
  using (id = auth.uid() or core.is_platform_admin()
         or exists (select 1 from core.memberships mm join core.my_memberships() m on m.organization_id = mm.organization_id where mm.profile_id = profiles.id));
create policy profiles_update_self on core.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy memberships_read on core.memberships for select to authenticated
  using (profile_id = auth.uid() or core.is_platform_admin() or core.in_my_org(organization_id));
-- Seul un platform_admin touche un rattachement platform_admin (ni le viser, ni l'écrire) — correctif Agriva 0020.
create policy memberships_admin on core.memberships for all to authenticated
  using (core.is_platform_admin()
         or (role <> 'platform_admin'
             and exists (select 1 from core.my_memberships() m
                          where m.organization_id = memberships.organization_id and m.role = 'org_admin')))
  with check (core.is_platform_admin()
              or (role <> 'platform_admin'
                  and exists (select 1 from core.my_memberships() m
                               where m.organization_id = memberships.organization_id and m.role = 'org_admin')));

create policy domain_events_read on core.domain_events for select to authenticated
  using (core.is_platform_admin() or core.in_my_org(organization_id));

-- Référentiel géo : lecture pour tous, écriture plateforme
alter table core.geo_regions  enable row level security;
alter table core.geo_communes enable row level security;
alter table core.geo_villages enable row level security;
create policy geo_regions_read  on core.geo_regions  for select to authenticated, anon using (true);
create policy geo_communes_read on core.geo_communes for select to authenticated, anon using (true);
create policy geo_villages_read on core.geo_villages for select to authenticated, anon using (true);
create policy geo_regions_admin  on core.geo_regions  for all to authenticated using (core.is_platform_admin()) with check (core.is_platform_admin());
create policy geo_communes_admin on core.geo_communes for all to authenticated using (core.is_platform_admin()) with check (core.is_platform_admin());
create policy geo_villages_admin on core.geo_villages for all to authenticated using (core.is_platform_admin()) with check (core.is_platform_admin());

grant usage on schema core to anon, authenticated, service_role;
grant select on all tables in schema core to authenticated;
revoke select on core.event_consumers from authenticated;
grant select on core.geo_regions, core.geo_communes, core.geo_villages to anon;
-- Configuration (organisations, unités, rattachements) : écriture par les admins via policies ; tout le reste par RPC.
grant insert, update on core.memberships, core.org_units, core.organizations to authenticated;
grant update on core.profiles to authenticated;
grant all on all tables in schema core to service_role;
revoke update, delete on core.domain_events from service_role;      -- append-only, même pour les workers
-- Fonctions : rien n'est exécutable par défaut ; les helpers de policy (lecture) sont ouverts, les RPC accordées explicitement
select null from core.lock_down_functions('core');
-- lock_down_functions ré-ouvre les fonctions non security definer : elle-même ne doit pas l'être (correctif Agriva 0014).
revoke execute on function core.lock_down_functions(text) from public, anon, authenticated;
grant execute on function core.my_memberships(), core.is_platform_admin(), core.sandbox_visible(uuid) to authenticated, anon;

-- -----------------------------------------------------------------------------
-- Seed structurel (idempotent). IDs fixes pour être référencés par les scripts et les tests.
-- Les caisses PAMECAS ne sont pas semées : liste à confirmer (Cadrage pilote, prérequis).
-- -----------------------------------------------------------------------------
insert into core.organizations (id, code, name, kind, is_sandbox) values
  ('00000000-0000-4000-8000-000000000001', 'FIELDPROOF',    'Fieldproof — plateforme',                'platform',   false),
  ('00000000-0000-4000-8000-000000000002', 'FIELDPROOF-QA', 'Fieldproof — bac à sable (tests, démos)', 'platform',   true),
  ('00000000-0000-4000-8000-000000000010', 'IBRIZ',         'IBRIZ',                                  'originator', false),
  ('00000000-0000-4000-8000-000000000020', 'PAMECAS',       'PAMECAS',                                'lender',     false)
on conflict (code) do update set name = excluded.name, kind = excluded.kind, is_sandbox = excluded.is_sandbox;

insert into core.organization_capabilities (organization_id, capability) values
  -- le bac à sable rejoue l'originateur et le prêteur en démo
  ('00000000-0000-4000-8000-000000000002', 'originate'),
  ('00000000-0000-4000-8000-000000000002', 'lend')
on conflict do nothing;

-- Sièges
insert into core.org_units (id, organization_id, kind, code, name) values
  ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000001', 'headquarters', 'HQ', 'Fieldproof'),
  ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000002', 'headquarters', 'HQ', 'Bac à sable'),
  ('00000000-0000-4000-8000-000000000110', '00000000-0000-4000-8000-000000000010', 'headquarters', 'HQ', 'IBRIZ — siège Dakar'),
  ('00000000-0000-4000-8000-000000000120', '00000000-0000-4000-8000-000000000020', 'headquarters', 'DG', 'Direction générale PAMECAS')
on conflict (organization_id, code) do nothing;

-- Équipes terrain IBRIZ des deux zones du pilote ; équipe et caisse du bac à sable
insert into core.org_units (organization_id, kind, parent_id, code, name) values
  ('00000000-0000-4000-8000-000000000010', 'team',   '00000000-0000-4000-8000-000000000110', 'NIAYES',    'Équipe Niayes'),
  ('00000000-0000-4000-8000-000000000010', 'team',   '00000000-0000-4000-8000-000000000110', 'ZIG',       'Équipe Ziguinchor'),
  ('00000000-0000-4000-8000-000000000002', 'team',   '00000000-0000-4000-8000-000000000102', 'QA-TEAM',   'Équipe QA'),
  ('00000000-0000-4000-8000-000000000002', 'branch', '00000000-0000-4000-8000-000000000102', 'QA-CAISSE', 'Caisse QA')
on conflict (organization_id, code) do nothing;
