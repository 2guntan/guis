#!/usr/bin/env bash
# Mise à jour de Guis sur le VPS et chargement des données de la coopérative, depuis la machine
# qui a l'accès SSH (le Mac du porteur). Aucune valeur secrète dans ce fichier : l'hôte et la clé
# viennent de l'environnement ou de ~/.config/guis/deploy.env (voir docs/DEPLOIEMENT.md).
#
#   deploy/mettre-a-jour.sh verifier                          # accès SSH, version en ligne, santé
#   deploy/mettre-a-jour.sh maj [branche]                     # sauvegarde, git pull, reconstruction (défaut : main)
#   deploy/mettre-a-jour.sh simulation FICHE.xlsx VILLAGES.xlsx   # import de la fiche, sans rien écrire
#   deploy/mettre-a-jour.sh import FICHE.xlsx VILLAGES.xlsx       # sauvegarde, puis import réel (confirmation)
#   deploy/mettre-a-jour.sh attribution COMMUNES-AGENTS.xlsx      # attribution des communes aux agents
#   deploy/mettre-a-jour.sh apk N                             # vérifie l'APK de la release apk-N, la met
#                                                             # sur https://<domaine>/app/ et la propose aux agents
#   deploy/mettre-a-jour.sh guide GUIDE.pdf                   # guide de l'agent, lié depuis la page /app/
#
# Les fichiers de la coopérative sont copiés dans un dossier temporaire du serveur et du conteneur,
# puis effacés à la fin, même en cas d'erreur. Compatible avec le bash 3 de macOS.
set -euo pipefail

CONFIG="${GUIS_DEPLOY_CONFIG:-$HOME/.config/guis/deploy.env}"
REMOTE_DIR=guis   # relatif au dossier personnel de deploy sur le serveur

die() { echo "Erreur : $*" >&2; exit 1; }
say() { printf '\n== %s\n' "$*"; }

# --- Configuration (mêmes noms que deploy/doctor.py) ------------------------------------------
conf() {
  local name="$1" value
  value="$(eval "printf '%s' \"\${$name:-}\"")"
  if [ -z "$value" ] && [ -f "$CONFIG" ]; then
    value="$(grep -E "^[[:space:]]*$name=" "$CONFIG" | tail -n 1 | cut -d= -f2- | sed -e "s/^[\"']//" -e "s/[\"']$//")"
  fi
  printf '%s' "$value"
}

if [ -f "$CONFIG" ] && [ -n "$(find "$CONFIG" -perm -g+r -o -perm -o+r 2>/dev/null)" ]; then
  die "$CONFIG doit avoir les permissions 600 (chmod 600 $CONFIG)"
fi
HOST="$(conf GUIS_VPS_HOST)"
KEY="$(conf GUIS_VPS_SSH_KEY_PATH)"
[ -n "$KEY" ] || KEY="$(conf GUIS_VPS_SSH_KEY)"
DOMAIN="$(conf GUIS_DOMAIN)"
[ -n "$HOST" ] || die "GUIS_VPS_HOST manquant (environnement ou $CONFIG)"
[ -n "$KEY" ] || die "GUIS_VPS_SSH_KEY_PATH manquant (environnement ou $CONFIG)"
[ -n "$DOMAIN" ] && [ "$DOMAIN" != localhost ] || DOMAIN="guis.$HOST.sslip.io"

WORK="$(mktemp -d)"
cleanup_local() { rm -rf "$WORK"; }
trap cleanup_local EXIT
case "$KEY" in
  -----BEGIN*) printf '%s\n' "$KEY" > "$WORK/key"; chmod 600 "$WORK/key"; KEY="$WORK/key" ;;
  *) KEY="${KEY/#\~/$HOME}"; [ -f "$KEY" ] || die "clé SSH introuvable : $KEY" ;;
esac

SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=auto -o "ControlPath=$WORK/cm" -o ControlPersist=120)
# shellcheck disable=SC2029 # les commandes sont construites ici et exécutées sur le serveur
remote() { ssh "${SSH_OPTS[@]}" "deploy@$HOST" "cd $REMOTE_DIR && $1"; }

