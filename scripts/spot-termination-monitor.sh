#!/bin/bash
# Polls the AWS instance metadata endpoint every 5 seconds for a spot
# termination notice.  When AWS signals reclamation (2-minute warning):
#   1. Checkpoints and quits BOINC cleanly
#   2. Stops all Docker Compose services gracefully
#   3. Syncs filesystems
# Runs as a systemd service (spot-termination-monitor.service).

set -euo pipefail

METADATA_URL="http://169.254.169.254/latest/meta-data/spot/termination-time"
COMPOSE_DIR="/opt/lab/docker"
BOINC_CONTAINER="boinc"
LOG_TAG="spot-monitor"

log() {
  logger -t "$LOG_TAG" "$1"
  echo "$(date -Iseconds)  $1"
}

get_imdsv2_token() {
  # IMDSv2 requires a session token — more secure than IMDSv1 (no token).
  curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
    --connect-timeout 2 --max-time 5 2>/dev/null || echo ""
}

log "Spot termination monitor started (PID $$)"

while true; do
  TOKEN=$(get_imdsv2_token)

  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-aws-ec2-metadata-token: $TOKEN" \
    --connect-timeout 2 --max-time 5 \
    "$METADATA_URL" 2>/dev/null || echo "000")

  if [ "$HTTP_STATUS" = "200" ]; then
    TERM_TIME=$(curl -s \
      -H "X-aws-ec2-metadata-token: $TOKEN" \
      --connect-timeout 2 \
      "$METADATA_URL" 2>/dev/null || echo "unknown")

    log "⚠️  SPOT TERMINATION NOTICE — instance stops at: $TERM_TIME"
    log "You have ~2 minutes. Starting graceful shutdown..."

    # Step 1 — tell BOINC to checkpoint and exit
    log "Checkpointing BOINC..."
    docker exec "$BOINC_CONTAINER" boinccmd \
      --host localhost \
      --passwd "${BOINC_RPC_PASSWORD}" \
      --quit 2>/dev/null || true

    # Give BOINC a moment to write its checkpoint files to the EBS volume
    sleep 10

    # Step 2 — graceful stop of all services (volumes are NOT removed)
    log "Stopping Docker Compose stack..."
    cd "$COMPOSE_DIR" && docker compose stop

    # Step 3 — flush kernel buffers to disk
    log "Syncing filesystems..."
    sync

    log "Graceful shutdown complete. AWS will stop the instance momentarily."
    log "The EBS volume and persistent spot request survive. The instance will"
    log "restart automatically when spot capacity is available again."
    exit 0
  fi

  sleep 5
done
