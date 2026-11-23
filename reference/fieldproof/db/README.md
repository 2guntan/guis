# `db` — schéma Fieldproof

Migrations numérotées dans `migrations/`, un schéma Postgres par contexte. Postgres standard (ADR-0004).

| Migration | Contexte | Statut |
|---|---|---|
| `0000_core.sql` | `core` : organisations, unités (siège, caisse, équipe), rattachements, rôles (`platform_admin`, `org_admin`, `field_agent`, `field_supervisor`), axes RLS, **bac à sable**, **événements de domaine**, référentiel géo. Copié d'Agriva | testé, appliqué le 20/11/2026 |
| `0001_identity.sql` | `identity` : client (personne physique au pilote), exploitation, parcelle PostGIS (surface, périmètre, validité calculés ; motif d'invalidité), événement `identity.parcel.geometry_recorded`. Adapté d'Agriva 0001 | testé, appliqué le 20/11 |
| `0002_geo_senegal.sql` | 14 régions, 118 communes et 868 villages (noms SOLIR), communes des Niayes à compléter | appliqué le 20/11 |
| `0003_core_jobs.sql` | table de travaux des workers (ADR-0005) : routes événement → travail, `claim_jobs` (SKIP LOCKED, reprise après 15 min), `complete_job`, `fail_job` (délai croissant, échec définitif) | testé, appliqué le 20/11 |
| `0004_dossier.sql` | Module Dossier : configuration prêteur, caisses et zones, dossier client, pièces versionnées, consentement par finalité, **complétude** en base, soumission / renvoi / envoi par commandes horodatées, paquets, **lien sécurisé** (jeton haché, expiration, révocation, journal), **retour du prêteur** | testé, appliqué le 20/11 |
| `0005_watch.sql` | Watch tranche 1 : analyse rétroactive par parcelle (travail `retro_analysis` pour worker-sat), vue `latest_retro` | testé, appliqué le 20/11 |
| `0006_storage.sql` | bucket privé `documents` : `files/<dossier>/<pièce>` (dépôt agent), `packages/<dossier>/<paquet>/…` (worker) | testé, appliqué le 20/11 |
| `0007_sending_job_token.sql` | le jeton du lien passe par le travail d'envoi (service_role seul), jamais par les événements ; effacé à la fin | testé, appliqué le 20/11 |
| `0008_service_role_execute.sql` | `lock_down_functions` laisse l'exécution à `service_role` (déclencheurs des workers) | testé, appliqué le 20/11 |
| `0009_hardening.sql` | corrections de l'audit Supabase : RLS partout, search_path figé, policies optimisées | testé, appliqué le 20/11 |
| `0010_dossier_replays.sql` | rejeux idempotents (pièce, consentement, soumission), parcelles refusées sans exploitation nommée, configuration prêteur cloisonnée bac à sable | testé, appliqué le 20/11 |
| `0011_job_defer_sheet_refresh.sql` | `core.defer_job` (report sans consommer d'essai), travail `refresh_sheet` après une analyse rétroactive tardive, `dossier.retry_generation` (superviseur) et événement `dossier.package.generation_failed` ; jeton gardé dans un travail échoué, effacé à la révocation | testé, appliqué le 20/11 |
| `0012_retro_radar.sql` | analyse rétroactive : colonne `radar_series` (radar Sentinel-1), `finish_retro` conserve la série radar et le fournisseur, vue `latest_retro` recréée (ADR-0010) | testé |

Chaîne locale : `smoke_core` (69) + `smoke_dossier` (115) = **184 assertions vertes**.

## Projet Supabase

Projet `fieldproof` (réf. `rxoddvvdjxmbvjekjedq`, eu-west-1, Postgres 17). Schémas exposés à l'API : `public`, `graphql_public`, `core`, `identity`, `dossier`, `watch`.

Appliquer une migration (CLI Supabase connecté, sans mot de passe dans le dépôt) : tester d'abord en local (`db/tests/run_local.sh`), puis l'essayer sur le projet dans une transaction annulée (`begin; … rollback;`), puis l'appliquer dans une transaction :

```bash
supabase link --project-ref rxoddvvdjxmbvjekjedq --workdir <dossier de travail hors dépôt>
supabase db query --linked --workdir <dossier> -f <fichier begin…commit>.sql
```

Comptes de démonstration (bac à sable) : `node --env-file=.env.local scripts/create_demo_accounts.mjs` ; identifiants dans `.demo-accounts.local.md` (hors git).

Audit Supabase restant (assumé) : RPC `security definer` exposées (c'est le modèle d'écriture), PostGIS et citext dans `public`, `spatial_ref_sys` et `st_estimatedextent` appartenant à `supabase_admin` (non modifiables sans déplacer PostGIS), protection des mots de passe divulgués (réglage Auth à activer).

## Règle bac à sable

`core.organizations.is_sandbox = true` marque le bac à sable (`FIELDPROOF-QA`). Toute ligne créée par une organisation bac à sable n'est visible que de ses membres et des `platform_admin` (`core.sandbox_visible()`), et la vue `core.production_organizations` l'exclut des KPI. Les comptes de test sont membres de `FIELDPROOF-QA`, jamais d'IBRIZ ni de PAMECAS.

## Tester en local

Sur macOS avec Homebrew (`postgresql@17`), un cluster jetable :

```bash
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH" LC_ALL=C LANG=C
initdb -D ~/.fieldproof-pg17 -U postgres --encoding=UTF8 --locale=C     # une fois
pg_ctl -D ~/.fieldproof-pg17 -o "-p 5499 -k /tmp" -l /tmp/fieldproof-pg.log start
PGHOST=127.0.0.1 PGPORT=5499 PGUSER=postgres db/tests/run_local.sh
```

`run_local.sh` détruit et recrée la base `fieldproof_test`, crée les stubs Supabase (`auth.users`, `auth.uid()`, rôles), applique les migrations, charge `_harness.sql` et joue la chaîne de tests : `PASS (n assertions)` par fichier, puis `ALL GREEN`. `LC_ALL=C` est requis sur macOS.

Assertions du harnais (schéma `test`, jamais déployé) : `test.eq`, `test.ok`, `test.fails(label, sql, fragment)`, `test.count` ; `test.login(uuid)` / `test.anon()` / `test.logout()` changent de rôle.

## Événements de domaine

- Un seul canal : `core.domain_events`, append-only. Une seule fonction d'émission : `core.emit_event(...)`, appelée dans la transaction de l'écriture métier ; jamais exécutable par un client.
- Tout type est déclaré dans `core.event_types` par la migration du contexte émetteur ; nommage `<contexte>.<agrégat>.<fait_passé>`.
- Workers (ADR-0005) : `core.next_events(consumer, limit)` puis `core.ack_events(consumer, last_id)` ; chaque consommateur est enregistré dans `core.event_consumers` par la migration qui en a besoin.

## Conventions

- `core.lock_down_functions('<schéma>')` en fin de chaque migration, puis grants explicites des RPC.
- Vues toujours `with (security_invoker = true)`.
- Jamais un `IN ('IBRIZ','PAMECAS')` : on teste `kind` ou une capacité.
