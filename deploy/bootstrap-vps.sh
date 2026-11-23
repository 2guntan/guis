#!/usr/bin/env bash
# Préparation du VPS Contabo (Ubuntu 24.04), à lancer UNE fois, en root, depuis la console Contabo ou une
# première connexion SSH. Il ne contient aucun secret : la clé publique SSH est passée en argument.
#
#   bash bootstrap-vps.sh "ssh-ed25519 AAAA… commentaire"
#
# Effet (NOTE-CADRAGE.md §5) : Docker et Compose installés ; utilisateur « deploy » (non root, groupe docker)
# avec la clé SSH donnée ; connexion SSH par mot de passe et connexion directe en root désactivées ;
# pare-feu ufw ouvert seulement sur 22, 80 et 443 ; mises à jour de sécurité automatiques.
set -euo pipefail

KEY="${1:?usage : bash bootstrap-vps.sh \"<clé publique SSH>\"}"
[ "$(id -u)" -eq 0 ] || { echo "À lancer en root." >&2; exit 1; }

apt-get update
apt-get install -y ca-certificates curl ufw unattended-upgrades git

# Docker (dépôt officiel)
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Utilisateur deploy
id deploy >/dev/null 2>&1 || adduser --disabled-password --gecos "" deploy
usermod -aG docker deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
grep -qxF "$KEY" /home/deploy/.ssh/authorized_keys 2>/dev/null || echo "$KEY" >> /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys

# SSH : clé seulement, pas de root
cat > /etc/ssh/sshd_config.d/90-guis.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
CONF
sshd -t
systemctl reload ssh

# Pare-feu
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

dpkg-reconfigure -f noninteractive unattended-upgrades
echo "VPS prêt. Vérifiez depuis un autre terminal : ssh deploy@<IP> (avant de fermer cette session)."
