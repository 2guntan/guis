# Déploiement sur le VPS

Un seul serveur, un VPS Contabo Cloud VPS 4 sous Ubuntu 24.04, avec Docker Compose (NOTE-CADRAGE.md §5). **Rien de ce qui suit ne doit être mis dans git** : ni l'IP, ni les clés, ni les mots de passe, ni le fichier `.env`.

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
- active les mises à jour de sécurité.

**Avant de fermer la session root**, vérifiez dans un autre terminal que `ssh deploy@<IP>` fonctionne.

## 2. Nom de domaine

Faites pointer un enregistrement DNS `A` (par exemple `guis.exemple.sn`) vers l'IP du VPS. À défaut, `guis.<IP>.sslip.io` fonctionne sans rien configurer : `sslip.io` renvoie l'IP contenue dans le nom. Caddy obtient le certificat HTTPS tout seul au premier démarrage.

## 3. Installer Guis

En tant que `deploy` :

```bash
git clone https://github.com/2guntan/guis.git && cd guis
```

```bash
cp .env.example .env && sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" .env
```

Ensuite, mettez le domaine dans `.env` (`GUIS_DOMAIN=guis.exemple.sn`), puis lancez la stack :

```bash
docker compose up -d --build
```

Vérification : `https://<domaine>/api/health` répond `{"ok":true}`.

Les premiers comptes se créent ainsi (le mot de passe est demandé au clavier) :

```bash
docker compose exec -it web node scripts/create-user.mjs --phone "77 000 00 01" --name "Prénom Nom" --role admin
```

```bash
docker compose exec -it web node scripts/create-user.mjs --phone "77 000 00 02" --name "Prénom Nom" --role agent
```

Ensuite, chargez les listes et importez les distributions de semences (voir le README racine).

## 4. App Android

1. Dans GitHub → Settings → Secrets and variables → Actions → **Variables**, créez `GUIS_API_URL` = `https://<domaine>`.
2. Relancez le workflow **apk** (onglet Actions → apk → Run workflow).
3. Téléchargez l'artefact `guis-apk-N` et installez `app-release.apk` sur les téléphones. Il faut autoriser les sources inconnues.

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

```bash
cd ~/guis && git pull && docker compose up -d --build
```

Le schéma de la base se met à jour tout seul au démarrage du web.

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
