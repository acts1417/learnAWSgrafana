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
# DLAMI ships with 4 CUDA toolkit versions (~41GB total). Containers bring their
# own CUDA libs; only the driver is needed on the host. Keep the newest, drop the rest.
echo "Cleaning up old CUDA toolkit versions..."
for ver in 12.6 12.8 12.9; do
  if [ -d "/usr/local/cuda-$${ver}" ]; then
    rm -rf "/usr/local/cuda-$${ver}"
    echo "  removed cuda-$${ver}"
  fi
done

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
BRANCH="claude/setup-aws-boinc-grafana-digQH"

# GIT_TERMINAL_PROMPT=0 prevents git from hanging waiting for credentials
# in a headless environment. Requires the repo to be public.
export GIT_TERMINAL_PROMPT=0

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
WEBUI_SECRET_KEY=$(openssl rand -hex 32)
ENV
chmod 600 "$${REPO_DIR}/docker/.env"

# ── Start Docker Compose stack ────────────────────────────────────────────────
echo "Pulling container images (this takes a few minutes)..."
cd "$${REPO_DIR}/docker"
docker compose pull
docker compose up -d

# ── Docker Compose boot service ──────────────────────────────────────────────
# Ensures the stack restarts after any stop/start (weekend shutdowns, spot reclaim).
# Docker's own restart: unless-stopped handles container crashes, but this
# service guarantees docker compose up runs on every OS boot as a safety net.
cat > /etc/systemd/system/lab-stack.service <<UNIT
[Unit]
Description=Lab Docker Compose Stack
After=network-online.target docker.service
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

# ── Spot termination monitor ──────────────────────────────────────────────────
# On-demand instances don't receive spot interruption notices so the monitor
# is not installed. The script is kept in scripts/ for reference if spot is
# ever re-enabled (set use_spot = true in terraform.tfvars).

echo "========================================================"
echo "Lab setup complete: $(date)"
echo ""
echo "Services running:"
docker compose -f "$${REPO_DIR}/docker/docker-compose.yml" ps
echo ""
echo "Check GPU:"
nvidia-smi
echo "========================================================"
