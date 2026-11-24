# Déployer Guis depuis une session Claude cloud

Une session Claude cloud ne reçoit pas la configuration privée du Mac et ne peut pas joindre le VPS Guis en SSH sur le port 22. Le déploiement passe donc par le workflow GitHub Actions `deploy-vps.yml`. Chaque nouvelle session Claude attachée à `2guntan/guis` peut le déclencher sans recevoir la clé SSH.

## Configuration unique

Dans les secrets GitHub Actions du dépôt `2guntan/guis`, enregistrer :

| Secret | Valeur |
| --- | --- |
| `GUIS_VPS_HOST` | Hôte ou IP du VPS. |
| `GUIS_VPS_SSH_PRIVATE_KEY` | Clé privée SSH du compte `deploy` sur le VPS. Utiliser une clé dédiée à GitHub Actions. |
| `GUIS_VPS_KNOWN_HOSTS` | Entrée `known_hosts` du VPS, vérifiée depuis une machine qui s'y connecte déjà. |

Ne placer aucune de ces valeurs dans le dépôt, dans `CLAUDE.md`, dans une conversation Claude ou dans les journaux de CI. Le compte `deploy` doit déjà avoir accès à Docker et le dépôt `~/guis` doit être sur `main`, propre, avec un `.env` fonctionnel. Le workflow sauvegarde la base avant de mettre à jour le code et attend que les services Docker soient prêts.

## Depuis Claude Code cloud

Attacher le dépôt `2guntan/guis` à la session, puis demander :

> Déploie la branche `main` de Guis sur le VPS via l'événement GitHub `guis-deploy-vps`. Vérifie la CI, déclenche l'événement, attends le résultat du workflow `deploy-vps.yml` et rapporte le commit déployé. Ne tente pas de connexion SSH depuis cette session.

Si `gh` est disponible dans la session, le déclenchement équivalent utilise l'API REST GitHub :

```bash
gh api --method POST repos/2guntan/guis/dispatches -f event_type=guis-deploy-vps
```

Le jeton GitHub de Claude cloud a le droit d'écriture sur le contenu du dépôt, requis par `repository_dispatch`, mais pas le droit d'écriture sur Actions, requis par `workflow_dispatch`. L'événement `guis-deploy-vps` est limité à ce workflow et GitHub l'exécute depuis `main`. Le déclenchement manuel dans l'interface GitHub Actions reste disponible.

Le workflow n'est utilisable qu'après sa fusion dans `main` et l'enregistrement des trois secrets. Un échec laisse le journal du workflow et la sauvegarde préalable sur le VPS pour diagnostic.
