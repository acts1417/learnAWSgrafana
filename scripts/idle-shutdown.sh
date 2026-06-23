#!/bin/bash
# Stops the instance once Open WebUI has had no real requests for
# IDLE_MINUTES. "Real" activity excludes the frontend's periodic
# GET /_app/version.json poll, which fires every ~60s regardless of
# whether anyone is actually using the UI.
# BOINC is not consulted — stopping the instance pauses it too.
# Runs as a systemd service (idle-shutdown.service).

set -euo pipefail

CONTAINER="open-webui"
IDLE_MINUTES=30
CHECK_INTERVAL=300 # 5 minutes
LOG_TAG="idle-shutdown"

log() {
  logger -t "$LOG_TAG" "$1"
  echo "$(date -Iseconds)  $1"
}

log "Idle-shutdown monitor started (PID $$), threshold ${IDLE_MINUTES}m"

while true; do
  STARTED_AT=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER")
  UPTIME_SECONDS=$(($(date +%s) - $(date -d "$STARTED_AT" +%s)))

  if [ "$UPTIME_SECONDS" -lt $((IDLE_MINUTES * 60)) ]; then
    log "Container up $((UPTIME_SECONDS / 60))m — under ${IDLE_MINUTES}m grace period, skipping check."
  else
    ACTIVITY=$(docker logs --since "${IDLE_MINUTES}m" "$CONTAINER" 2>&1 \
      | grep -v '/_app/version.json' \
      | grep -E '"[A-Z]+ .* HTTP/1\.[01]" [0-9]{3}' || true)

    if [ -z "$ACTIVITY" ]; then
      log "No Open WebUI requests in the last ${IDLE_MINUTES}m — stopping instance."
      sync
      shutdown -h now
      exit 0
    fi
  fi

  sleep "$CHECK_INTERVAL"
done
