# Guis

Application de collecte et de suivi satellite des champs : app Android (Flutter), tableau de bord et API (Next.js), PostgreSQL et PostGIS, worker satellite (Python), Caddy, le tout en Docker Compose sur un VPS. Tout est décrit dans `NOTE-CADRAGE.md`.

## Règles du projet

- `reference/fieldproof/` est en **lecture seule** : on copie un fichier ailleurs (`apps/`, `workers/`, `db/`), on l'adapte là, et on ajoute une ligne dans `PROVENANCE.md`.
- Le dépôt est **public** : aucun secret (mot de passe, clé, IP du VPS, clé SSH, keystore) ni donnée réelle de producteur dans git. Les fichiers de la coopérative (`.xlsx`, `.csv`) restent hors du dépôt.
- On vise **le plus simple qui marche**. Textes de l'interface en **français**.
- Ordre de priorité : app de collecte, puis tableau de bord, puis satellite.

## Agent skills

### Issue tracker

Issues et specs en GitHub Issues sur `2guntan/guis`. See `docs/agents/issue-tracker.md`.

### Triage labels

Les cinq étiquettes par défaut (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context : un `CONTEXT.md` et `docs/adr/` à la racine. See `docs/agents/domain.md`.
