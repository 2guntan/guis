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

## Import de la fiche de visite-validation

La fiche Excel de la coopérative (une feuille par commune) et la table de correspondance des villages restent **hors du dépôt**. On les copie sur le serveur, on lance d'abord une **simulation** (rien n'est écrit), on relit le compte rendu, puis on importe.

```bash
docker compose cp fiche.xlsx web:/tmp/fiche.xlsx
docker compose cp villages-correspondance.xlsx web:/tmp/villages.xlsx
docker compose exec web node scripts/import-fiche-validation.mjs /tmp/fiche.xlsx --villages /tmp/villages.xlsx --simulation
```

```bash
docker compose exec web node scripts/import-fiche-validation.mjs /tmp/fiche.xlsx --villages /tmp/villages.xlsx
```

- Commune = nom de la feuille. Village = colonne « Village retenu » de la table (colonnes « Village lu » et « Village retenu », classeur ou CSV).
- Écartés : superficie validée nulle **et** remarque « pas de champ », « pas de parcelle », « abandon… » ou « non validé », y compris dans une cellule fusionnée.
- Nom = dernier mot, prénom = le reste ; un seul mot → nom « À COMPLÉTER ». Téléphone invalide → importé sans téléphone.
- Même commune, téléphone et nom deux fois : ressaisie ignorée, ou fusion avec superficies additionnées si les deux lignes ont une superficie validée.
- Aucune semence n'est créée : les remises sont saisies dans l'app.
- Réimport sans risque : seules la commune et les superficies sont mises à jour ; nom, téléphone et village corrigés sur le terrain sont gardés ; rien n'est supprimé.

## Attribution des communes aux agents

Chaque agent ne reçoit sur son téléphone que les producteurs des communes qui lui sont attribuées, plus ceux qu'il a créés ; l'admin reçoit tout ([ADR-0001](docs/adr/0001-agent-voit-ses-producteurs-par-recherche.md)). L'attribution vient d'un fichier gardé hors du dépôt, une ligne par couple commune / agent (exemple fictif : `apps/web/scripts/exemples/communes-agents.csv`).

```bash
docker compose cp communes-agents.xlsx web:/tmp/communes-agents.xlsx
docker compose exec web node scripts/load-attribution.mjs /tmp/communes-agents.xlsx
```

- Une commune peut avoir plusieurs agents, un agent plusieurs communes (même téléphone sur plusieurs lignes).
- L'attribution est remplacée en entier à chaque chargement ; les téléphones la reçoivent à leur synchronisation suivante.
- Un agent inconnu est créé avec un mot de passe initial **affiché une seule fois** : le lui transmettre.
- Un producteur créé par un agent qui n'a qu'une commune est rattaché à cette commune.

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
