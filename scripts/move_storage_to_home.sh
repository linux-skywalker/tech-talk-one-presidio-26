#!/usr/bin/env bash
# Moves Docker and k3s storage from the small root partition to /home (bind mounts, paths stay identical).
# Run with: sudo bash scripts/move_storage_to_home.sh
# Changes: stops k3s and docker, copies /var/lib/docker and /var/lib/rancher/k3s to /home/storage,
#          renames the originals to *.premove (NOT deleted), adds two bind mounts to /etc/fstab, restarts both.
# Kubernetes pods and the cluster state are kept. Pods restart. The local registry container restarts too.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
mountpoint -q /home || { echo "/home is not a separate mount"; exit 1; }
avail=$(df --output=avail -BG /home | tail -1 | tr -dc 0-9)
[ "$avail" -ge 60 ] || { echo "need 60 GB free on /home, have ${avail}"; exit 1; }
t0=$(date +%s)

echo "[1/6] stop k3s and docker"
systemctl stop k3s
k3s-killall.sh >/dev/null 2>&1 || true
systemctl stop docker docker.socket

echo "[2/6] copy data to /home/storage (several minutes)"
mkdir -p /home/storage/docker /home/storage/k3s
rsync -aHAXx --info=progress2 /var/lib/docker/ /home/storage/docker/
rsync -aHAXx --info=progress2 /var/lib/rancher/k3s/ /home/storage/k3s/

echo "[3/6] keep the originals as *.premove and create empty mount points"
mv /var/lib/docker /var/lib/docker.premove
mv /var/lib/rancher/k3s /var/lib/rancher/k3s.premove
mkdir /var/lib/docker /var/lib/rancher/k3s

echo "[4/6] fstab bind mounts"
grep -q '/home/storage/docker' /etc/fstab || echo '/home/storage/docker /var/lib/docker none bind,x-systemd.requires-mounts-for=/home 0 0' >> /etc/fstab
grep -q '/home/storage/k3s' /etc/fstab || echo '/home/storage/k3s /var/lib/rancher/k3s none bind,x-systemd.requires-mounts-for=/home 0 0' >> /etc/fstab
systemctl daemon-reload
mount /var/lib/docker
mount /var/lib/rancher/k3s

echo "[5/6] start docker and k3s"
systemctl start docker
systemctl start k3s

echo "[6/6] result"
findmnt -no SOURCE,TARGET /var/lib/docker /var/lib/rancher/k3s
df -h / /home | awk '{print $1,$2,$3,$4,$5,$6}'
echo "done in $(( $(date +%s) - t0 ))s. After checking that docker and k3s work, free the old copies with:"
echo "  sudo rm -rf /var/lib/docker.premove /var/lib/rancher/k3s.premove"
