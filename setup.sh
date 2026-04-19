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
echo "[1/6] Installing Docker..."

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
echo "[2/6] Creating service config directories..."

mkdir -p "${REPO_DIR}/plex/config"
mkdir -p "${REPO_DIR}/homeassistant/config"
mkdir -p "${REPO_DIR}/pihole/etc-pihole"
mkdir -p "${REPO_DIR}/pihole/etc-dnsmasq.d"

echo "  Done."

# --- Mount NAS shares ---

echo ""
echo "[3/6] Mounting NAS shares..."

apt-get install -y -qq cifs-utils

# Public/Media/Movies (guest access)
mkdir -p "/mnt/Public/Media/Movies"
if ! grep -q "//192.168.1.100/Public/Media/Movies" /etc/fstab; then
  echo '//192.168.1.100/Public/Media/Movies /mnt/Public/Media/Movies cifs guest,iocharset=utf8,uid='"${PUID:-1000}"',gid='"${PGID:-1000}"',nofail,_netdev 0 0' >> /etc/fstab
  echo "  Added /mnt/Public/Media/Movies to fstab"
fi

# Public/Media/TV Shows (guest access)
mkdir -p "/mnt/Public/Media/TV Shows"
if ! grep -q "Public/Media/TV" /etc/fstab; then
  echo '//192.168.1.100/Public/Media/TV\040Shows /mnt/Public/Media/TV\040Shows cifs guest,iocharset=utf8,uid='"${PUID:-1000}"',gid='"${PGID:-1000}"',nofail,_netdev 0 0' >> /etc/fstab
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

  if ! grep -q "//192.168.1.100/Cameras" /etc/fstab; then
    echo "//192.168.1.100/Cameras /mnt/Cameras cifs credentials=${CREDS_FILE},iocharset=utf8,uid=${PUID:-1000},gid=${PGID:-1000},nofail,_netdev 0 0" >> /etc/fstab
    echo "  Added /mnt/Cameras to fstab (authenticated)"
  fi
fi

mount -a || echo "  Warning: mount -a had errors. Check NAS connectivity."
echo "  Done."

# --- Blacklist mt76x2u WiFi driver ---

echo ""
echo "[4/6] Blacklisting mt76x2u WiFi driver..."

BLACKLIST_FILE="/etc/modprobe.d/blacklist-mt76x2u.conf"
if [[ ! -f "$BLACKLIST_FILE" ]]; then
  echo "blacklist mt76x2u" > "$BLACKLIST_FILE"
  echo "  Created ${BLACKLIST_FILE}"
else
  echo "  Already blacklisted."
fi

# --- Install MOTD ---

echo ""
echo "[5/6] Installing BLACKBOX MOTD..."

# Disable default MOTD components
chmod -x /etc/update-motd.d/* 2>/dev/null || true

cp "${REPO_DIR}/motd/blackbox-motd.sh" /etc/update-motd.d/00-blackbox
chmod +x /etc/update-motd.d/00-blackbox

echo "  Done."

# --- Set hostname ---

echo ""
echo "[6/6] Setting hostname to 'blackbox'..."

CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" != "blackbox" ]]; then
  hostnamectl set-hostname blackbox
  sed -i "s/${CURRENT_HOSTNAME}/blackbox/g" /etc/hosts
  echo "  Hostname changed from '${CURRENT_HOSTNAME}' to 'blackbox'"
else
  echo "  Hostname already set to 'blackbox'."
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
echo ""
