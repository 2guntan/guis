#!/usr/bin/env bash
# Préparation du VPS Contabo (Ubuntu 24.04), à lancer UNE fois, en root, depuis la console Contabo ou une
# première connexion SSH. Il ne contient aucun secret : la clé publique SSH est passée en argument.
#
#   bash bootstrap-vps.sh "ssh-ed25519 AAAA… commentaire"
#
# Effet (NOTE-CADRAGE.md §5) : Docker et Compose installés ; utilisateur « deploy » (non root, groupe docker)
# avec la clé SSH donnée ; connexion SSH par mot de passe et connexion directe en root désactivées ;
# pare-feu ufw ouvert seulement sur 22, 80 et 443 ; fail2ban sur SSH ; mises à jour de sécurité automatiques.
# Le script peut être relancé : chaque étape vérifie ce qui existe déjà.
set -euo pipefail

KEY="${1:?usage : bash bootstrap-vps.sh \"<clé publique SSH>\"}"
[ "$(id -u)" -eq 0 ] || { echo "À lancer en root." >&2; exit 1; }

apt-get update
apt-get install -y ca-certificates curl ufw unattended-upgrades fail2ban git

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

# SSH : clé seulement, pas de root. sshd garde la PREMIÈRE valeur lue : le préfixe 01 passe avant
# 50-cloud-init.conf, qui active PasswordAuthentication sur les images Contabo.
rm -f /etc/ssh/sshd_config.d/90-guis.conf
cat > /etc/ssh/sshd_config.d/01-guis.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
X11Forwarding no
CONF
sshd -t
systemctl reload ssh
sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication) '

# fail2ban : sur Ubuntu 24.04, l'unité s'appelle ssh.service (le filtre par défaut cherche sshd.service).
cat > /etc/fail2ban/jail.d/guis.local <<'CONF'
[DEFAULT]
backend = systemd
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
CONF
systemctl enable fail2ban
systemctl restart fail2ban

# Pare-feu
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

dpkg-reconfigure -f noninteractive unattended-upgrades
echo "VPS prêt. Vérifiez depuis un autre terminal : ssh deploy@<IP> (avant de fermer cette session)."
