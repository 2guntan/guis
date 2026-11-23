#!/usr/bin/env bash
# =============================================================================
# run_local.sh — recrée une base de test, applique les migrations, joue la chaîne de tests avec assertions.
# Usage : PGHOST=… PGPORT=… PGUSER=… db/tests/run_local.sh   (base $DB, défaut fieldproof_test — DÉTRUITE puis recréée)
# Sortie : PASS (n assertions) par fichier, ALL GREEN à la fin ; toute assertion fausse ou erreur inattendue arrête la chaîne.
# Copié d'Agriva (packages/db/tests/run_local.sh) — voir PROVENANCE.md.
# =============================================================================
set -euo pipefail
DB="${DB:-fieldproof_test}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="${TMPDIR:-/tmp}/fieldproof-tests"; mkdir -p "$S"
psql -v ON_ERROR_STOP=1 -q -c "drop database if exists $DB" postgres
psql -v ON_ERROR_STOP=1 -q -c "create database $DB" postgres
# Stubs Supabase minimaux : auth.users, auth.uid(), rôles anon / authenticated / service_role.
psql -v ON_ERROR_STOP=1 -q -d "$DB" <<'SQL'
create extension if not exists citext; create extension if not exists postgis;
create schema auth; create table auth.users (id uuid primary key, email text);
create or replace function auth.uid() returns uuid language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;
grant usage on schema auth to anon, authenticated, service_role;
alter role service_role with bypassrls;
-- Storage Supabase réduit à ce que les migrations touchent (bucket, objets sous RLS).
create schema storage;
create table storage.buckets (id text primary key, name text not null, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id),
  name text not null, owner uuid, owner_id text, metadata jsonb, created_at timestamptz default now(), unique (bucket_id, name));
alter table storage.objects enable row level security;
grant usage on schema storage to anon, authenticated, service_role;
grant all on storage.objects, storage.buckets to anon, authenticated, service_role;
SQL
for f in "$ROOT"/migrations/*.sql; do
  echo "== $(basename "$f")"
  psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$f" || { echo "MIGRATION FAILED: $f"; exit 1; }
done
psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$ROOT/tests/_harness.sql" || exit 1
for t in smoke_core smoke_dossier; do
  echo "== $t"
  if psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$ROOT/tests/$t.sql" > "$S/$t.out" 2>&1; then echo "   PASS ($(grep -c '^ ok' "$S/$t.out") assertions)"; else echo "   FAIL"; tail -5 "$S/$t.out"; exit 1; fi
done
echo "== ALL GREEN"
