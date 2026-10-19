#!/usr/bin/env bash
# Phase 2 system-wide installs. Run with: sudo bash scripts/phase2_install.sh
# Changes: apt repo + nvidia-container-toolkit, /etc/docker/daemon.json (nvidia runtime), restarts docker, installs k3s (systemd service).
# Does NOT install the NVIDIA GPU Operator or any driver. The driver is the host driver (Windows on WSL2, native on Ubuntu).
set -euo pipefail
t0=$(date +%s)

echo "[1/3] NVIDIA Container Toolkit"
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -qq
apt-get install -y nvidia-container-toolkit

echo "[2/3] Docker runtime"
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

echo "[3/3] k3s (single node, containerd). It auto-detects nvidia-container-runtime on PATH."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -

echo "done in $(( $(date +%s) - t0 ))s"
