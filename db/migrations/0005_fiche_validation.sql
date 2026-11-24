-- =============================================================================
-- 0005_fiche_validation.sql — import de la fiche de visite-validation (ticket 10)
--
-- Voir CONTEXT.md : la surface déclarée et la surface validée sont celles du
-- producteur (fiche de la coopérative), distinctes de la surface déclarée du
-- champ et de la surface mesurée. La commune est celle de l'équipe de visite.
-- =============================================================================

create table communes (name text primary key);

alter table producers
  add column commune text,
  add column area_declared_ha numeric(10, 4) check (area_declared_ha is null or area_declared_ha > 0),
  add column area_validated_ha numeric(10, 4) check (area_validated_ha is null or area_validated_ha >= 0),
  -- Clé figée calculée sur les valeurs lues dans la fiche (commune, téléphone, nom) :
  -- elle retrouve le producteur au réimport même après correction sur le terrain.
  add column import_key text;

create unique index producers_import_key_uq on producers (import_key) where import_key is not null;
create index producers_commune_idx on producers (commune);
