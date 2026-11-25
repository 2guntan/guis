-- =============================================================================
-- 0008_coordinateur.sql — profil coordinateur (spec 2guntan/guis#24, ticket #25)
--
-- Le coordinateur (coopérative) consulte toutes les données sur le tableau de bord, sans les
-- modifier ni les exporter, et gère l'attribution des communes aux agents. Il voit tous les
-- producteurs, comme l'admin.
-- =============================================================================

alter table users drop constraint users_role_check;
alter table users add constraint users_role_check check (role in ('admin', 'coordinator', 'agent'));

create or replace function producer_visible(p_user uuid, p_producer uuid) returns boolean language sql stable as $$
  select exists (select 1 from users u where u.id = p_user and u.role in ('admin', 'coordinator'))
      or exists (
        select 1 from producers p
         where p.id = p_producer
           and (p.created_by = p_user
                or p.commune in (select commune from agent_communes where user_id = p_user)));
$$;
