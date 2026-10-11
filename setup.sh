#!/usr/bin/env bash
# ==============================================================================
# BLACKBOX — homelab-stack setup script
# Run once on a fresh Ubuntu Server install to bootstrap the environment.
# Usage: sudo bash setup.sh
# ==============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${REPO_DIR}/.env"

# --- Preflight checks ---

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (sudo bash setup.sh)"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: .env file not found. Copy .env.example to .env and fill in your values first."
  echo "  cp .env.example .env"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

echo "========================================="
echo "  BLACKBOX — Setup starting..."
echo "========================================="

# --- Install Docker ---

echo ""
echo "[1/9] Installing Docker..."

if command -v docker &>/dev/null; then
  echo "  Docker already installed: $(docker --version)"
else
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Allow the non-root user to run docker
  SUDO_USER_NAME="${SUDO_USER:-sysadmin}"
  usermod -aG docker "$SUDO_USER_NAME"

  echo "  Docker installed: $(docker --version)"
fi

# --- Create service config directories ---

echo ""
echo "[2/9] Creating service config directories..."

mkdir -p "${REPO_DIR}/plex/config"
mkdir -p "${REPO_DIR}/homeassistant/config"
mkdir -p "${REPO_DIR}/pihole/etc-pihole"
mkdir -p "${REPO_DIR}/pihole/etc-dnsmasq.d"
mkdir -p "${REPO_DIR}/frigate/config"
mkdir -p "${REPO_DIR}/mosquitto/config"
mkdir -p "${REPO_DIR}/mosquitto/data"
mkdir -p "${REPO_DIR}/mosquitto/log"

echo "  Done."

# --- Mount NAS shares ---

echo ""
echo "[3/9] Mounting NAS shares..."

apt-get install -y -qq cifs-utils

# Public/Media/Movies (guest access)
mkdir -p "/mnt/Public/Media/Movies"
if ! grep -q "//192.168.1.3/Public/Media/Movies" /etc/fstab; then
  echo '//192.168.1.3/Public/Media/Movies /mnt/Public/Media/Movies cifs guest,iocharset=utf8,uid='"${PUID:-1000}"',gid='"${PGID:-1000}"',nofail,_netdev 0 0' >> /etc/fstab
  echo "  Added /mnt/Public/Media/Movies to fstab"
fi

# Public/Media/TV Shows (guest access)
mkdir -p "/mnt/Public/Media/TV Shows"
if ! grep -q "Public/Media/TV" /etc/fstab; then
  echo '//192.168.1.3/Public/Media/TV\040Shows /mnt/Public/Media/TV\040Shows cifs guest,iocharset=utf8,uid='"${PUID:-1000}"',gid='"${PGID:-1000}"',nofail,_netdev 0 0' >> /etc/fstab
  echo "  Added /mnt/Public/Media/TV Shows to fstab"
fi

# Cameras share (authenticated)
mkdir -p /mnt/Cameras
mkdir -p /etc/samba
CREDS_FILE="/etc/samba/credentials"

if [[ -z "${NAS_CAMERAS_USER:-}" || -z "${NAS_CAMERAS_PASS:-}" ]]; then
  echo "  Warning: NAS_CAMERAS_USER or NAS_CAMERAS_PASS not set in .env — skipping Cameras mount."
else
  cat > "$CREDS_FILE" <<CRED
username=${NAS_CAMERAS_USER}
password=${NAS_CAMERAS_PASS}
CRED
  chmod 600 "$CREDS_FILE"

  if ! grep -q "//192.168.1.3/Cameras" /etc/fstab; then
    echo "//192.168.1.3/Cameras /mnt/Cameras cifs credentials=${CREDS_FILE},iocharset=utf8,uid=${PUID:-1000},gid=${PGID:-1000},nofail,_netdev 0 0" >> /etc/fstab
    echo "  Added /mnt/Cameras to fstab (authenticated)"
  fi
fi

mount -a || echo "  Warning: mount -a had errors. Check NAS connectivity."
echo "  Done."

# --- Blacklist mt76x2u WiFi driver ---

echo ""
echo "[4/9] Blacklisting mt76x2u WiFi driver..."

BLACKLIST_FILE="/etc/modprobe.d/blacklist-mt76x2u.conf"
if [[ ! -f "$BLACKLIST_FILE" ]]; then
  echo "blacklist mt76x2u" > "$BLACKLIST_FILE"
  echo "  Created ${BLACKLIST_FILE}"
else
  echo "  Already blacklisted."
fi

# --- Enable IPv4 forwarding (for Tailscale subnet routing) ---

echo ""
echo "[5/9] Enabling IPv4 forwarding for Tailscale subnet routing..."

SYSCTL_FILE="/etc/sysctl.d/99-tailscale.conf"
if [[ ! -f "$SYSCTL_FILE" ]]; then
  cat > "$SYSCTL_FILE" <<'EOF'
