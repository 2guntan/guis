-- =============================================================================
-- 0002_satellite.sql — suivi Sentinel-2 depuis le semis (NOTE-CADRAGE.md §4)
--
-- Table de travaux copiée de Fieldproof (db/migrations/0003_core_jobs.sql) et
-- simplifiée : un seul type de travail (`field_ndvi`), un travail en attente au
-- plus par champ, pas d'événements de domaine ni de RLS (une seule application
-- accède à la base).
-- =============================================================================

create table ndvi_points (
  field_id    uuid not null references fields(id) on delete cascade,
  scene_date  date not null,
  ndvi        real,            -- null : scène trop nuageuse sur le champ
  cloud_pct   real,
  pixels      integer,         -- pixels clairs retenus
  scene_id    text,
  primary key (field_id, scene_date)
);

create table field_status (
  field_id         uuid primary key references fields(id) on delete cascade,
  status          text not null check (status in ('waiting', 'bare', 'emergence', 'growth', 'peak', 'senescence')),
  days_since_sowing integer,
  last_ndvi        real,
  last_scene_date  date,
  peak_ndvi        real,
  indicative       boolean not null default false,
  pixels           integer,
  alerts           jsonb not null default '[]'::jsonb,   -- [{code, message}]
  computed_at      timestamptz not null default now()
);

create table jobs (
  id           bigint generated always as identity primary key,
  kind         text not null default 'field_ndvi' check (kind ~ '^[a-z_]+$'),
  field_id     uuid not null references fields(id) on delete cascade,
  status       text not null default 'queued' check (status in ('queued', 'running', 'done', 'failed')),
  attempts     integer not null default 0,
  max_attempts integer not null default 5,
  run_after    timestamptz not null default now(),
  locked_by    text,
  locked_at    timestamptz,
  last_error   text,
  result       jsonb,
  created_at   timestamptz not null default now(),
  finished_at  timestamptz
);
-- Un seul travail en attente par champ et par type : enfiler deux fois ne double rien.
create unique index jobs_one_queued on jobs (kind, field_id) where status = 'queued';
create index jobs_queue_idx on jobs (run_after) where status in ('queued', 'running');

-- Enfile un calcul pour un champ (sans effet s'il y en a déjà un en attente).
create or replace function enqueue_field(p_field uuid) returns void language sql as $$
  insert into jobs (field_id) values (p_field) on conflict do nothing;
$$;

-- Nouveau contour ou nouvelle date de semis : recalcul tout de suite.
create or replace function fields_enqueue() returns trigger language plpgsql as $$
begin
  if new.geom is not null and (tg_op = 'INSERT' or new.geom is distinct from old.geom or new.sown_on is distinct from old.sown_on) then
    perform enqueue_field(new.id);
  end if;
  return new;
end $$;
create trigger fields_enqueue after insert or update on fields for each row execute function fields_enqueue();

-- Réclamer jusqu'à p_limit travaux ; un travail bloqué (worker mort) est repris après 30 min.
create or replace function claim_jobs(p_worker text, p_limit integer default 2)
returns setof jobs language plpgsql as $$
begin
  return query
  update jobs j set status = 'running', locked_by = p_worker, locked_at = now(), attempts = j.attempts + 1
   where j.id in (
     select id from jobs
      where (status = 'queued' and run_after <= now())
         or (status = 'running' and locked_at < now() - interval '30 minutes')
      order by run_after, id
      limit greatest(1, least(p_limit, 50))
      for update skip locked)
  returning j.*;
end $$;

create or replace function complete_job(p_job bigint, p_result jsonb default null) returns void language plpgsql as $$
begin
  update jobs set status = 'done', result = p_result, finished_at = now(), last_error = null where id = p_job;
end $$;

-- Échec : rejoué après 1, 4, 9, 16… minutes ; définitif à max_attempts.
create or replace function fail_job(p_job bigint, p_error text) returns text language plpgsql as $$
declare j jobs;
begin
  select * into j from jobs where id = p_job for update;
  if not found then return 'missing'; end if;
  if j.attempts >= j.max_attempts then
    update jobs set status = 'failed', last_error = left(p_error, 2000), finished_at = now(), locked_by = null where id = p_job;
    return 'failed';
  end if;
  update jobs set status = 'queued', last_error = left(p_error, 2000), locked_by = null, locked_at = null,
                  run_after = now() + make_interval(mins => j.attempts * j.attempts)
   where id = p_job;
  return 'queued';
exception when unique_violation then
  -- un autre calcul du même champ est déjà en attente : celui-ci s'arrête
  update jobs set status = 'failed', last_error = left(p_error, 2000), finished_at = now() where id = p_job;
  return 'failed';
end $$;

-- Recalcul quotidien de tous les champs relevés.
create or replace function enqueue_all_fields() returns integer language plpgsql as $$
declare n integer;
begin
  insert into jobs (field_id) select id from fields where geom is not null on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
