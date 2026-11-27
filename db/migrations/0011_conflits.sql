-- =============================================================================
-- 0011_conflits.sql — modifications concurrentes depuis l'app (ADR-0004, audit M4)
--
-- edited_at / edited_by : dernière modification faite par une personne (app, fusion de doublons).
-- Les imports et le calcul satellite ne les touchent pas (updated_at, lui, bouge à chaque écriture).
-- Un envoi de l'app qui part d'une version plus ancienne, modifiée depuis par quelqu'un d'autre,
-- est refusé (409) : l'agent choisit de remplacer ou de garder la version du serveur.
-- =============================================================================

alter table producers add column edited_at timestamptz, add column edited_by uuid references users(id) on delete set null;
alter table fields add column edited_at timestamptz, add column edited_by uuid references users(id) on delete set null;