health() {
  local _
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 5 "https://$DOMAIN/api/health" >/dev/null 2>&1; then
      echo "https://<domaine>/api/health : ok"
      return 0
    fi
    sleep 4
  done
  die "le site ne répond pas sur /api/health après 2 minutes (voir : docker compose logs web)"
}

backup() {
  say "Sauvegarde de la base avant $1"
  remote "docker compose exec -T backup sh -c 'f=/backups/guis-avant-$1-\$(date -u +%Y%m%dT%H%M%S).dump && pg_dump -Fc -f \"\$f\" && ls -l \"\$f\"'"
}

# Copie des fichiers dans le conteneur web (/tmp/guis-import), lance la commande, efface tout.
with_files() {
  local cmd="$1"; shift
  local rdir
  rdir="$(remote 'mktemp -d /tmp/guis-import.XXXXXX')"
  # shellcheck disable=SC2064
  trap "remote 'docker compose exec -T -u root web rm -rf /tmp/guis-import; rm -rf $rdir' >/dev/null 2>&1 || true; cleanup_local" EXIT
  mkdir -p "$WORK/import"
  local f
  for f in "$@"; do
    [ -f "$f" ] || die "fichier introuvable : $f"
  done
  cp "$@" "$WORK/import/"
  chmod 644 "$WORK"/import/*
  scp -q "${SSH_OPTS[@]}" "$WORK"/import/* "deploy@$HOST:$rdir/"
  remote "chmod 700 $rdir && docker compose exec -T -u root web rm -rf /tmp/guis-import && docker compose cp $rdir web:/tmp/guis-import >/dev/null"
  # docker cp garde le propriétaire du serveur (deploy) et le mode 700 : l'app tourne en « node ».
  remote "docker compose exec -T -u root web chown -R node:node /tmp/guis-import"
  remote "docker compose exec -T web $cmd"
}

base() { basename "$1"; }

# Outil du SDK Android (build-tools le plus récent), pour vérifier une APK.
build_tool() {
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}" t
  t="$(ls -d "$sdk"/build-tools/*/ 2>/dev/null | sort -V | tail -n 1)"
  [ -n "$t" ] && [ -x "$t$1" ] || die "$1 introuvable (SDK Android : $sdk/build-tools)"
  printf '%s' "$t$1"
}

