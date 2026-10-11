#!/usr/bin/env bash
# ==============================================================================
# BLACKBOX — Wait for NAS Mounts
# Ensures all required NAS mounts are ready before Docker services start
# Used as a pre-start check to prevent Plex unavailability issues
# ==============================================================================

set -euo pipefail

REQUIRED_MOUNTS=(
  "/mnt/Public/Media/Movies"
  "/mnt/Public/Media/TV Shows"
)

TIMEOUT=300  # 5 minutes
ELAPSED=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Waiting for NAS mounts to be ready..."

while [[ $ELAPSED -lt $TIMEOUT ]]; do
  ALL_MOUNTED=true
  
  for mount in "${REQUIRED_MOUNTS[@]}"; do
    # Check if directory exists and is readable (not just a mountpoint check)
    # Inside container, volumes appear as regular directories, not mountpoints
    if ! [[ -d "$mount" ]] || ! [[ -r "$mount" ]]; then
      log "  ⏳ Waiting for: $mount"
      ALL_MOUNTED=false
      break
    fi
  done
  
  if [[ "$ALL_MOUNTED" == true ]]; then
    log "✓ All NAS mounts are ready!"
    exit 0
  fi
  
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

log "✗ Timeout waiting for NAS mounts (${TIMEOUT}s elapsed)"
log "The following mounts may not be accessible:"
for mount in "${REQUIRED_MOUNTS[@]}"; do
  if ! [[ -d "$mount" ]] || ! [[ -r "$mount" ]]; then
    log "  - $mount"
  fi
done

exit 1
