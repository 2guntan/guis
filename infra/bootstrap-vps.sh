#!/usr/bin/env bash
# Prépare et sécurise le VPS Guis (Ubuntu 24.04). À lancer UNE fois depuis
# l'ordinateur qui a la clé root (installée avec ssh-copy-id) :
#
#   ./infra/bootstrap-vps.sh <IP_DU_VPS>
#
# L'IP n'est jamais écrite dans le dépôt : elle est passée en argument.
#
# Ce que fait le script :
#   1. crée en local une clé dédiée à l'agent cloud : ~/.ssh/guis_agent
#   2. (en root) mises à jour, utilisateur deploy (sudo, vos clés + clé agent),
#      ufw (22/80/443), fail2ban, mises à jour automatiques, Docker + compose
#   3. vérifie que deploy se connecte et a sudo
#   4. (en deploy) désactive root et les mots de passe en SSH
#   5. vérifie que root et les mots de passe sont bien refusés
set -euo pipefail

IP="${1:?usage: $0 <IP_DU_VPS>}"
KEY="$HOME/.ssh/guis_agent"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# --- 1. Clé de l'agent cloud -------------------------------------------------
step "Clé de l'agent cloud ($KEY)"
if [[ ! -f "$KEY" ]]; then
  ssh-keygen -t ed25519 -N "" -C "guis-cloud-agent" -f "$KEY"
else
  echo "Déjà présente, réutilisée."
fi
AGENT_PUB="$(cat "$KEY.pub")"

# --- 2. Préparation en root --------------------------------------------------
step "Préparation du serveur (root)"
ssh "${SSH_OPTS[@]}" "root@$IP" "bash -s -- '$AGENT_PUB'" <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
AGENT_PUB="$1"
APT_OPTS=(-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

echo "-- Mises à jour"
apt-get update -q
apt-get "${APT_OPTS[@]}" upgrade
apt-get "${APT_OPTS[@]}" install ufw fail2ban python3-systemd unattended-upgrades ca-certificates curl

echo "-- Utilisateur deploy"
id deploy >/dev/null 2>&1 || adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
# deploy n'a pas de mot de passe (connexion par clé seulement) : sudo sans mot de passe.
echo 'deploy ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-deploy
chmod 440 /etc/sudoers.d/90-deploy
visudo -cf /etc/sudoers.d/90-deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
# Vos clés (celles de root) + la clé de l'agent, sans doublon ni ligne "command=".
{ grep -v 'command=' /root/.ssh/authorized_keys || true; echo "$AGENT_PUB"; } \
  | awk 'NF && !seen[$0]++' > /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys

echo "-- Pare-feu ufw"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "-- fail2ban"
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
EOF
systemctl enable fail2ban
systemctl restart fail2ban

echo "-- Mises à jour automatiques"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
cat > /etc/apt/apt.conf.d/52guis-unattended <<'EOF'
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF
systemctl enable --now unattended-upgrades

echo "-- Docker + compose (dépôt officiel)"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -q
apt-get "${APT_OPTS[@]}" install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
# Journaux des conteneurs limités en taille.
[[ -f /etc/docker/daemon.json ]] || echo '{ "log-driver": "local" }' > /etc/docker/daemon.json
systemctl enable docker
systemctl restart docker
usermod -aG docker deploy

echo "-- Fait (root)."
REMOTE

# --- 3. Vérifier deploy avant de fermer root --------------------------------
step "Vérification : connexion deploy + sudo + docker"
ssh "${SSH_OPTS[@]}" "deploy@$IP" 'sudo -n true && docker --version && docker compose version'
ssh "${SSH_OPTS[@]}" -i "$KEY" -o IdentitiesOnly=yes "deploy@$IP" 'echo "Clé agent OK pour $(whoami)"'

# --- 4. Fermer root et les mots de passe en SSH ------------------------------
step "Durcissement SSH (via deploy)"
ssh "${SSH_OPTS[@]}" "deploy@$IP" 'sudo bash -s' <<'REMOTE'
set -euo pipefail
# 00- : lu avant 50-cloud-init.conf ; pour sshd, la première valeur gagne.
cat > /etc/ssh/sshd_config.d/00-guis.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowUsers deploy
MaxAuthTries 3
X11Forwarding no
EOF
mkdir -p /run/sshd
sshd -t
systemctl restart ssh
sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|allowusers) '
REMOTE

# --- 5. Contrôles finaux ------------------------------------------------------
step "Contrôles finaux"
if ssh -o BatchMode=yes -o ConnectTimeout=10 "root@$IP" true 2>/dev/null; then
  echo "ATTENTION : root peut encore se connecter !" >&2; exit 1
else
  echo "OK : connexion root refusée."
fi
if ssh -o BatchMode=yes -o ConnectTimeout=10 -o PubkeyAuthentication=no \
     -o PreferredAuthentications=password,keyboard-interactive "deploy@$IP" true 2>&1 \
     | grep -q 'Permission denied (publickey)'; then
  echo "OK : seule la clé est acceptée (pas de mot de passe)."
else
  echo "ATTENTION : vérifier l'authentification par mot de passe." >&2
fi
ssh "${SSH_OPTS[@]}" "deploy@$IP" 'sudo ufw status verbose; sudo fail2ban-client status sshd; systemctl is-active unattended-upgrades docker'

step "Terminé"
cat <<EOF
Connexion : ssh deploy@$IP
Clé de l'agent cloud : $KEY (privée)  /  $KEY.pub (publique)
Ne mettez ni l'IP ni ces clés dans le dépôt.
EOF
