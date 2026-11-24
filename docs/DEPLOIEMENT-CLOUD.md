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

> Déploie la branche `main` de Guis sur le VPS via le workflow GitHub Actions `deploy-vps.yml`. Vérifie la CI, déclenche le workflow sur `main`, attends son résultat et rapporte le commit déployé. Ne tente pas de connexion SSH depuis cette session.

Si `gh` est disponible dans la session, le déclenchement équivalent utilise l'API REST GitHub :

```bash
gh api --method POST repos/2guntan/guis/actions/workflows/deploy-vps.yml/dispatches -f ref=main
```

Le workflow n'est utilisable qu'après sa fusion dans `main` et l'enregistrement des trois secrets. Un échec laisse le journal du workflow et la sauvegarde préalable sur le VPS pour diagnostic.
