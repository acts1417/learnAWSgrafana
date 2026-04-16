#!/bin/bash
# Bootstrap script — runs once on first boot as root.
# Progress is logged to /var/log/userdata.log — watch it with:
#   sudo tail -f /var/log/userdata.log
set -euo pipefail
exec >> /var/log/userdata.log 2>&1

echo "========================================================"
echo "Lab setup started: $(date)"
echo "========================================================"

# ── System update ─────────────────────────────────────────────────────────────
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold"
apt-get install -y git curl ca-certificates gnupg

# ── Docker ───────────────────────────────────────────────────────────────────
# The DLAMI may already have Docker, but we ensure it's present and up to date.
if ! command -v docker &>/dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Docker Compose v2 plugin
if ! docker compose version &>/dev/null 2>&1; then
  apt-get install -y docker-compose-plugin
fi

# ── NVIDIA Container Toolkit ─────────────────────────────────────────────────
# Allows Docker containers to access the GPU via --gpus / deploy.resources
echo "Installing nvidia-container-toolkit..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

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
BRANCH="claude/setup-aws-boinc-grafana-digQH"

echo "Cloning repo to $${REPO_DIR}..."
if [ -d "$${REPO_DIR}/.git" ]; then
  git -C "$${REPO_DIR}" fetch origin
  git -C "$${REPO_DIR}" checkout "$${BRANCH}"
  git -C "$${REPO_DIR}" pull origin "$${BRANCH}"
else
  git clone --branch "$${BRANCH}" ${repo_url} "$${REPO_DIR}"
fi

# ── Environment file ─────────────────────────────────────────────────────────
# Terraform renders these values at plan time — they never hit the git repo.
cat > "$${REPO_DIR}/docker/.env" <<ENV
BOINC_RPC_PASSWORD=${boinc_password}
GRAFANA_ADMIN_PASSWORD=${grafana_admin_password}
ENV
chmod 600 "$${REPO_DIR}/docker/.env"

# ── Start Docker Compose stack ────────────────────────────────────────────────
echo "Pulling container images (this takes a few minutes)..."
cd "$${REPO_DIR}/docker"
docker compose pull
docker compose up -d

# ── Spot termination monitor ──────────────────────────────────────────────────
cp "$${REPO_DIR}/scripts/spot-termination-monitor.sh" /usr/local/bin/
chmod +x /usr/local/bin/spot-termination-monitor.sh

cat > /etc/systemd/system/spot-termination-monitor.service <<'UNIT'
[Unit]
Description=AWS Spot Instance Termination Monitor
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/spot-termination-monitor.sh
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable spot-termination-monitor
systemctl start spot-termination-monitor

echo "========================================================"
echo "Lab setup complete: $(date)"
echo ""
echo "Services running:"
docker compose -f "$${REPO_DIR}/docker/docker-compose.yml" ps
echo ""
echo "Check GPU:"
nvidia-smi
echo "========================================================"
