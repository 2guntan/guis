-- =============================================================================
-- 0007_doublons.sql — doublon possible signalé à l'admin (ticket 13)
--
-- Un producteur créé dans l'app avec un téléphone déjà présent est marqué
-- « doublon possible » ; l'admin tranche : deux personnes, ou fusion.
-- =============================================================================

-- Producteurs existants qui partagent son téléphone (null : pas de doublon possible).
alter table producers add column possible_duplicate_of uuid[];
create index producers_possible_duplicate_idx on producers ((possible_duplicate_of is not null)) where possible_duplicate_of is not null;

-- Couples tranchés « deux personnes » (a < b) : jamais remarqués à nouveau.
create table producer_distinct (
  a uuid not null,
  b uuid not null,
  decided_by uuid references users(id),
  decided_at timestamptz not null default now(),
  primary key (a, b),
  check (a < b)
);

-- Fusions : un téléphone qui renvoie encore l'ancien identifiant est redirigé vers le producteur gardé.
create table producer_merges (
  old_id     uuid primary key,
  new_id     uuid not null references producers(id) on delete cascade,
  merged_by  uuid references users(id),
  merged_at  timestamptz not null default now()
);

-- Recalcule le marquage d'un producteur saisi dans l'app.
create or replace function flag_duplicates(p_id uuid) returns void language sql as $$
  update producers p
     set possible_duplicate_of = (
       select array_agg(o.id order by o.created_at)
         from producers o
        where o.phone = p.phone and o.id <> p.id
          and not exists (select 1 from producer_distinct d where d.a = least(o.id, p.id) and d.b = greatest(o.id, p.id)))
   where p.id = p_id and p.source = 'app';
$$;
