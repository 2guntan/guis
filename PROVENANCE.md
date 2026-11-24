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
| `apps/web/tailwind.config.ts`, `app/globals.css` | `reference/fieldproof/apps/web/` (mêmes noms) | `57ba3a7` | 23/11/2026 | Jetons remplacés par ceux de `docs/design/SPECS.md` (24/11/2026). |
| `apps/web/next.config.mjs` | `reference/fieldproof/apps/web/next.config.ts` | `57ba3a7` | 23/11/2026 | En `.mjs` (lu sans TypeScript en production) ; en-têtes du lien sécurisé et `distDir` Netlify retirés. |
| `apps/web/lib/utils.ts`, `lib/format.ts`, `lib/map.ts` | `reference/fieldproof/apps/web/lib/` (mêmes noms) | `57ba3a7` | 23/11/2026 | Aucune. |
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
| `apps/web/components/map/ParcelsMap.tsx`, `ParcelsMapCanvas.tsx` | `reference/fieldproof/apps/web/components/map/` | `57ba3a7` | 23/11/2026 | Rampe NDVI de la direction B (remplissage, contour pointillé sans statut), anneau jaune des champs à vérifier, sommets et marge de 5 m sur la fiche, clic vers la fiche, centre par défaut sur les Niayes. |
| `apps/web/components/dashboard/FilterBar.tsx` | `reference/fieldproof/apps/web/components/superviseur/FilterBar.tsx` | `57ba3a7` | 23/11/2026 | Refaite pour la direction B : filtres configurables (champs ou producteurs), case « À vérifier seulement (N) », compteur. |
| `apps/web/components/StatusBadge.tsx` | `reference/fieldproof/apps/web/components/StatusBadge.tsx` | `57ba3a7` | 23/11/2026 | Refait pour la direction B : carré de couleur et mot (`StatusMark`, `StatusPill`), étiquettes (`Tag`). |
| `apps/web/app/login/page.tsx`, `app/deconnexion/route.ts`, `app/(tableau)/layout.tsx` | `reference/fieldproof/apps/web/app/login/page.tsx`, `app/deconnexion/route.ts`, `app/superviseur/layout.tsx` | `57ba3a7` | 23/11/2026 | Supabase remplacé par la session Guis (cookie HTTP-only, formulaire HTML, redirections relatives) ; un seul rôle « admin » ; textes Guis. Le `middleware.ts` de Fieldproof n'est pas repris : la mise en page du tableau de bord vérifie la session. |
| `workers/sat/sat/scenes.py` | `reference/fieldproof/workers/sat/sat/retro.py` (`scene_ndvi`, `select_items`, `_offset`, `square`, accès STAC, `GDAL_ENV`) | `57ba3a7` | 23/11/2026 | Fenêtre semis − 15 j → aujourd'hui, une scène par jour, dates déjà mesurées sautées ; marge intérieure de 5 m (abandonnée si aucun pixel) ; pixels et marge rendus avec la mesure. Saisons, verdict et radar non repris. |
| `workers/sat/sat/main.py` | `reference/fieldproof/workers/sat/sat/main.py` | `57ba3a7` | 23/11/2026 | psycopg au lieu de PostgREST ; un travail = un champ ; enfilement quotidien ; écriture de `ndvi_points` et `field_status`. |
| `workers/sat/Dockerfile`, `requirements.txt` | `reference/fieldproof/workers/sat/` | `57ba3a7` | 23/11/2026 | `httpx` et `pyproj` remplacés par `psycopg`. |
| `apps/web/components/dashboard/NdviChart.tsx` | `reference/fieldproof/apps/web/components/superviseur/NdviChart.tsx` | `57ba3a7` | 23/11/2026 | Saisons et radar retirés ; axe en jours depuis le semis, plage attendue de la pomme de terre, repères Semis et Aujourd'hui. |
| `apps/agent/assets/fonts/*.ttf` (et `apps/web/app/fonts/*.woff2`) | Google Fonts (`github.com/google/fonts`, `ofl/fraunces`, `ofl/geist`) | `main` | 24/11/2026 | Sous-ensemble latin (pyftsubset) ; instances statiques Fraunces 600 et Geist 400/500/600 pour Flutter (fontTools instancer). Licence OFL jointe (`OFL-*.txt`). |
