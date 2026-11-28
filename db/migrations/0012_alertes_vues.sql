-- =============================================================================
-- 0012_alertes_vues.sql — une alerte satellite peut être marquée « vue »
--
-- Le compteur « champs à vérifier » ne comptait que les alertes du worker, sans
-- moyen de dire qu'on s'en était occupé. Un admin ou un coordinateur marque
-- maintenant les alertes d'un champ comme vues : elles sortent du compteur et
-- du filtre « À vérifier ». Une alerte est identifiée par son code
-- (`no_emergence`, `ndvi_drop`, …) : un autre code sur le même champ reste
-- ouvert, et une alerte qui disparaît puis revient est de nouveau à vérifier.
-- =============================================================================

create table alert_reviews (
  field_id     uuid not null references fields(id) on delete cascade,
  code         text not null,
  reviewed_by  uuid references users(id) on delete set null,
  reviewed_at  timestamptz not null default now(),
  primary key (field_id, code)
);

-- Alertes encore à vérifier d'un champ : celles du worker, moins celles marquées vues.
create or replace function open_alerts(p_field uuid, p_alerts jsonb) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(a order by n), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p_alerts, '[]'::jsonb)) with ordinality as x(a, n)
   where not exists (select 1 from alert_reviews r where r.field_id = p_field and r.code = a->>'code');
$$;

-- Quand le worker recalcule un champ, une alerte disparue oublie qu'elle avait été vue :
-- si elle revient plus tard, elle est de nouveau à vérifier.
create or replace function alert_reviews_forget() returns trigger language plpgsql as $$
begin
  delete from alert_reviews r
   where r.field_id = new.field_id
     and not exists (select 1 from jsonb_array_elements(new.alerts) a where a->>'code' = r.code);
  return new;
end $$;

create trigger field_status_forget_reviews after insert or update of alerts on field_status
  for each row execute function alert_reviews_forget();
