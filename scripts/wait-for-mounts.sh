#!/usr/bin/env bash
# ==============================================================================
# BLACKBOX — Wait for NAS Mounts
# Ensures all required NAS mounts are ready before Docker services start
# Used as a pre-start check to prevent Plex unavailability issues
# ==============================================================================

set -euo pipefail

# These paths are where the NAS volumes are mounted inside the Plex container
REQUIRED_VOLUMES=(
  "/media/Movies"
  "/media/TV Shows"
)

TIMEOUT=300  # 5 minutes
ELAPSED=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Waiting for NAS mounts to be ready..."

while [[ $ELAPSED -lt $TIMEOUT ]]; do
  ALL_READY=true
  
  for volume in "${REQUIRED_VOLUMES[@]}"; do
    # Check if directory exists and is readable
    if ! [[ -d "$volume" ]] || ! [[ -r "$volume" ]]; then
      log "  ⏳ Waiting for: $volume"
      ALL_READY=false
      break
    fi
  done
  
  if [[ "$ALL_READY" == true ]]; then
    log "✓ All NAS mounts are ready!"
    exit 0
  fi
  
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

log "✗ Timeout waiting for NAS mounts (${TIMEOUT}s elapsed)"
log "The following volumes may not be accessible:"
for volume in "${REQUIRED_VOLUMES[@]}"; do
  if ! [[ -d "$volume" ]] || ! [[ -r "$volume" ]]; then
    log "  - $volume"
  fi
done

exit 1
