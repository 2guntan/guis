# Déploiement sur le VPS

Un seul serveur, un VPS Contabo Cloud VPS 4 sous Ubuntu 24.04, avec Docker Compose (NOTE-CADRAGE.md §5). **Rien de ce qui suit ne doit être mis dans git** : ni l'IP, ni les clés, ni les mots de passe, ni le fichier `.env`.

## Accès conservé hors du dépôt

Les variables données à une session Claude ne passent pas automatiquement aux sessions suivantes. Sur la machine qui déploie, conserver les paramètres non publiables dans `~/.config/guis/deploy.env` avec des permissions `600` :

```text
GUIS_VPS_HOST=<IP publique du VPS>
GUIS_VPS_SSH_KEY_PATH=<chemin absolu vers la clé privée SSH>
# GUIS_DOMAIN=<domaine propre facultatif>
```

Créer le répertoire avec permission `700` et le fichier avec permission `600`. Les variables d'environnement `GUIS_VPS_HOST`, `GUIS_VPS_SSH_KEY_PATH` (ou l'ancien `GUIS_VPS_SSH_KEY`) et `GUIS_DOMAIN` prennent priorité sur ce fichier. `python3 deploy/doctor.py` indique seulement quels paramètres sont disponibles ; il ne teste pas le réseau et n'affiche aucune valeur secrète. Si aucun domaine propre n'est défini et que l'hôte est une IPv4, l'adresse provisoire `guis.<IP>.sslip.io` suffit. Vérifier ensuite l'accès avec `ssh -i <chemin de clé> deploy@<IP>` avant tout déploiement.

Si Claude exécute le travail sur une machine cloud, le fichier privé de votre Mac n'y est pas visible. De plus, une session Claude Code dans le cloud ne peut pas ouvrir de connexion SSH sortante (port 22 refusé, constaté le 24/11/2026) : le déploiement se lance alors depuis le Mac, avec `deploy/mettre-a-jour.sh` (§5). Fournir les variables à cet environnement cloud par son mécanisme de secrets persistant, ou placer le fichier privé sur cette machine avec les mêmes permissions. Le dépôt public ne transporte jamais ces valeurs.

La configuration de Fieldproof, y compris ses plateformes cloud, ne donne aucun accès au VPS propre à Guis. Les secrets GitHub Actions servent à la CI lorsqu'ils sont créés ; ils ne révèlent pas leur valeur à une nouvelle session Claude.

## 1. Préparer le serveur (une fois)

Depuis la console Contabo, ou une première connexion `ssh root@<IP>`, une fois le travail fusionné dans `main` :

```bash
curl -fsSL https://raw.githubusercontent.com/2guntan/guis/main/deploy/bootstrap-vps.sh -o bootstrap-vps.sh
```

```bash
bash bootstrap-vps.sh "ssh-ed25519 AAAA… votre-clé-publique"
```

Ce script :
- installe Docker ;
- crée l'utilisateur `deploy` avec votre clé SSH ;
- désactive la connexion par mot de passe et la connexion directe en root ;
- n'ouvre que les ports 22, 80 et 443 avec `ufw` ;
- active fail2ban sur SSH ;
- active les mises à jour de sécurité.

**Avant de fermer la session root**, vérifiez dans un autre terminal que `ssh deploy@<IP>` fonctionne, puis que `sudo` y fonctionne.

**Serveur déjà partiellement configuré.** Ne relancez pas le script à l'aveugle : vérifiez d'abord ce qui tourne (`ss -tlnp`, `docker ps`, `ufw status`, `sshd -T`), puis appliquez les étapes manquantes une par une. Avant de toucher à SSH, gardez une session de secours ouverte (par exemple `ssh -M -S ~/.ssh/guis-cm/r -fN root@<IP>`, chemin court obligatoire) : les connexions ouvertes survivent au rechargement de `sshd`. En cas d'erreur, supprimez `/etc/ssh/sshd_config.d/01-guis.conf` depuis cette session et lancez `systemctl reload ssh`.

