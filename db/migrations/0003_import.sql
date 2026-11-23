-- =============================================================================
-- 0003_import.sql — producteurs importés du fichier de distribution (ticket 05)
--
-- Un producteur importé n'a pas encore donné son consentement : l'agent le
-- recueille à la première visite. Un producteur saisi dans l'app l'a toujours.
-- =============================================================================

alter table producers alter column consent_at drop not null;
alter table producers add constraint producers_consent_required check (source = 'import' or consent_at is not null);

-- Comparaison des noms sans accents (import).
create extension if not exists unaccent;
