# PROVENANCE

Ce fichier recense chaque fichier repris d'un autre projet. Pour chacun, on note le chemin source, le commit source, la date et les modifications faites.

## Copie de référence

| Destination | Source | Commit | Date | Modifications |
|---|---|---|---|---|
| `reference/fieldproof/**` (99 fichiers, voir `reference/fieldproof/README.md`) | Fieldproof, mêmes chemins | `57ba3a7` | 23/11/2026 | Aucune : copie brute en lecture seule, faite par `git archive` (seuls les fichiers suivis par git, donc sans `.env` ni `env.json`). |

## Fichiers repris dans Guis

À compléter à chaque copie depuis `reference/fieldproof/`.

| Destination | Source | Commit | Date | Modifications |
|---|---|---|---|---|
| `apps/web/tsconfig.json`, `postcss.config.js`, `.eslintrc.json`, `.gitignore` | `reference/fieldproof/apps/web/` (mêmes noms) | `57ba3a7` | 23/11/2026 | Aucune. |
| `apps/web/tailwind.config.ts`, `app/globals.css` | `reference/fieldproof/apps/web/` (mêmes noms) | `57ba3a7` | 23/11/2026 | Aucune (palette et composants CSS Fieldproof). |
| `apps/web/next.config.mjs` | `reference/fieldproof/apps/web/next.config.ts` | `57ba3a7` | 23/11/2026 | En `.mjs` (lu sans TypeScript en production) ; en-têtes du lien sécurisé et `distDir` Netlify retirés. |
| `apps/web/lib/utils.ts`, `lib/format.ts`, `lib/map.ts` | `reference/fieldproof/apps/web/lib/` (mêmes noms) | `57ba3a7` | 23/11/2026 | Aucune. |
| `apps/web/components/ui/button.tsx` | `reference/fieldproof/apps/web/components/ui/button.tsx` | `57ba3a7` | 23/11/2026 | Aucune. |
| `db/migrations/0002_satellite.sql` (table `jobs`, `claim_jobs`, `complete_job`, `fail_job`) | `reference/fieldproof/db/migrations/0003_core_jobs.sql` | `57ba3a7` | 23/11/2026 | Simplifiée : schéma public, un seul type de travail par champ, pas d'événements de domaine, de routes ni de RLS. |
| `apps/agent/android/` (`build.gradle.kts`, `app/build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`, `app/src/*/AndroidManifest.xml`, `MainActivity.kt`) | `reference/fieldproof/apps/agent/android/` | `57ba3a7` | 23/11/2026 | Paquet `com.fieldproof.agent` → `com.guis.app`, libellé « Guis », variable de signature `GUIS_SIGNING`, mémoire Gradle réduite à 4 Go. Le reste (gradlew, ressources) vient de `flutter create`. |
| `apps/agent/analysis_options.yaml` | `reference/fieldproof/apps/agent/analysis_options.yaml` | `57ba3a7` | 23/11/2026 | Largeur de ligne 140 pour `dart format`. |
| `apps/agent/lib/core/json_store.dart` | `reference/fieldproof/apps/agent/lib/core/json_store.dart` | `57ba3a7` | 23/11/2026 | Aucune. |
| `apps/agent/lib/core/config.dart` | `reference/fieldproof/apps/agent/lib/core/config.dart` | `57ba3a7` | 23/11/2026 | `SUPABASE_URL` et `SUPABASE_ANON_KEY` remplacés par `API_URL`. |
| `apps/agent/lib/core/sync/outbox.dart` | `reference/fieldproof/apps/agent/lib/core/sync/outbox.dart` | `57ba3a7` | 23/11/2026 | Requête HTTP (`method`, `path`) au lieu d'une RPC Supabase ; sujet = producteur ; remplacement par ressource en gardant les pièces jointes ; classement des erreurs par code HTTP (déplacé dans `core/api.dart`). |
| `apps/agent/test/outbox_test.dart` | `reference/fieldproof/apps/agent/test/outbox_test.dart` | `57ba3a7` | 23/11/2026 | Adapté à l'outbox HTTP ; cas Postgrest remplacés par des codes HTTP ; test du remplacement avec photos ajouté. |
| `apps/agent/lib/features/auth/sign_in_page.dart` | `reference/fieldproof/apps/agent/lib/features/auth/sign_in_page.dart` | `57ba3a7` | 23/11/2026 | Téléphone au lieu de l'adresse électronique ; API Guis au lieu de Supabase ; textes et logo Guis. |
| `apps/agent/lib/ui/theme.dart` | `reference/fieldproof/apps/agent/lib/ui/theme.dart` | `57ba3a7` | 23/11/2026 | `FpColors` → `GuisColors`, `fieldproofTheme` → `guisTheme` ; statuts de dossier et montants FCFA retirés ; `StateChip` ajouté. |
| `apps/agent/lib/main.dart` | `reference/fieldproof/apps/agent/lib/main.dart` | `57ba3a7` | 23/11/2026 | Supabase et contrôle du rôle retirés ; services Guis. |
| `apps/agent/test/screens_test.dart` | `reference/fieldproof/apps/agent/test/screens_test.dart` | `57ba3a7` | 23/11/2026 | Démarche seulement (téléphone 360 × 640, sans débordement) ; écrans et parcours Guis. |
| `apps/agent/lib/core/model/geo.dart` | `reference/fieldproof/apps/agent/lib/core/model/geo.dart` | `57ba3a7` | 23/11/2026 | Commentaires : règles du serveur Guis au lieu des fonctions de la base Fieldproof. |
| `apps/agent/test/geo_test.dart` | `reference/fieldproof/apps/agent/test/geo_test.dart` | `57ba3a7` | 23/11/2026 | Nom du paquet. |
| `apps/agent/lib/features/fields/field_walk_page.dart` | `reference/fieldproof/apps/agent/lib/features/editor/parcel_walk_page.dart` | `57ba3a7` | 23/11/2026 | Renommée `FieldWalkPage`, couleurs Guis, carte centrée sur les Niayes, agent utilisateur `com.guis.app`. |
| `apps/agent/lib/core/photos.dart` | `reference/fieldproof/apps/agent/lib/core/photos.dart` | `57ba3a7` | 23/11/2026 | `takeDocumentPhoto` → `takePhoto` (renvoie une `LocalPhoto` avec ses en-têtes de dépôt, sans modèle de dossier) ; texte « Guis ». |
