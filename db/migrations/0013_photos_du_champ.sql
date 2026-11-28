-- =============================================================================
-- Photos du champ : de zéro à cinq par champ (CONTEXT.md), au lieu d'une seule.
-- L'ordre affiché est celui de la prise de vue (photos.taken_at), pas celui de la liste.
-- La photo d'un producteur reste unique (producers.photo_id).
-- =============================================================================

alter table fields add column photo_ids uuid[] not null default '{}'
  constraint fields_photo_ids_max check (cardinality(photo_ids) <= 5);

update fields set photo_ids = array[photo_id] where photo_id is not null;

alter table fields drop column photo_id;
