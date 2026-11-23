-- =============================================================================
-- 0005_watch.sql — Module Watch, tranche 1 : analyse rétroactive des parcelles
--
-- Une parcelle dont la géométrie valide est enregistrée émet
-- identity.parcel.geometry_recorded → travail « retro_analysis » pour worker-sat.
-- worker-sat analyse les 2 à 3 dernières saisons (Sentinel-2 ; Sentinel-1 plus tard
-- pour l'hivernage en Casamance), puis écrit le résultat par RPC.
-- Le résultat alimente la fiche Fieldproof. Suivi continu et alertes : tranche 2.
-- =============================================================================

create schema if not exists watch;

create type watch.retro_status  as enum ('running', 'done', 'failed');
create type watch.retro_verdict as enum ('cultivated', 'partially_cultivated', 'not_cultivated', 'uncertain');

create table watch.retro_analyses (
  id                  uuid primary key default gen_random_uuid(),
  parcel_id           uuid not null references identity.parcels(id) on delete cascade,
  status              watch.retro_status not null default 'running',
  provider            text not null,                      -- 'planetary_computer:sentinel-2-l2a'
  geometry_hash       text not null,                      -- md5 du WKB analysé : une recapture relance l'analyse
  seasons_analyzed    integer check (seasons_analyzed is null or seasons_analyzed between 0 and 10),
  cultivated_seasons  integer check (cultivated_seasons is null or cultivated_seasons >= 0),
  verdict             watch.retro_verdict,
  confirmed_area_ha   numeric(10,4),
  seasons             jsonb,                              -- [{label, start, end, ndvi_peak, ndvi_peak_date, cultivated, cloud_free_scenes}]
  ndvi_series         jsonb,                              -- [{date, ndvi, cloud_pct}]
  summary             text,
  error               text,
  started_at          timestamptz not null default now(),
  finished_at         timestamptz,
  job_id              bigint
);
create index retro_analyses_parcel_idx on watch.retro_analyses (parcel_id, started_at desc);

insert into core.event_types (event_type, description, introduced_in) values
  ('watch.retro_analysis.completed', 'Analyse rétroactive d''une parcelle terminée', '0005_watch')
on conflict (event_type) do nothing;
insert into core.job_routes (event_type, kind) values ('identity.parcel.geometry_recorded', 'retro_analysis') on conflict do nothing;

-- worker-sat : démarre une analyse et reçoit la géométrie (null si la parcelle a disparu ou est invalide)
create or replace function watch.start_retro(p_parcel uuid, p_provider text, p_job bigint default null) returns jsonb
language plpgsql security definer set search_path = watch, identity, public, pg_temp as $$
declare p identity.parcels; v_id uuid; v_hash text;
begin
  select * into p from identity.parcels where id = p_parcel;
  if not found or p.archived_at is not null or p.geometry is null or p.geometry_invalid_reason is not null then
    return jsonb_build_object('skip', true, 'reason', 'parcelle absente, archivée ou sans contour valide');
  end if;
  v_hash := md5(ST_AsBinary(p.geometry));
  if exists (select 1 from watch.retro_analyses where parcel_id = p_parcel and geometry_hash = v_hash and status = 'done') then
    return jsonb_build_object('skip', true, 'reason', 'déjà analysée pour ce contour');
  end if;
  insert into watch.retro_analyses (parcel_id, provider, geometry_hash, job_id) values (p_parcel, p_provider, v_hash, p_job) returning id into v_id;
  return jsonb_build_object('skip', false, 'analysis_id', v_id, 'geometry', ST_AsGeoJSON(p.geometry)::jsonb,
                            'area_ha', p.gps_area_ha, 'centroid', ST_AsGeoJSON(p.centroid)::jsonb);
end $$;

create or replace function watch.finish_retro(p_analysis uuid, p_result jsonb) returns void
language plpgsql security definer set search_path = watch, identity, core, pg_temp as $$
declare a watch.retro_analyses; v_org uuid;
begin
  select * into a from watch.retro_analyses where id = p_analysis for update;
  if not found or a.status <> 'running' then raise exception 'finish_retro: analyse introuvable ou terminée'; end if;
  update watch.retro_analyses set status = 'done', finished_at = now(),
    seasons_analyzed = (p_result->>'seasons_analyzed')::integer, cultivated_seasons = (p_result->>'cultivated_seasons')::integer,
    verdict = (p_result->>'verdict')::watch.retro_verdict, confirmed_area_ha = nullif(p_result->>'confirmed_area_ha', '')::numeric,
    seasons = p_result->'seasons', ndvi_series = p_result->'ndvi_series', summary = p_result->>'summary'
   where id = p_analysis;
  select created_by_organization_id into v_org from identity.parcels where id = a.parcel_id;
  perform core.emit_event('watch.retro_analysis.completed', 'parcel', a.parcel_id,
    jsonb_build_object('v', 1, 'analysis_id', p_analysis, 'verdict', p_result->>'verdict'), v_org, null);
end $$;

create or replace function watch.fail_retro(p_analysis uuid, p_error text) returns void
language sql security definer set search_path = watch, pg_temp as $$
  update watch.retro_analyses set status = 'failed', error = left(p_error, 2000), finished_at = now() where id = p_analysis and status = 'running';
$$;

alter table watch.retro_analyses enable row level security;
create policy retro_analyses_read on watch.retro_analyses for select to authenticated
  using (exists (select 1 from identity.parcels p where p.id = parcel_id and dossier.can_read_farm(p.farm_id)));

-- Dernière analyse par parcelle, pour les écrans
create or replace view watch.latest_retro with (security_invoker = true) as
  select distinct on (parcel_id) * from watch.retro_analyses order by parcel_id, started_at desc;

grant usage on schema watch to authenticated, service_role;
grant select on all tables in schema watch to authenticated;
grant all on all tables in schema watch to service_role;
select null from core.lock_down_functions('watch');
grant execute on function watch.start_retro(uuid, text, bigint), watch.finish_retro(uuid, jsonb), watch.fail_retro(uuid, text) to service_role;
