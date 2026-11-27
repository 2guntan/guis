# Guis

Application de collecte et de suivi satellite des champs : app Android (Flutter), tableau de bord et API (Next.js), PostgreSQL et PostGIS, worker satellite (Python), Caddy, le tout en Docker Compose sur un VPS. Tout est décrit dans `NOTE-CADRAGE.md`.

## Règles du projet

- `reference/fieldproof/` est en **lecture seule** : on copie un fichier ailleurs (`apps/`, `workers/`, `db/`), on l'adapte là, et on ajoute une ligne dans `PROVENANCE.md`.
- Le dépôt est **public** : aucun secret (mot de passe, clé, IP du VPS, clé SSH, keystore) ni donnée réelle de producteur dans git. Les fichiers de la coopérative (`.xlsx`, `.csv`) restent hors du dépôt.
- On vise **le plus simple qui marche**. Textes de l'interface en **français**.
- Ordre de priorité : app de collecte, puis tableau de bord, puis satellite.

## Accès au VPS entre sessions

Avant de redemander l'IP, la clé SSH ou le domaine, exécuter `python3 deploy/doctor.py`. Il lit les variables de la session, puis `~/.config/guis/deploy.env` si ce fichier existe. Sa sortie ne contient ni IP ni clé. `config_complete` signifie seulement que les paramètres sont présents ; vérifier ensuite la connexion SSH avant un déploiement.

Le dépôt public ne contient aucun identifiant d'accès. Les variables transmises à une ancienne session Claude ne sont pas automatiquement disponibles dans une nouvelle session. Si `host` ou `ssh_key` est manquant après le diagnostic, demander uniquement le paramètre manquant ou le chemin vers la configuration privée. Ne jamais copier une clé privée dans le dépôt, un ticket, un journal ou une réponse.

Une session Claude distante ne voit pas le fichier privé du Mac de l'utilisateur : la configuration doit exister **dans l'environnement qui exécute le déploiement**. Ne pas présenter un réglage local d'un autre projet comme un accès vérifié au VPS Guis.

Pour déployer depuis Claude Code cloud, envoyer l'événement GitHub `guis-deploy-vps` décrit dans `docs/DEPLOIEMENT-CLOUD.md`. Il lance le workflow GitHub Actions `deploy-vps.yml`, garde la clé SSH dans les secrets GitHub et fonctionne depuis chaque nouvelle session attachée au dépôt. Le jeton Claude cloud n'a pas le droit de lancer directement `workflow_dispatch`. Ne pas essayer le SSH direct depuis la session cloud.

Le domaine n'est pas un blocage si `GUIS_VPS_HOST` est une IPv4 publique : utiliser l'adresse provisoire `guis.<IP>.sslip.io` prévue par `NOTE-CADRAGE.md` §7. Un domaine propre peut être branché plus tard. Les accès de Fieldproof dans `reference/fieldproof/` ne sont pas ceux de Guis.

## Nouvelle version de l'app agent

Claude s'en charge de bout en bout. Détails pour les humains : `docs/DEPLOIEMENT.md` §4.

1. **Publication automatique.** Un push sur `main` qui touche `apps/agent/**` ou `.github/workflows/apk.yml` lance le workflow `apk`, qui publie la release `apk-N`, où N est le numéro du run et le `versionCode` de l'APK. Il n'y a pas de release si la clé de release ou `GUIS_API_URL` manque (APK « ESSAI-NE-PAS-DISTRIBUER »). Pour forcer une construction : `gh workflow run apk.yml --repo 2guntan/guis --ref main`.
2. **Vérifier la release** avant d'en parler aux agents :
   - `gh release list --repo 2guntan/guis --limit 1` affiche `apk-N`, marquée « Latest » ;
   - télécharger `https://github.com/2guntan/guis/releases/latest/download/guis.apk` et `guis.apk.sha256` dans le scratchpad, puis `shasum -a 256 -c guis.apk.sha256` ;
   - `aapt dump badging` donne `versionCode='N'`, et `apksigner verify --print-certs` donne `CN=Guis, O=Solir, C=SN`. Un autre signataire : ne rien proposer aux agents, prévenir l'utilisateur ;
   - effacer les fichiers téléchargés.
3. **Proposer la version sur le VPS** : `python3 deploy/doctor.py`, puis SSH en `deploy@` avec la configuration privée, dans `~/guis` :
   - sauvegarder : `cp -p .env .env.bak-$(date -u +%Y%m%dT%H%M%S)` ;
   - modifier la ligne existante, sans en ajouter une deuxième : `sed -i 's/^GUIS_LATEST_APP_BUILD=.*/GUIS_LATEST_APP_BUILD=N/' .env` ;
   - `docker compose up -d --wait web`, puis vérifier dans le conteneur la valeur de `GUIS_LATEST_APP_BUILD` et `/api/health` (200) ;
   - `git status --porcelain` doit rester vide, sinon le workflow de déploiement refuse de tourner.
4. **`GUIS_MIN_APP_BUILD`** bloque toutes les versions plus anciennes. Ne le régler que si l'utilisateur le demande explicitement (correctif indispensable). Les saisies non envoyées restent sur le téléphone et partent après la mise à jour.
5. **Ne jamais** afficher les autres lignes du `.env` ni toucher à `GUIS_APK_URL`, qui pointe déjà sur `releases/latest`.
6. **Session cloud** : pas de SSH vers le VPS. Dire à l'utilisateur que l'étape 3 reste à faire depuis le Mac, avec le numéro N.

## Agent skills

### Issue tracker

Issues et specs en GitHub Issues sur `2guntan/guis`. See `docs/agents/issue-tracker.md`.

### Triage labels

Les cinq étiquettes par défaut (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context : un `CONTEXT.md` et `docs/adr/` à la racine. See `docs/agents/domain.md`.
