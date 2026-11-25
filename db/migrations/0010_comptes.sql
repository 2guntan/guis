-- =============================================================================
-- 0010_comptes.sql — gestion des comptes par l'admin (tickets #28 et #29, spec #24)
--
-- - users.last_sync_at : dernière synchronisation de l'app (dernier bootstrap reçu) ;
-- - account_events : journal des actions sur les comptes, sans aucun secret.
-- =============================================================================

alter table users add column last_sync_at timestamptz;

create table account_events (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  actor_id   uuid references users(id) on delete set null,
  target_id  uuid references users(id) on delete set null,
  action     text not null check (action in ('create', 'update', 'role', 'reset', 'deactivate', 'reactivate', 'delete')),
  detail     text
);
create index account_events_target_idx on account_events (target_id, at desc);
