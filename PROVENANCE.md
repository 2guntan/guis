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
