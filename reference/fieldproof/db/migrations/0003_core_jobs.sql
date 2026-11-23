-- =============================================================================
-- 0003_core_jobs.sql — table de travaux des workers (ADR-0005)
--
-- Les événements de domaine alimentent la table de travaux : une route
-- (event_type → kind) enfile un travail dans la transaction de l'événement.
-- worker-docs et worker-sat réclament leurs travaux (FOR UPDATE SKIP LOCKED),
-- les terminent ou les échouent ; un échec est rejoué avec un délai croissant
-- jusqu'à max_attempts. Un travail bloqué (worker mort) est repris après 15 min.
-- =============================================================================

create type core.job_status as enum ('queued', 'running', 'done', 'failed');

create table core.jobs (
  id            bigint generated always as identity primary key,
  kind          text not null check (kind ~ '^[a-z_]+$'),
  payload       jsonb not null default '{}'::jsonb,
  status        core.job_status not null default 'queued',
  dedupe_key    text,
  attempts      integer not null default 0,
  max_attempts  integer not null default 5 check (max_attempts between 1 and 20),
  run_after     timestamptz not null default now(),
  locked_by     text,
  locked_at     timestamptz,
  last_error    text,
  result        jsonb,
  source_event_id bigint references core.domain_events(id),
  organization_id uuid references core.organizations(id),
  created_at    timestamptz not null default now(),
  finished_at   timestamptz
);
create unique index jobs_dedupe on core.jobs (kind, dedupe_key) where dedupe_key is not null;
create index jobs_queue_idx on core.jobs (kind, run_after) where status in ('queued', 'running');

create table core.job_routes (
  event_type  text not null references core.event_types(event_type),
  kind        text not null check (kind ~ '^[a-z_]+$'),
  primary key (event_type, kind)
);

-- Enfilement dans la transaction de l'événement ; dédoublonné par (kind, événement)
create or replace function core.domain_events_enqueue() returns trigger language plpgsql security definer set search_path = core, pg_temp as $$
begin
  insert into core.jobs (kind, payload, dedupe_key, source_event_id, organization_id)
  select r.kind,
         new.payload || jsonb_build_object('event_type', new.event_type, 'aggregate_type', new.aggregate_type,
                                           'aggregate_id', new.aggregate_id, 'event_id', new.id),
         r.kind || ':' || new.aggregate_id || ':' || new.id, new.id, new.organization_id
    from core.job_routes r where r.event_type = new.event_type
  on conflict do nothing;
  return new;
end $$;
create trigger domain_events_enqueue after insert on core.domain_events
  for each row execute function core.domain_events_enqueue();

-- Réclamer jusqu'à p_limit travaux d'un ou plusieurs types
create or replace function core.claim_jobs(p_kinds text[], p_worker text, p_limit integer default 5)
returns setof core.jobs language plpgsql security definer set search_path = core, pg_temp as $$
begin
  return query
  update core.jobs j set status = 'running', locked_by = p_worker, locked_at = now(), attempts = j.attempts + 1
   where j.id in (
     select id from core.jobs
      where kind = any (p_kinds)
        and ((status = 'queued' and run_after <= now())
          or (status = 'running' and locked_at < now() - interval '15 minutes'))
      order by run_after, id
      limit greatest(1, least(p_limit, 50))
      for update skip locked)
  returning j.*;
end $$;

create or replace function core.complete_job(p_job bigint, p_result jsonb default null) returns void
language plpgsql security definer set search_path = core, pg_temp as $$
begin
  update core.jobs set status = 'done', result = p_result, finished_at = now(), last_error = null
   where id = p_job and status = 'running';
  if not found then raise exception 'complete_job: travail % introuvable ou pas en cours', p_job; end if;
end $$;

-- Échec : rejoué après 1, 4, 9, 16… minutes ; définitif à max_attempts (ou si p_permanent)
create or replace function core.fail_job(p_job bigint, p_error text, p_permanent boolean default false) returns core.job_status
language plpgsql security definer set search_path = core, pg_temp as $$
declare j core.jobs;
begin
  select * into j from core.jobs where id = p_job and status = 'running' for update;
  if not found then raise exception 'fail_job: travail % introuvable ou pas en cours', p_job; end if;
  if p_permanent or j.attempts >= j.max_attempts then
    update core.jobs set status = 'failed', last_error = left(p_error, 2000), finished_at = now(), locked_by = null where id = p_job;
    return 'failed';
  end if;
  update core.jobs set status = 'queued', last_error = left(p_error, 2000), locked_by = null, locked_at = null,
                       run_after = now() + make_interval(mins => j.attempts * j.attempts)
   where id = p_job;
  return 'queued';
end $$;

alter table core.jobs       enable row level security;
alter table core.job_routes enable row level security;
revoke all on core.jobs, core.job_routes from authenticated, anon;
grant all on core.jobs, core.job_routes to service_role;

select null from core.lock_down_functions('core');
revoke execute on function core.lock_down_functions(text) from public, anon, authenticated;
grant execute on function core.my_memberships(), core.is_platform_admin(), core.sandbox_visible(uuid) to authenticated, anon;
grant execute on function core.claim_jobs(text[], text, integer), core.complete_job(bigint, jsonb), core.fail_job(bigint, text, boolean) to service_role;
