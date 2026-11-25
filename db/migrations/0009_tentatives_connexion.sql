-- =============================================================================
-- 0009_tentatives_connexion.sql — blocage après 5 essais (ticket #27, ADR-0003)
--
-- Échecs de connexion consécutifs par téléphone normalisé, qu'un compte existe ou non.
-- Après 5 échecs, toute tentative est refusée jusqu'à blocked_until (15 minutes).
-- =============================================================================

create table login_attempts (
  phone          text primary key,
  failures       integer not null default 0,
  blocked_until  timestamptz,
  updated_at     timestamptz not null default now()
);