[ $# -ge 1 ] || die "commande manquante : verifier, maj, simulation, import, attribution, apk ou guide (voir l'en-tête du script)"
case "$1" in
  verifier)
    say "Connexion SSH"
    remote 'echo "connecté en $(whoami) sur $(hostname)"'
    say "Version en ligne"
    remote 'git log --oneline -1 && git status --short | head -5'
    say "Conteneurs"
    remote 'docker compose ps --format "table {{.Service}}\t{{.Status}}"'
    say "Santé"
    health
    ;;
  maj)
    ref="${2:-main}"
    remote "git diff --quiet && git diff --cached --quiet" || die "le checkout du serveur a des modifications locales : à examiner avant de mettre à jour"
    backup maj
    say "Récupération de $ref"
    remote "git fetch --quiet origin && git checkout --quiet $ref && git pull --ff-only --quiet origin $ref && git log --oneline -1"
    say "Reconstruction et redémarrage (quelques minutes)"
    remote 'docker compose up -d --build 2>&1 | tail -n 5'
    say "Migrations"
    sleep 10
    remote 'docker compose logs --no-log-prefix web 2>&1 | grep -E "migration appliquée|migration .*:" | tail -n 10 || echo "aucune nouvelle migration"'
    say "Santé"
    health
    ;;
  simulation)
    [ $# -eq 3 ] || die "usage : $0 simulation FICHE.xlsx VILLAGES.xlsx"
    say "Simulation de l'import (rien n'est écrit)"
    with_files "node scripts/import-fiche-validation.mjs /tmp/guis-import/$(base "$2") --villages /tmp/guis-import/$(base "$3") --simulation" "$2" "$3"
    ;;
  import)
    [ $# -eq 3 ] || die "usage : $0 import FICHE.xlsx VILLAGES.xlsx"
    printf "Importer pour de bon la fiche dans la base de production ? Tapez « oui » : "
    read -r ok
    [ "$ok" = oui ] || die "import annulé"
    backup import
    say "Import de la fiche"
    with_files "node scripts/import-fiche-validation.mjs /tmp/guis-import/$(base "$2") --villages /tmp/guis-import/$(base "$3")" "$2" "$3"
    ;;
  attribution)
    [ $# -eq 2 ] || die "usage : $0 attribution COMMUNES-AGENTS.xlsx"
    backup attribution
    say "Attribution des communes (les mots de passe des comptes créés ne s'affichent qu'ici, une fois)"
    with_files "node scripts/load-attribution.mjs /tmp/guis-import/$(base "$2")" "$2"
    ;;
  apk)
    [ $# -eq 2 ] && [[ "$2" =~ ^[0-9]+$ ]] || die "usage : $0 apk N (numéro de la release apk-N)"
    n="$2"
    say "Vérification de la release apk-$n sur ce Mac"
    base_url="https://github.com/2guntan/guis/releases/download/apk-$n"
    curl -fsSL -o "$WORK/guis.apk" "$base_url/guis.apk" || die "release apk-$n introuvable"
    curl -fsSL -o "$WORK/guis.apk.sha256" "$base_url/guis.apk.sha256" || die "empreinte de apk-$n introuvable"
    (cd "$WORK" && shasum -a 256 -c guis.apk.sha256 >/dev/null) || die "l'APK ne correspond pas à son empreinte"
    sha="$(cut -d' ' -f1 "$WORK/guis.apk.sha256")"
    code="$("$(build_tool aapt)" dump badging "$WORK/guis.apk" | sed -nE "s/.*versionCode='([0-9]+)'.*/\1/p" | head -n 1)"
    [ "$code" = "$n" ] || die "versionCode $code au lieu de $n"
    "$(build_tool apksigner)" verify --print-certs "$WORK/guis.apk" | grep -q 'CN=Guis, O=Solir, C=SN' \
      || die "signataire inattendu : ne rien proposer aux agents"
    echo "empreinte, versionCode $n et signataire (CN=Guis, O=Solir, C=SN) vérifiés"
    rm -f "$WORK/guis.apk" "$WORK/guis.apk.sha256"
    remote "git diff --quiet && git diff --cached --quiet" || die "le checkout du serveur a des modifications locales : à examiner d'abord"
    remote "test -x deploy/publier-apk.sh" || die "le serveur n'a pas encore deploy/publier-apk.sh : lancer d'abord « $0 maj »"
    remote "deploy/publier-apk.sh $n $sha"
    say "Contrôle depuis Internet"
    health
    got="$(curl -fsSL "https://$DOMAIN/app/guis.apk" | shasum -a 256 | cut -d' ' -f1)"
    [ "$got" = "$sha" ] || die "https://<domaine>/app/guis.apk ne sert pas l'APK attendue"
    curl -fsS -o /dev/null "https://$DOMAIN/app/" || die "la page https://<domaine>/app/ ne répond pas"
    echo "https://<domaine>/app/ : page et APK version $n en ligne"
    ;;
  guide)
    [ $# -eq 2 ] && [ -f "$2" ] || die "usage : $0 guide GUIDE.pdf"
    [ "$(head -c 4 "$2")" = "%PDF" ] || die "$2 n'est pas un PDF"
    say "Guide de l'agent"
    remote "test -w data/app" || die "data/app absent ou non accessible sur le serveur : publier d'abord une APK (« $0 apk N »)"
    scp -q "${SSH_OPTS[@]}" "$2" "deploy@$HOST:$REMOTE_DIR/data/app/.guide.pdf"
    remote "chmod 644 data/app/.guide.pdf && mv data/app/.guide.pdf data/app/guide.pdf"
    curl -fsS -o /dev/null "https://$DOMAIN/app/guide.pdf" || die "https://<domaine>/app/guide.pdf ne répond pas"
    echo "https://<domaine>/app/guide.pdf en ligne"
    ;;
  *)
    die "commande inconnue : $1 (verifier, maj, simulation, import, attribution, apk ou guide)"
    ;;
esac
