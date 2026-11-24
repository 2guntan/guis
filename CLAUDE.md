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

## Agent skills

### Issue tracker

Issues et specs en GitHub Issues sur `2guntan/guis`. See `docs/agents/issue-tracker.md`.

### Triage labels

Les cinq étiquettes par défaut (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context : un `CONTEXT.md` et `docs/adr/` à la racine. See `docs/agents/domain.md`.
