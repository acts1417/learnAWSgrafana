#!/bin/bash
# Run once on a fresh instance to prepare storage, Docker, and the lab stack.
# Expected: a dedicated EBS data volume attached (e.g. /dev/nvme2n1 or /dev/xvdb).
# Pass the device as the first argument, e.g.: sudo ./bootstrap.sh /dev/nvme2n1

set -euo pipefail

DATA_DEVICE="${1:?Usage: $0 <data-device>  e.g. $0 /dev/nvme2n1}"
DATA_MOUNT="/data"
COMPOSE_DIR="/opt/lab/docker"

# ── 1. Mount the data EBS volume ─────────────────────────────────────────────
if ! blkid "$DATA_DEVICE" | grep -q ext4; then
  echo "Formatting $DATA_DEVICE as ext4 (first boot)..."
  mkfs.ext4 -L labdata "$DATA_DEVICE"
fi

mkdir -p "$DATA_MOUNT"

if ! mountpoint -q "$DATA_MOUNT"; then
  mount "$DATA_DEVICE" "$DATA_MOUNT"
fi

# Persist the mount across reboots
if ! grep -q "$DATA_DEVICE" /etc/fstab; then
  echo "$DATA_DEVICE  $DATA_MOUNT  ext4  defaults,nofail  0  2" >> /etc/fstab
fi

# ── 2. Create data directories ────────────────────────────────────────────────
mkdir -p \
  "$DATA_MOUNT/docker" \
  "$DATA_MOUNT/containerd" \
  "$DATA_MOUNT/ollama" \
  "$DATA_MOUNT/boinc" \
  "$DATA_MOUNT/prometheus" \
  "$DATA_MOUNT/grafana" \
  "$DATA_MOUNT/open-webui"

# ── 3. Configure Docker to use /data ─────────────────────────────────────────
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "$DATA_MOUNT/docker"
}
EOF

# ── 4. Configure containerd to use /data ─────────────────────────────────────
mkdir -p /etc/containerd
cat > /etc/containerd/config.toml <<EOF
version = 2
root = "$DATA_MOUNT/containerd"
EOF

# ── 5. Restart storage-aware services ────────────────────────────────────────
systemctl restart containerd
systemctl restart docker

# ── 6. Add ubuntu to docker group ────────────────────────────────────────────
usermod -aG docker ubuntu

# ── 7. Bring the lab stack up ─────────────────────────────────────────────────
cd "$COMPOSE_DIR"
sudo -u ubuntu docker compose up -d

echo ""
echo "Bootstrap complete. Data volume: $DATA_DEVICE → $DATA_MOUNT"
echo "Stack is up. Grafana: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
echo ""
echo "Pull an LLM model to get started:"
echo "  docker exec ollama ollama pull llama3.1:8b"
