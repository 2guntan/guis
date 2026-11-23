-- =============================================================================
-- 0001_schema.sql — schéma Guis (NOTE-CADRAGE.md §2 et §5)
--
-- Schéma neuf et court, inspiré de Fieldproof (db/migrations) sans en reprendre le
-- modèle : comptes, producteurs, semences, champs, photos.
-- Les identifiants des producteurs, champs, semences et photos sont créés par
-- l'app Android (UUID) : le serveur fait un upsert par identifiant (pas de verrou
-- ni de statut, voir l'ADR-0007 de Fieldproof pour l'idée).
-- =============================================================================

create extension if not exists postgis;
create extension if not exists pgcrypto;

-- Comptes : connexion par numéro de téléphone et mot de passe, créés par script.
create table users (
  id             uuid primary key default gen_random_uuid(),
  phone          text not null unique check (phone ~ '^\+?[0-9]{6,15}$'),
  name           text not null,
  role           text not null check (role in ('admin', 'agent')),
  password_hash  text not null,
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);

-- Sessions : jeton opaque, seule son empreinte SHA-256 est gardée.
create table sessions (
  token_hash  text primary key,
  user_id     uuid not null references users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);
create index sessions_user_idx on sessions (user_id);

-- Listes remplies par script (scripts/load-lists.mjs).
create table villages (name text primary key);
create table varieties (name text primary key);

-- Photos : le fichier est sur le disque du VPS (volume Docker), la ligne en garde la trace.
create table photos (
  id            uuid primary key,
  path          text not null,
  content_type  text not null,
  size_bytes    integer not null,
  lat           double precision,
  lng           double precision,
  taken_at      timestamptz,
  uploaded_by   uuid references users(id),
  created_at    timestamptz not null default now()
);

create table producers (
  id           uuid primary key,
  last_name    text not null check (length(trim(last_name)) > 0),
  first_name   text not null check (length(trim(first_name)) > 0),
  phone        text,
  member_card  text,
  sex          text check (sex in ('F', 'H')),
  village      text,
  photo_id     uuid,          -- pas de clé étrangère : la photo peut arriver après
  consent_at   timestamptz not null,
  consent_by   uuid references users(id),
  source       text not null default 'app' check (source in ('app', 'import')),
  created_by   uuid references users(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
-- Le téléphone n'est pas unique : deux membres d'une même famille partagent souvent un numéro.
create index producers_phone_idx on producers (phone);
create unique index producers_card_uq on producers (member_card) where member_card is not null and member_card <> '';

create table seed_distributions (
  id           uuid primary key,
  producer_id  uuid not null references producers(id) on delete cascade,
  variety      text not null,
  quantity_kg  numeric(10, 2) not null check (quantity_kg > 0),
  received_on  date,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index seed_distributions_producer_idx on seed_distributions (producer_id);

create table fields (
  id                uuid primary key,
  producer_id       uuid not null references producers(id) on delete cascade,
  name              text,
  geom              geometry(Polygon, 4326),
  contour           jsonb not null default '[]'::jsonb,   -- sommets relevés : lat, lng, accuracy_m, captured_at
  area_measured_ha  numeric(10, 4) generated always as (round((st_area(geom::geography) / 10000)::numeric, 4)) stored,
  area_declared_ha  numeric(10, 4) check (area_declared_ha is null or area_declared_ha > 0),
  sown_on           date,
  irrigation        text,
  water_source      text,
  photo_id          uuid,
  created_by        uuid references users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint fields_geom_valid check (geom is null or st_isvalid(geom))
);
create index fields_producer_idx on fields (producer_id);
create index fields_geom_idx on fields using gist (geom);
