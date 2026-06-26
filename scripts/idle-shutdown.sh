#!/bin/bash
# Stops the instance once Open WebUI has had no real requests for
# IDLE_MINUTES. "Real" activity excludes the frontend's periodic
# GET /_app/version.json poll, which fires every ~60s regardless of
# whether anyone is actually using the UI.
# BOINC is not consulted — stopping the instance pauses it too.
# Runs as a systemd service (idle-shutdown.service).
#
# Writes STATUS_FILE on every check with the deadline for the next
# shutdown, so idle-status-server.service can serve a live countdown
# (see scripts/idle-status/index.html).

set -euo pipefail

CONTAINER="open-webui"
IDLE_MINUTES=30
CHECK_INTERVAL=300 # 5 minutes
LOG_TAG="idle-shutdown"
STATUS_FILE="/opt/lab/idle-status/status.json"

log() {
  logger -t "$LOG_TAG" "$1"
  echo "$(date -Iseconds)  $1"
}

write_status() {
  local last_activity_epoch="$1" state="$2"
  local shutdown_at_epoch=$((last_activity_epoch + IDLE_MINUTES * 60))
  mkdir -p "$(dirname "$STATUS_FILE")"
  cat >"$STATUS_FILE" <<EOF
{"last_activity_epoch": $last_activity_epoch, "shutdown_at_epoch": $shutdown_at_epoch, "idle_minutes": $IDLE_MINUTES, "checked_at_epoch": $(date +%s), "state": "$state"}
EOF
}

log "Idle-shutdown monitor started (PID $$), threshold ${IDLE_MINUTES}m"

while true; do
  STARTED_AT=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER")
  STARTED_AT_EPOCH=$(date -d "$STARTED_AT" +%s)
  NOW_EPOCH=$(date +%s)

  # Last "real" request in the trailing IDLE_MINUTES window, or container
  # start time if there's been none — same deadline either way: most
  # recent known activity + IDLE_MINUTES.
  LAST_LINE=$(docker logs --since "${IDLE_MINUTES}m" "$CONTAINER" 2>&1 \
    | grep -v '/_app/version.json' \
    | grep -E '"[A-Z]+ .* HTTP/1\.[01]" [0-9]{3}' \
    | tail -1 || true)

  if [ -n "$LAST_LINE" ]; then
    LAST_ACTIVITY_EPOCH=$(date -d "$(echo "$LAST_LINE" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}')" +%s)
  else
    LAST_ACTIVITY_EPOCH=$STARTED_AT_EPOCH
  fi

  IDLE_SECONDS=$((NOW_EPOCH - LAST_ACTIVITY_EPOCH))
  UPTIME_SECONDS=$((NOW_EPOCH - STARTED_AT_EPOCH))

  if [ "$IDLE_SECONDS" -ge $((IDLE_MINUTES * 60)) ] && [ "$UPTIME_SECONDS" -ge $((IDLE_MINUTES * 60)) ]; then
    write_status "$LAST_ACTIVITY_EPOCH" "shutting_down"
    log "No Open WebUI requests in the last ${IDLE_MINUTES}m — stopping instance."
    sync
    shutdown -h now
    exit 0
  else
    write_status "$LAST_ACTIVITY_EPOCH" "active"
    log "Idle for $((IDLE_SECONDS / 60))m of ${IDLE_MINUTES}m threshold."
  fi

  sleep "$CHECK_INTERVAL"
done
