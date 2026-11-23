# `workers` — traitements Fieldproof (ADR-0005)

Deux conteneurs Docker portables, sans état, qui consomment la table de travaux `core.jobs`
(`db/migrations/0003_core_jobs.sql`) avec la clé `service_role`. Ils n'écrivent en base que par les RPC
du contrat (`dossier.*`, `watch.*`, `core.*`) et dans le bucket privé `documents`.

| Worker | Dossier | Langage | Travaux | Fait |
|---|---|---|---|---|
| **worker-docs** | `workers/docs` | Node 22 + TypeScript (exécuté par `--experimental-strip-types`, sans compilation) | `send_packages` | rend les paquets, les dépose dans Storage, envoie le mail du lien sécurisé |
| **worker-sat** | `workers/sat` | Python 3.12 | `retro_analysis` | analyse rétroactive Sentinel-2, complétée par le radar Sentinel-1, d'une parcelle (3 dernières saisons) |

## Flux

```
superviseur ── dossier.send_file ──► core.jobs « send_packages » {sending_id, file_id, link_token}
agent ── save_draft (contour valide) ──► identity.parcel.geometry_recorded ──► core.jobs « retro_analysis » {aggregate_id = parcelle}

worker-sat  : claim_jobs → watch.start_retro → Planetary Computer (STAC + COG) → watch.finish_retro → complete_job
worker-docs : claim_jobs → dossier.worker_sending + watch.latest_retro
              → par paquet : formulaire prêteur, fiche Fieldproof, annexe structurée (xlsx + json), pièces
                → Storage packages/<file_id>/<package_id>/<nom> → attach_package_document → set_package_generation('ready')
              → mail (Resend, ou journal seul) → set_sending_mail → complete_job
```

Échec : `fail_job` rejoue après 1, 4, 9, 16 min (5 tentatives), `fail_job(…, true)` pour une erreur
définitive (envoi introuvable). Un travail bloqué (worker arrêté net) est repris après 15 min par
`claim_jobs`. Le jeton du lien n'existe en clair que dans le payload du travail ; il est effacé quand
le travail se termine (0007).

## worker-docs

Contenu d'un paquet (`packages/<file_id>/<package_id>/`) :

