#!/usr/bin/env bash
# ==============================================================================
# BLACKBOX — Setup Tailscale Funnel for Remote Access
# Configures Tailscale Funnel to expose Frigate and Plex securely over internet
# ==============================================================================

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✗ ERROR: $*" >&2
  exit 1
}

# --- Preflight checks ---

log "Checking prerequisites..."

if ! command -v tailscale &>/dev/null; then
  error "Tailscale is not installed. Run setup.sh first."
fi

# Check if Tailscale is running
if ! tailscale status &>/dev/null; then
  error "Tailscale is not running. Start it with: sudo systemctl start tailscaled"
fi

# Get Tailnet name
TAILNET=$(tailscale status | grep -oE '[a-z0-9-]+\.ts\.net' | head -1 || true)
if [[ -z "$TAILNET" ]]; then
  error "Could not determine Tailnet name. Is Tailscale connected?"
fi

log "Tailnet: $TAILNET"

# --- Configure Funnel ---

log "Setting up Tailscale Funnel for Frigate (port 5000)..."
sudo tailscale serve https+insecure / http://localhost:5000 || error "Failed to configure Frigate Funnel"
log "✓ Frigate Funnel configured"
log "  Access at: https://blackbox.${TAILNET}:5000"

log "Setting up Tailscale Funnel for Plex (port 32400)..."
sudo tailscale serve https+insecure / http://localhost:32400 || error "Failed to configure Plex Funnel"
log "✓ Plex Funnel configured"
log "  Access at: https://blackbox.${TAILNET}:32400"

# --- Verify ---

log "Verifying Funnel configuration..."
if sudo tailscale serve status 2>&1 | grep -q "http://localhost:5000"; then
  log "✓ Frigate Funnel is active"
else
  error "Frigate Funnel verification failed"
fi

if sudo tailscale serve status 2>&1 | grep -q "http://localhost:32400"; then
  log "✓ Plex Funnel is active"
else
  error "Plex Funnel verification failed"
fi

log ""
log "========================================="
log "  Tailscale Funnel Setup Complete!"
log "========================================="
log ""
log "Remote access is now available:"
log "  • Frigate:  https://blackbox.${TAILNET}:5000"
log "  • Plex:     https://blackbox.${TAILNET}:32400"
log ""
log "Make sure Tailscale Funnel is enabled on your tailnet:"
log "  https://login.tailscale.com/admin/acls/funnel"
log ""
