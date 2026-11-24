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
| `workers/sat/` | Worker satellite (Python) : NDVI Sentinel-2 depuis le semis, statut et alertes. Voir son README. |
| `apps/agent/` | App Android (Flutter). Voir son README. |
| `deploy/` | Caddyfile (HTTPS automatique), préparation du VPS et diagnostic d'accès sans affichage de secrets. |
| `docs/DEPLOIEMENT.md` | Mise en ligne, mises à jour, sauvegardes, APK. |

Pour reprendre un déploiement dans une nouvelle session, lancer `python3 deploy/doctor.py` avant de redemander les accès. La configuration persistante reste hors du dépôt ; voir [docs/DEPLOIEMENT.md](docs/DEPLOIEMENT.md#accès-conservé-hors-du-dépôt). Un domaine propre est facultatif au départ.

## Listes et import des distributions de semences

Les fichiers de la coopérative restent **hors du dépôt** : on les copie sur le serveur, puis on les passe au conteneur web. Les exemples fictifs de `apps/web/scripts/exemples/` montrent le format attendu.

```bash
docker compose cp villages.csv web:/tmp/villages.csv
docker compose cp varietes.csv web:/tmp/varietes.csv
docker compose exec web node scripts/load-lists.mjs --villages /tmp/villages.csv --varietes /tmp/varietes.csv
```

```bash
docker compose cp distributions.csv web:/tmp/distributions.csv
docker compose exec web node scripts/import-distributions.mjs /tmp/distributions.csv
```

- Listes : CSV à une colonne `nom`.
- Distributions : colonnes `nom ; prenom ; telephone ; carte_membre ; sexe ; village ; variete ; quantite_kg ; date_reception` (en-tête obligatoire, accents et casse indifférents, séparateur `;` ou `,`, dates `JJ/MM/AAAA` ou `AAAA-MM-JJ`). Une ligne par semence reçue.
- Un producteur est reconnu par sa carte de membre, sinon par son téléphone et son nom. Relancer l'import ne crée pas de doublon.
- Un producteur importé n'a pas encore donné son consentement : l'app l'affiche « Consentement à recueillir » et l'agent le coche à la première visite.
