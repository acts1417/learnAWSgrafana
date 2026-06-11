#!/bin/bash
# Bootstrap script — runs once on first boot as root.
# Progress is logged to /var/log/userdata.log — watch it with:
#   sudo tail -f /var/log/userdata.log
set -euo pipefail
exec >> /var/log/userdata.log 2>&1
chmod 600 /var/log/userdata.log

echo "========================================================"
echo "Lab setup started: $(date)"
echo "========================================================"

# ── System update ─────────────────────────────────────────────────────────────
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold"
apt-get install -y git curl ca-certificates gnupg

# ── DLAMI CUDA cleanup ────────────────────────────────────────────────────────
# DLAMI ships with several CUDA toolkit versions (~40GB). Containers bring their
# own CUDA libs; only the driver is needed on the host. Drop the toolkits.
echo "Cleaning up old CUDA toolkit versions..."
for ver in 12.6 12.8 12.9; do
  if [ -d "/usr/local/cuda-$${ver}" ]; then
    rm -rf "/usr/local/cuda-$${ver}"
    echo "  removed cuda-$${ver}"
  fi
done

# ── Persistent data volume (/data) ────────────────────────────────────────────
# A dedicated EBS volume (terraform aws_ebs_volume.data, attached at /dev/sdf)
# holds Docker's data-root so the 80GB root volume never fills with images/models.
# On Nitro, /dev/sdf surfaces as some /dev/nvme*n1 — detect it by EBS model,
# skipping the root disk and the ephemeral instance-store NVMe.
DATA_MOUNT=/data

find_data_device() {
  local root_src root_disk name model dev
  root_src=$(findmnt -no SOURCE /)
  root_disk="/dev/$(lsblk -no PKNAME "$${root_src}" | head -1)"
  while read -r name model; do
    dev="/dev/$${name}"
    [ "$${dev}" = "$${root_disk}" ] && continue
    # Skip any disk that already has a mountpoint
    if lsblk -no MOUNTPOINT "$${dev}" | grep -q .; then continue; fi
    # Match Amazon EBS (instance-store model is "Amazon EC2 NVMe Instance Storage")
    case "$${model}" in
      *Elastic*Block*Store*) echo "$${dev}"; return 0 ;;
    esac
  done < <(lsblk -dno NAME,MODEL)
  return 1
}

echo "Waiting for data EBS volume to attach..."
DATA_DEV=""
for _ in $(seq 1 30); do
  DATA_DEV=$(find_data_device || true)
  [ -n "$${DATA_DEV}" ] && break
  sleep 5
done

if [ -z "$${DATA_DEV}" ]; then
  echo "ERROR: data EBS volume not found after 150s — aborting so root volume is not filled."
  exit 1
fi
echo "Data volume detected at $${DATA_DEV}"

# Format only if it has no filesystem yet (preserves data when restored from snapshot)
if ! blkid "$${DATA_DEV}" >/dev/null 2>&1; then
  echo "No filesystem on $${DATA_DEV} — formatting ext4 (fresh volume)"
  mkfs.ext4 -L labdata "$${DATA_DEV}"
else
  echo "Existing filesystem on $${DATA_DEV} — keeping it (snapshot restore)"
fi

mkdir -p "$${DATA_MOUNT}"
mount "$${DATA_DEV}" "$${DATA_MOUNT}"

# Persist mount by UUID (device names can change across reboots)
DATA_UUID=$(blkid -s UUID -o value "$${DATA_DEV}")
if ! grep -q "$${DATA_UUID}" /etc/fstab; then
  echo "UUID=$${DATA_UUID}  $${DATA_MOUNT}  ext4  defaults,nofail  0  2" >> /etc/fstab
fi

mkdir -p "$${DATA_MOUNT}/docker"

# ── Docker ───────────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
fi

# Point Docker's data-root at /data BEFORE it starts pulling images.
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<JSON
{
  "data-root": "$${DATA_MOUNT}/docker"
}
JSON

systemctl enable docker
systemctl restart docker
usermod -aG docker ubuntu

# Docker Compose v2 plugin
if ! docker compose version &>/dev/null 2>&1; then
  apt-get install -y docker-compose-plugin
fi

# ── NVIDIA Container Toolkit ─────────────────────────────────────────────────
echo "Installing nvidia-container-toolkit..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --batch --yes --no-tty --dearmor \
        -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

DISTRO=$(. /etc/os-release && echo "$${ID}$${VERSION_ID}")
curl -sL "https://nvidia.github.io/libnvidia-container/$${DISTRO}/libnvidia-container.list" \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update -y
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# ── Clone repo ───────────────────────────────────────────────────────────────
REPO_DIR=/opt/lab
BRANCH="main"

# GIT_TERMINAL_PROMPT=0 prevents git from hanging on credentials in a headless env.
export GIT_TERMINAL_PROMPT=0

echo "Cloning repo to $${REPO_DIR}..."
if [ -d "$${REPO_DIR}/.git" ]; then
  git config --global --add safe.directory "$${REPO_DIR}"
  git -C "$${REPO_DIR}" fetch origin
  git -C "$${REPO_DIR}" checkout "$${BRANCH}"
  git -C "$${REPO_DIR}" pull origin "$${BRANCH}"
else
  git clone --branch "$${BRANCH}" ${repo_url} "$${REPO_DIR}"
fi
git config --global --add safe.directory "$${REPO_DIR}"
chown -R ubuntu:ubuntu "$${REPO_DIR}"

# ── Environment file ─────────────────────────────────────────────────────────
# Terraform renders these values at plan time — they never hit the git repo.
cat > "$${REPO_DIR}/docker/.env" <<ENV
BOINC_RPC_PASSWORD=${boinc_password}
GRAFANA_ADMIN_PASSWORD=${grafana_admin_password}
WEBUI_SECRET_KEY=$(openssl rand -hex 32)
ENV
chmod 600 "$${REPO_DIR}/docker/.env"

# ── Start Docker Compose stack ────────────────────────────────────────────────
echo "Building and pulling container images (this takes a few minutes)..."
cd "$${REPO_DIR}/docker"
docker compose build
docker compose up -d

# ── Docker Compose boot service ──────────────────────────────────────────────
# Restarts the stack on every OS boot (weekend shutdowns, instance start/stop).
# Requires /data to be mounted first (the named volumes live there).
cat > /etc/systemd/system/lab-stack.service <<UNIT
[Unit]
Description=Lab Docker Compose Stack
After=network-online.target docker.service data.mount
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$${REPO_DIR}/docker
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose stop
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable lab-stack

echo "========================================================"
echo "Lab setup complete: $(date)"
echo ""
echo "Storage:"
df -h / "$${DATA_MOUNT}"
echo ""
echo "Services running:"
docker compose -f "$${REPO_DIR}/docker/docker-compose.yml" ps
echo ""
echo "Check GPU:"
nvidia-smi
echo "========================================================"
