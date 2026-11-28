#!/usr/bin/env bash
# Sur le VPS, dans ~/guis : met en ligne l'APK de la release GitHub apk-N sur https://<domaine>/app/
# et la propose aux agents (bandeau « Nouvelle version »). Lancé par « deploy/mettre-a-jour.sh apk N »
# depuis le Mac, qui a d'abord vérifié le signataire de cette APK et en donne l'empreinte attendue.
#
#   deploy/publier-apk.sh N SHA256
#
# - télécharge guis.apk de la release apk-N et vérifie qu'elle a l'empreinte SHA256 ;
# - la place dans data/app (servi par Caddy, ignoré par git), en gardant la précédente
#   (guis-<ancien N>.apk) ; la page d'installation est refaite à partir de deploy/app/index.html ;
# - règle GUIS_LATEST_APP_BUILD=N et GUIS_APK_URL=https://<domaine>/app/guis.apk dans .env (copie
#   de sauvegarde avant), puis redémarre web et caddy.
# Revenir à une version précédente : relancer avec son numéro.
set -euo pipefail

die() { echo "Erreur : $*" >&2; exit 1; }
say() { printf '\n== %s\n' "$*"; }

[ $# -eq 2 ] || die "usage : $0 N SHA256"
N="$1"
SHA="$2"
[[ "$N" =~ ^[0-9]+$ ]] || die "numéro de version invalide : $N"
[[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || die "empreinte SHA-256 invalide"
cd "$(dirname "$0")/.."
[ -f .env ] || die ".env introuvable dans $(pwd)"

# Dépôt GitHub d'après le remote (https://github.com/<propriétaire>/<dépôt>.git ou git@github.com:…).
REPO="$(git remote get-url origin | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')"
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "remote GitHub non reconnu"

env_value() { grep -E "^$1=" .env | tail -n 1 | cut -d= -f2- | sed -e "s/^[\"']//" -e "s/[\"']$//"; }
DOMAIN="$(env_value GUIS_DOMAIN || true)"
[ -n "$DOMAIN" ] && [ "$DOMAIN" != localhost ] || die "GUIS_DOMAIN manquant dans .env"

# data/app peut avoir été créé par Docker (propriétaire root) au premier démarrage de caddy.
mkdir -p data/app 2>/dev/null || true
if [ ! -w data/app ]; then
  docker run --rm -v "$(pwd)/data/app:/d" busybox chown "$(id -u):$(id -g)" /d
fi
[ -w data/app ] || die "data/app n'est pas accessible en écriture"

say "Téléchargement de la release apk-$N"
TMP="$(mktemp -d data/app/.apk-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 3 -o "$TMP/guis.apk" "https://github.com/$REPO/releases/download/apk-$N/guis.apk" \
  || die "release apk-$N introuvable sur GitHub"
GOT="$(sha256sum "$TMP/guis.apk" | cut -d' ' -f1)"
[ "$GOT" = "$SHA" ] || die "empreinte différente de celle vérifiée sur le Mac : rien n'est changé"
echo "empreinte vérifiée"

say "Mise en ligne sur https://$DOMAIN/app/"
OLD="$(cat data/app/BUILD 2>/dev/null || true)"
if [ -f data/app/guis.apk ] && [ -n "$OLD" ] && [ "$OLD" != "$N" ]; then
  find data/app -maxdepth 1 -name 'guis-*.apk' -delete
  mv data/app/guis.apk "data/app/guis-$OLD.apk"
  echo "version précédente gardée : guis-$OLD.apk"
fi
BYTES="$(wc -c < "$TMP/guis.apk" | tr -d ' ')"
SIZE="$(awk -v b="$BYTES" 'BEGIN { printf "%.1f Mo", b / 1048576 }' | tr . ,)"
sed -e "s/__BUILD__/$N/g" -e "s/__TAILLE__/$SIZE/g" -e "s#__DATE__#$(date -u +%d/%m/%Y)#g" deploy/app/index.html > "$TMP/index.html"
cp apps/web/app/fonts/Fraunces-var.woff2 apps/web/app/fonts/Geist-var.woff2 apps/web/public/icon.svg data/app/
echo "$SHA  guis.apk" > data/app/guis.apk.sha256
mv "$TMP/guis.apk" data/app/guis.apk
mv "$TMP/index.html" data/app/index.html
echo "$N" > data/app/BUILD
chmod 644 data/app/*

say "Proposition aux agents (.env)"
cp -p .env ".env.bak-$(date -u +%Y%m%dT%H%M%S)"
set_env() {
  if grep -qE "^$1=" .env; then
    sed -i "s#^$1=.*#$1=$2#" .env
  else
    printf '%s=%s\n' "$1" "$2" >> .env
  fi
}
set_env GUIS_LATEST_APP_BUILD "$N"
set_env GUIS_APK_URL "https://$DOMAIN/app/guis.apk"
docker compose up -d --wait web caddy
[ "$(docker compose exec -T web printenv GUIS_LATEST_APP_BUILD)" = "$N" ] || die "GUIS_LATEST_APP_BUILD n'a pas pris la valeur $N dans le conteneur"
echo "GUIS_LATEST_APP_BUILD=$N"
[ -z "$(git status --porcelain)" ] || die "le checkout a des modifications : le workflow de déploiement refuserait de tourner"
echo "version $N proposée"