Points vérifiés sur Ubuntu 24.04 (images Contabo) :
- `sshd` garde la **première** valeur lue. `50-cloud-init.conf` active `PasswordAuthentication yes` : le réglage Guis doit s'appeler `01-guis.conf` pour passer avant. Contrôle : `sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication) '` doit afficher `no` deux fois.
- L'unité SSH s'appelle `ssh.service`, pas `sshd.service` : la prison fail2ban doit le préciser (`journalmatch`), sinon elle ne voit aucune tentative. Contrôle : `sudo fail2ban-client status sshd`.
- Les ports publiés par Docker contournent `ufw`. Seul Caddy publie des ports (80 et 443) ; la base n'est pas exposée.
- Après les mises à jour, redémarrez si `/var/run/reboot-required` existe, puis vérifiez que `ufw`, fail2ban, Docker et le réglage SSH sont toujours actifs.

## 2. Nom de domaine

Si vous avez un domaine propre, faites pointer un enregistrement DNS `A` (par exemple `guis.exemple.sn`) vers l'IP du VPS. Sinon, `guis.<IP>.sslip.io` fonctionne sans configuration DNS : `sslip.io` renvoie l'IP contenue dans le nom. Caddy obtient le certificat HTTPS au premier démarrage. Le domaine propre peut donc être ajouté après la première mise en ligne.

## 3. Installer Guis

En tant que `deploy` :

```bash
git clone https://github.com/2guntan/guis.git && cd guis
```

```bash
cp .env.example .env && sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" .env
```

Ensuite, mettez dans `.env` soit le domaine propre (`GUIS_DOMAIN=guis.exemple.sn`), soit l'adresse provisoire (`GUIS_DOMAIN=guis.<IP>.sslip.io`), puis lancez la stack :

```bash
docker compose up -d --build
```

Vérification : `https://<domaine>/api/health` répond `{"ok":true}`.

Le premier compte admin se crée ainsi (le mot de passe est demandé au clavier) :

```bash
docker compose exec -it web node scripts/create-user.mjs --phone "77 000 00 01" --name "Prénom Nom" --role admin
```

Les autres comptes (coordinateurs, agents) se créent ensuite sur la page **« Utilisateurs »** du tableau de bord, et les communes se confient aux agents sur la page **« Attribution »** (voir le README racine).

Ensuite, chargez les listes et importez les distributions de semences (voir le README racine).

## 4. App Android

1. Dans GitHub → Settings → Secrets and variables → Actions → **Secrets**, créez `GUIS_API_URL` = `https://<domaine>` (ou `gh secret set GUIS_API_URL --repo 2guntan/guis`). Un secret plutôt qu'une variable : le dépôt est public, une variable apparaîtrait en clair dans les journaux Actions, et l'adresse provisoire `guis.<IP>.sslip.io` contient l'IP.
2. Relancez le workflow **apk** (onglet Actions → apk → Run workflow).
3. Téléchargez l'artefact `guis-apk-N` et installez `app-release.apk` sur les téléphones. Il faut autoriser les sources inconnues.

Le fichier s'appelle `app-release.apk` dans tous les cas, mais il n'est durable que s'il est signé avec la clé de release. Le journal de l'étape « Clé de signature » l'indique : « APK signée avec la clé de release » ou « Pas de clé de release : APK signée avec la clé de debug ». Une APK debug convient pour un essai ; elle devra être désinstallée (données locales non synchronisées perdues) avant d'installer une APK signée autrement.

**Clé de signature.** Sans elle, l'APK est signée avec une clé de debug, qui change d'une construction à l'autre. Pour pouvoir mettre l'app à jour sans la désinstaller, créez une fois une clé, hors du dépôt :

```bash
keytool -genkeypair -v -keystore guis.jks -alias guis -keyalg RSA -keysize 4096 -validity 10000
```

Ajoutez ensuite ces quatre **Secrets** dans GitHub :
- `GUIS_KEYSTORE_BASE64` : le résultat de `base64 -w0 guis.jks` ;
- `GUIS_KEYSTORE_PASSWORD` ;
- `GUIS_KEY_ALIAS` (`guis`) ;
- `GUIS_KEY_PASSWORD`.

Gardez `guis.jks` en lieu sûr : sans ce fichier, plus aucune mise à jour de l'app n'est possible.

