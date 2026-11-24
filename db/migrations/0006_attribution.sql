-- =============================================================================
-- 0006_attribution.sql — attribution des communes aux agents (ticket 11, ADR-0001)
--
-- Un agent ne reçoit que les producteurs des communes qui lui sont attribuées,
-- plus ceux qu'il a créés. Une commune peut avoir plusieurs agents, un agent
-- plusieurs communes. L'admin voit tout.
-- =============================================================================

create table agent_communes (
  user_id  uuid not null references users(id) on delete cascade,
  commune  text not null references communes(name) on update cascade,
  primary key (user_id, commune)
);
create index agent_communes_commune_idx on agent_communes (commune);

-- Producteurs visibles par un compte (admin : tous).
create or replace function producer_visible(p_user uuid, p_producer uuid) returns boolean language sql stable as $$
  select exists (select 1 from users u where u.id = p_user and u.role = 'admin')
      or exists (
        select 1 from producers p
         where p.id = p_producer
           and (p.created_by = p_user
                or p.commune in (select commune from agent_communes where user_id = p_user)));
$$;
