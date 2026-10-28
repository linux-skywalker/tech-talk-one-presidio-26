#!/usr/bin/env bash
# Cleans up host files left behind by the GPU Operator with toolkit.enabled=true on k3s, then restarts k3s.
# Run with: sudo bash scripts/recover_after_toolkit_test.sh
# Symptom it fixes: node NotReady, "cni plugin not initialized" (the toolkit replaced k3s's containerd config with a 56 byte stub).
# Removes only files the Operator toolkit created. Does not touch /usr/bin/nvidia-* (the apt toolkit) or cluster data.
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
D=/var/lib/rancher/k3s/agent/etc/containerd
echo "== before"
ls -la $D; wc -c $D/config.toml $D/config.toml.tmpl 2>&1
ls -d /usr/local/nvidia /etc/containerd/conf.d/99-nvidia.toml /var/run/cdi/management.nvidia.com-gpu.yaml 2>&1

systemctl stop k3s
rm -f $D/config.toml.tmpl
rm -rf /usr/local/nvidia
rm -f /etc/containerd/conf.d/99-nvidia.toml /var/run/cdi/management.nvidia.com-gpu.yaml
systemctl start k3s

echo "== after"
sleep 10
wc -c $D/config.toml
ls /usr/local/nvidia 2>&1 | head -1
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
for i in $(seq 1 30); do s=$(k3s kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}'); [ "$s" = Ready ] && break; sleep 5; done
echo "node: ${s:-unknown}"
