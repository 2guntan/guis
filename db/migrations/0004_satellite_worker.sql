-- =============================================================================
-- 0004_satellite_worker.sql — compléments pour le worker satellite (ticket 08)
-- =============================================================================

-- La mesure a-t-elle pu retirer la marge de 5 m sur le bord du contour ?
alter table ndvi_points add column buffered boolean not null default true;

-- Petit état du worker (date du dernier enfilement quotidien).
create table worker_state (
  key    text primary key,
  value  text not null,
  updated_at timestamptz not null default now()
);

-- Nouveau contour : les mesures de l'ancien contour ne valent plus rien.
create or replace function fields_enqueue() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and new.geom is distinct from old.geom then
    delete from ndvi_points where field_id = new.id;
    delete from field_status where field_id = new.id;
  end if;
  if new.geom is not null and (tg_op = 'INSERT' or new.geom is distinct from old.geom or new.sown_on is distinct from old.sown_on) then
    perform enqueue_field(new.id);
  end if;
  return new;
end $$;
