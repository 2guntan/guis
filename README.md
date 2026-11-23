# Guis

**Guis** vient du wolof *gis*, « voir ». C'est une application générique de collecte et de suivi satellite des champs.

Premier usage : relever et suivre les champs de pomme de terre emblavés par les producteurs d'une coopérative partenaire.

- `NOTE-CADRAGE.md` : objectif, périmètre de la V1, données collectées, suivi satellite, plan de mise en œuvre.
- `docs/PROMPT-DEMARRAGE.md` : prompt pour démarrer une session de développement.
- `reference/fieldproof/` : extrait de Fieldproof en lecture seule, dont on copie le code (voir `PROVENANCE.md`).

## Démarrer

```bash
cp .env.example .env        # remplir POSTGRES_PASSWORD et GUIS_DOMAIN
docker compose up -d --build
docker compose exec -it web node scripts/create-user.mjs --phone "77 000 00 01" --name "Prénom Nom" --role admin
```

| Dossier | Contenu |
|---|---|
| `apps/web/` | Tableau de bord et API de l'app Android (Next.js). Voir son README. |
| `db/migrations/` | Schéma PostgreSQL/PostGIS, appliqué au démarrage du conteneur web. |
| `deploy/` | Caddyfile (HTTPS automatique). |