# Required for Tailscale subnet routing (192.168.1.0/24).
# IPv6 forwarding intentionally left disabled — LAN devices we route to
# (Reolink cameras, NAS) are IPv4-only.
net.ipv4.ip_forward = 1
EOF
  sysctl --system >/dev/null
  echo "  Created ${SYSCTL_FILE} and applied."
else
  echo "  ${SYSCTL_FILE} already exists."
fi

# --- Install Tailscale ---

echo ""
echo "[6/9] Installing Tailscale..."

if command -v tailscale &>/dev/null; then
  echo "  Tailscale already installed: $(tailscale version | head -1)"
else
  apt-get install -y -qq curl gnupg

  # Official Tailscale apt repo (Ubuntu noble = 24.04)
  UBUNTU_CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${UBUNTU_CODENAME}.noarmor.gpg" \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${UBUNTU_CODENAME}.tailscale-keyring.list" \
    -o /etc/apt/sources.list.d/tailscale.list

  apt-get update -qq
  apt-get install -y -qq tailscale

  systemctl enable --now tailscaled

  echo "  Tailscale installed: $(tailscale version | head -1)"
  echo "  Run the following manually to join the tailnet (one-time):"
  echo "    sudo tailscale up --hostname=blackbox \\"
  echo "      --advertise-routes=192.168.1.0/24 \\"
  echo "      --advertise-tags=tag:server"
  echo "  Then approve the subnet route + disable key expiry in the Tailscale admin console."
fi

# --- Configure DNS to support both Tailscale and public internet ---

echo ""
echo "[6.5/9] Configuring DNS for Tailscale + public internet access..."

# Configure systemd-resolved to use public DNS with Tailscale as a fallback
# This allows containers to resolve public domains (plex.tv, etc) while maintaining
# Tailscale connectivity for tailnet-internal domains.
cat > /etc/systemd/resolved.conf <<'EOF'
[Resolve]
DNS=8.8.8.8 8.8.4.4 100.100.100.100
FallbackDNS=8.8.8.8 8.8.4.4
# Route Tailscale domains (.ts.net) to Tailscale's nameserver
Domains=~tail*.ts.net
DNSSEC=no
EOF

systemctl restart systemd-resolved || true
echo "  Configured systemd-resolved to use public DNS (8.8.8.8, 8.8.4.4) with Tailscale fallback"

# --- Install MOTD ---

echo ""
echo "[7/9] Installing BLACKBOX MOTD..."

# Disable default MOTD components
chmod -x /etc/update-motd.d/* 2>/dev/null || true

cp "${REPO_DIR}/motd/blackbox-motd.sh" /etc/update-motd.d/00-blackbox
chmod +x /etc/update-motd.d/00-blackbox

echo "  Done."

# --- Set hostname ---

echo ""
echo "[8/9] Setting hostname to 'blackbox'..."

CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" != "blackbox" ]]; then
  hostnamectl set-hostname blackbox
  sed -i "s/${CURRENT_HOSTNAME}/blackbox/g" /etc/hosts
  echo "  Hostname changed from '${CURRENT_HOSTNAME}' to 'blackbox'"
else
  echo "  Hostname already set to 'blackbox'."
fi

# --- Generate Mosquitto password file ---

echo ""
echo "[9/9] Generating Mosquitto password file..."

MQTT_PASSWD_FILE="${REPO_DIR}/mosquitto/config/passwd"
if [[ -z "${MQTT_USER:-}" || -z "${MQTT_PASS:-}" ]]; then
  echo "  Warning: MQTT_USER or MQTT_PASS not set in .env — skipping."
  echo "  Frigate <-> HA MQTT will fail until this file exists."
elif [[ -f "$MQTT_PASSWD_FILE" ]]; then
  echo "  Already exists at ${MQTT_PASSWD_FILE}. Delete it to regenerate."
else
  docker run --rm \
    -v "${REPO_DIR}/mosquitto/config:/mosquitto/config" \
    eclipse-mosquitto:2 \
    mosquitto_passwd -b -c /mosquitto/config/passwd "$MQTT_USER" "$MQTT_PASS"
  chmod 600 "$MQTT_PASSWD_FILE"
  echo "  Created ${MQTT_PASSWD_FILE} (hashed)"
fi

echo ""
echo "========================================="
echo "  BLACKBOX — Setup complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Log out and back in (for docker group membership)"
echo "  2. cd ${REPO_DIR}"
echo "  3. docker compose up -d"
echo "  4. Join the tailnet (one-time, if not already):"
echo "       sudo tailscale up --hostname=blackbox \\"
echo "         --advertise-routes=192.168.1.0/24 \\"
echo "         --advertise-tags=tag:server"
echo "     Then in the Tailscale admin console:"
echo "       - Define tag:server in the ACL policy"
echo "       - Approve the 192.168.1.0/24 subnet route from blackbox"
echo "       - Disable key expiry for the blackbox node"
echo "       - Enable MagicDNS"
echo ""