| Fichier | `kind` | Libellé |
|---|---|---|
| `01-formulaire-<prêteur>-<paquet>.pdf` | `lender_form` | Formulaire <prêteur> pré-rempli |
| `02-fiche-fieldproof-<réf>.pdf` | `fieldproof_sheet` | Fiche Fieldproof (2 pages : client, exploitation, carte à l'échelle, analyse rétroactive, photos géolocalisées, consentement, attestation) |
| `03-annexe-structuree-<réf>.xlsx` / `.json` | `structured_annex` | Annexe structurée, une ligne par champ ; le JSON (`fieldproof.annexe/v1`) est le format de la future API |
| `04-piece-<type>-<id>.<ext>` | `scanned_piece` | Pièces du dossier utiles au paquet (CNI, photos, justificatif, signature et photo du consentement), copiées côté serveur |

- **Formulaire du prêteur** (`src/render/forms.ts`, ADR-0006) : interface `LenderFormAdapter`, choisie par
  `config.templates.<paquet>.engine`. `pdf-lib` remplit un PDF à champs du prêteur selon
  `config.mapping.<paquet>` = `[{ field, source, transform? }]` (`source` = clé de champ de
  `src/render/fields.ts`, ex. `client.last_name` ; `transform` = `upper`, `date_fr`, `digits`,
  `checked_if:<valeur>`). `carbone` est réservé (licence à valider). Sans modèle — cas actuel de PAMECAS —
  un **formulaire provisoire** est généré, marqué « Formulaire provisoire — modèle officiel du prêteur en attente ».
- **Analyse rétroactive** : si l'analyse d'une parcelle est encore en cours, le rendu est reporté
  (`core.defer_job`, sans consommer d'essai) jusqu'à `RETRO_WAIT_ATTEMPTS` fois toutes les `RETRO_WAIT_SECONDS`
  (3 × 120 s). Si l'analyse finit plus tard, l'événement `watch.retro_analysis.completed` enfile
  `refresh_sheet` : la fiche des paquets déjà prêts est régénérée au même chemin.
- **Échec de génération** : `dossier.package.generation_failed` est émis, le superviseur voit le paquet en échec
  et clique « Relancer la génération » (`dossier.retry_generation`), qui relance le travail d'origine
  (le jeton du lien y est conservé tant que le travail n'a pas réussi, effacé à la révocation).
- **Mail** : lien `${APP_URL}/l/<jeton>`, objet « Fieldproof — dossier <réf> pour la caisse <caisse> »,
  bouton « Ouvrir le dossier sécurisé », date d'expiration. Avec `RESEND_API_KEY` : envoi Resend
  (clé d'idempotence = envoi) → `mail_status = 'sent'` ; sinon `logged_only`.
- **Rejouable** : chemins déterministes en upsert, `attach_package_document` est un upsert, un paquet
  `ready` n'est pas régénéré, un mail parti n'est pas renvoyé.

Variables : `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `APP_URL` (défaut `https://fieldproof-sn.netlify.app`),
`WORKER_ID`, facultatives `RESEND_API_KEY`, `MAIL_FROM`, `MAIL_REPLY_TO`, `WORKER_INTERVAL_MS` (5000),
`WORKER_BATCH_SIZE` (3), `DOCUMENTS_BUCKET` (`documents`), `RETRO_WAIT_ATTEMPTS` (3), `RETRO_WAIT_SECONDS` (120). Voir `docs/.env.local.example`.

## worker-sat

`sat/retro.py` documente l'heuristique. En bref : catalogue STAC Microsoft Planetary Computer
(`sentinel-2-l2a`, anonyme, URLs signées), filtre nuages ≤ 80 % à la tuile, une scène par quinzaine et par
saison (≤ 40 au total) ; lectures fenêtrées B04/B08/SCL sur les COG, contour reprojeté dans le CRS de
l'image ; nuages et ombres masqués par SCL (on garde 4 et 5) ; décalage -1000 des bases ≥ 04.00 appliqué.
Saisons : hivernage (1/06–30/11), contre-saison (1/12–31/05) ; les 3 dernières terminées. Saison cultivée
si NDVI max ≥ 0,35, montée ≥ 0,15 au-dessus de la ligne de base (20e centile) ET au-dessus d'une valeur
antérieure de la saison (sinon végétation restante de la saison précédente) ; « incertaine » avec moins de
3 scènes claires. Verdict fondé sur l'hivernage : hivernage cultivé et contre-saisons vides = « cultivée »
(culture pluviale) ; « non cultivée » seulement si un hivernage est observé sans culture, sinon « incertaine ».
Radar (`sat/radar.py`, ADR-0010, option A) : `sentinel-1-rtc`, une seule géométrie d'acquisition (orbite la
plus fréquente), VV/VH moyens sur le contour en dB. Il tranche les saisons « incertaines » en optique :
cultivée si l'amplitude VH (90e - 10e centile) ≥ 2,5 dB et le pic ≥ -17 dB, au moins 5 passages (le radar ne
peut que confirmer une culture, jamais déclarer seul une saison non cultivée) ; mise en eau
(VV ≤ -17 dB puis VH qui remonte) signalée comme riz de bas-fond probable. Radar illisible : l'analyse
optique reste publiée. Environ 50 s par parcelle sur Railway (≈ 80 passages radar sur 3 saisons).
Tests sans réseau : `cd workers/sat && .venv/bin/python -m unittest discover -s tests`.

Variables : `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `WORKER_ID`, facultatives `WORKER_INTERVAL_S` (5),
`WORKER_BATCH_SIZE` (2), `SAT_MAX_SCENES` (40), `SAT_MAX_TILE_CLOUD` (80), `SAT_READ_THREADS` (4), `STAC_URL`,
`SAT_RADAR` (1 ; 0 coupe le radar), `SAT_MAX_RADAR_PASSES` (80), seuils `SAT_S1_MIN_RANGE_DB` (2.5),
`SAT_S1_MIN_PEAK_DB` (-17), `SAT_S1_PERMANENT_FLOOR_DB` (-15), `SAT_S1_FLOOD_VV_DB` (-17).

## Lancer en local

```bash
# secrets : copier depuis le .env.local de la racine (jamais commités, ignorés par git)
cd workers/docs && npm install
npm run dev            # boucle ; `npm run once` = une seule passe
npm run typecheck

cd ../sat && uv venv -p 3.12 .venv && uv pip install -p .venv/bin/python -r requirements.txt
(set -a; . ./.env.local; set +a; .venv/bin/python -m sat.main)      # --once pour une passe
.venv/bin/python -m sat.retro 14.80 -17.25 [côté_m]                  # analyse d'un carré, sans base
```

Outils de test (worker-docs, `scripts/`) :

- `sandbox-dossier.ts [ziguinchor|niayes]` crée un dossier complet dans le bac à sable FIELDPROOF-QA
  (agent.demo → pièces, consentement, soumission ; superviseur.demo → envoi). Les sessions des comptes de
  démo sont ouvertes par lien magique généré avec `service_role` : aucun mot de passe lu ni modifié.
- `preview.ts <sending_id> <dossier>` rend tous les documents d'un envoi en local, sans rien écrire.

## Déployer (Railway)

Projet Railway **fieldproof-workers**, services **worker-docs** et **worker-sat**, construits depuis les
`Dockerfile` (aucun domaine public : ce sont des workers sans port).

```bash
cd workers
railway link                      # projet fieldproof-workers
railway up ./docs --path-as-root --service worker-docs --detach
railway up ./sat  --path-as-root --service worker-sat  --detach
railway logs --service worker-docs     # ou --build pour la construction
```

Les secrets se posent sans jamais apparaître dans une commande :

```bash
grep -E '^SUPABASE_SERVICE_ROLE_KEY=' ../.env.local | cut -d= -f2- | tr -d '\n' \
  | railway variable set SUPABASE_SERVICE_ROLE_KEY --stdin --service worker-docs --skip-deploys
```

Une seule instance par service suffit au pilote ; plusieurs instances sont possibles (`claim_jobs` verrouille
avec `FOR UPDATE SKIP LOCKED`), à condition de leur donner des `WORKER_ID` distincts. Arrêt : SIGTERM →
le travail en cours se termine, rien de nouveau n'est réclamé. L'image tourne à l'identique sur un VPS
(`docker build` + `docker run --env-file`), ADR-0004.