## 5. Mettre à jour

Depuis le Mac, à la racine du dépôt à jour (`git pull`), avec la configuration privée en place :

```bash
deploy/mettre-a-jour.sh verifier
```

```bash
deploy/mettre-a-jour.sh maj
```

`verifier` teste la connexion SSH et affiche la version en ligne, les conteneurs et la santé du site. `maj` refuse de continuer si le checkout du serveur a été modifié à la main. Sinon il fait une sauvegarde `pg_dump`, récupère `main` (ou la branche donnée), reconstruit et redémarre la stack, affiche les migrations appliquées et attend que `/api/health` réponde. Le schéma de la base se met à jour tout seul au démarrage du web.

À la main, sur le serveur, c'est équivalent à :

```bash
cd ~/guis && git pull && docker compose up -d --build
```

### Passage des agents aux codes de 4 chiffres

Les agents créés avant les codes gardent leur ancien mot de passe jusqu'à sa réinitialisation. Après la mise à jour, réinitialisez chacun depuis la page « Utilisateurs » (admin) ou « Attribution » (coordinateur) et transmettez-lui son code. Le compte admin garde son mot de passe.

### Charger les données de la coopérative

Les fichiers restent sur le Mac. Le script les copie dans un dossier temporaire du serveur et du conteneur `web`, lance la commande, puis les efface, même en cas d'erreur. `import` et `attribution` font d'abord une sauvegarde de la base.

```bash
deploy/mettre-a-jour.sh simulation fiche.xlsx villages-correspondance.xlsx
```

```bash
deploy/mettre-a-jour.sh import fiche.xlsx villages-correspondance.xlsx
```

```bash
deploy/mettre-a-jour.sh attribution communes-agents.xlsx
```

Relire le compte rendu de la simulation avant l'import réel, qui demande de taper « oui ». L'attribution se gère normalement sur la page « Attribution » du tableau de bord ; le script `attribution` reste pour un chargement en masse et affiche **une seule fois** le code initial de chaque agent créé : le noter pour le lui transmettre, sans le copier dans un ticket ni dans git. Les sauvegardes faites avant chaque opération s'appellent `guis-avant-<opération>-<date>.dump` dans le volume `backups`.

## 6. Sauvegardes

- Contabo garde automatiquement 10 sauvegardes quotidiennes du serveur entier.
- Le service `backup` fait un `pg_dump` chaque nuit vers 2 h UTC, dans le volume `backups`, et garde 14 jours.

Pour lister les sauvegardes :

```bash
docker compose exec backup ls -la /backups
```

**Copie hors du serveur**, à faire régulièrement :

```bash
scp deploy@<IP>:"$(docker volume inspect guis_backups -f '{{.Mountpoint}}')/guis-AAAA-MM-JJ.dump" .
```

La copie peut aussi aller vers Contabo Object Storage avec `rclone`.

**Restaurer** une sauvegarde dans une base de test, pour vérifier qu'elle est lisible :

```bash
docker compose exec backup sh -c 'createdb guis_test && pg_restore -d guis_test /backups/guis-AAAA-MM-JJ.dump && psql -d guis_test -c "select count(*) from fields" && dropdb guis_test'
```

**Tester sans attendre la nuit** (dump immédiat, restauration dans une base isolée, comparaison du nombre de tables, puis nettoyage) :

```bash
cat <<'EOF' | docker compose exec -T backup sh -s
set -e
f=/backups/guis-test-$(date -u +%Y%m%dT%H%M%S).dump
pg_dump -Fc -f "$f"
createdb guis_restore_test && pg_restore -d guis_restore_test "$f"
q="select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE'"
echo "tables source=$(psql -At -c "$q") restaurées=$(psql -At -d guis_restore_test -c "$q")"
dropdb guis_restore_test && rm "$f"
EOF
```

Les photos sont dans le volume `photos`. Elles sont couvertes par la sauvegarde Contabo du serveur. Pour les copier ailleurs, archivez le dossier du volume.

## 7. Journaux

```bash
docker compose logs -f web
```

```bash
docker compose logs -f sat
```

```bash
docker compose ps
```
