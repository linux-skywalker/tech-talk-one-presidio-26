#!/usr/bin/env bash
# Growing demo: add Multipass VM workers one at a time, each joins the k3s cluster and runs one CPU-only copy of the smallest model.
# Measures time from "launch" to node Ready to model ready, and total requests/s with 1, 2, 3 VMs. CPU replicas, NOT GPU.
# usage: bash scripts/demo/vm-grow.sh [N]      (N VMs, default 3; AUTO=1 for no pauses)
# One-time: sudo cat /var/lib/rancher/k3s/server/node-token | install -m 600 /dev/stdin ~/.k3s-node-token   (run by you; the token never goes in the repo)
source "$(dirname "$0")/common.sh"
N=${1:-3}; TOKEN_FILE=${TOKEN_FILE:-$HOME/.k3s-node-token}
HOSTIP=$(hostname -I | awk '{print $1}'); ERR=$(mktemp)
# multipassd cannot reach the Ubuntu image server on this machine, so launch from a local copy of the cloud image (downloaded with curl)
IMAGE=${IMAGE:-file://$HOME/multipass-images/noble-server-cloudimg-amd64.img}; MODEL_FILE=${MODEL_FILE:-$HOME/multipass-images/SmolLM2-135M-Instruct-Q8_0.gguf}; K3S_BIN=$HOME/multipass-images/k3s; IMG_TAR=$HOME/multipass-images/llama-server.tar
[ -s "${IMAGE#file://}" ] && [ -s "$MODEL_FILE" ] && [ -s "$K3S_BIN" ] || { echo "Missing image or model file in ~/multipass-images (see vm-grow.sh)"; exit 1; }
[ -s "$TOKEN_FILE" ] || { echo "${RED}Missing $TOKEN_FILE.${R} Run: sudo cat /var/lib/rancher/k3s/server/node-token | install -m 600 /dev/stdin $TOKEN_FILE"; exit 1; }
command -v multipass >/dev/null || { echo "multipass not installed"; exit 1; }
load() { # load <requests> <parallel>: prints "<ok>/<total> ok, <requests per second counting only successful ones>"
  local t0=$(date +%s.%N) ok
  ok=$(seq 1 "$1" | xargs -P "$2" -I{} curl -s -m 60 -o /dev/null -w '%{http_code}\n' localhost:30100/v1/chat/completions -H 'Content-Type: application/json' \
    -d '{"messages":[{"role":"user","content":"Give one tip for staying focused."}],"max_tokens":32,"temperature":0}' | grep -c '^200$')
  python3 -c "print(f'{$ok}/{$1} ok, {round($ok/($(date +%s.%N)-$t0),1)} requests/s')"
}

step 6 "Growing"
fix "A new machine joins the cluster with one command and the scheduler uses it. Here: $N small VMs added one at a time, each runs one CPU copy of the smallest model. CPU replicas, not GPU."
show kubectl get nodes
kubectl apply -f k8s/serve-cpu.yaml >/dev/null; kubectl scale deployment/serve-cpu --replicas=0 >/dev/null
for k in $(seq 1 "$N"); do
  T0=$(date +%s)
  say "${B}Adding VM grow-$k${R}"
  multipass launch "$IMAGE" --name grow-$k --cpus 2 --memory 3G --disk 10G >/dev/null 2>"$ERR" || { echo "${RED}launch failed:${R} $(tail -2 "$ERR")"; exit 1; }
  multipass exec grow-$k -- sudo mkdir -p /opt/models >/dev/null 2>&1
  multipass transfer "$MODEL_FILE" grow-$k:/tmp/model.gguf >/dev/null && multipass exec grow-$k -- sudo mv /tmp/model.gguf /opt/models/SmolLM2-135M-Instruct-Q8_0.gguf
  LAUNCHED=$(( $(date +%s)-T0 ))
  # GitHub downloads are slow here, so give the VM this host's k3s binary (same version as the server) and skip the download
  multipass transfer "$K3S_BIN" grow-$k:/tmp/k3s >/dev/null && multipass exec grow-$k -- sudo install -m 755 /tmp/k3s /usr/local/bin/k3s
  multipass exec grow-$k -- sudo bash -c "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_DOWNLOAD=true K3S_URL=https://$HOSTIP:6443 K3S_TOKEN=$(cat "$TOKEN_FILE") INSTALL_K3S_EXEC='agent --node-label role=cpu-worker' sh -" >/dev/null 2>&1
  OK=""; for t in $(seq 1 180); do kubectl get node grow-$k --no-headers 2>/dev/null | grep -qw Ready && { OK=1; break; }; sleep 1; done
  [ -n "$OK" ] || { echo "${RED}grow-$k did not become Ready in 180 s. Stopping.${R}"; multipass exec grow-$k -- sudo systemctl status k3s-agent --no-pager 2>&1 | tail -5; exit 1; }
  READY=$(( $(date +%s)-T0 ))
  # ghcr.io is slow here (a 310 MB pull took 8 min), so load the llama.cpp server image from a local tar instead of pulling it
  [ -s "$IMG_TAR" ] && multipass transfer "$IMG_TAR" grow-$k:/tmp/llama.tar >/dev/null && multipass exec grow-$k -- sudo k3s ctr -n k8s.io images import /tmp/llama.tar >/dev/null 2>&1
  kubectl scale deployment/serve-cpu --replicas=$k >/dev/null
  OK=""; for t in $(seq 1 150); do [ "$(kubectl get deployment serve-cpu -o jsonpath='{.status.readyReplicas}')" = "$k" ] && { OK=1; break; }; sleep 2; done
  [ -n "$OK" ] || { echo "${RED}serve-cpu not ready with $k replicas in 300 s. Stopping.${R}"; kubectl get pods -l app=serve-cpu -o wide; kubectl describe pod -l app=serve-cpu | tail -8; exit 1; }
  MODEL=$(( $(date +%s)-T0 ))
  show kubectl get nodes
  show kubectl get pods -l app=serve-cpu -o wide
  RPS=$(load 60 8)
  echo "  $k VM(s): VM up ${LAUNCHED} s, node Ready ${READY} s, model serving ${MODEL} s, ${RPS} (60 requests, 8 at a time)"
  result "Growing $k" "$k VM(s): node Ready ${READY} s after launch, serving at ${MODEL} s, ${RPS} (CPU replicas, not GPU)"
done
note "The GPU stays on the host node: pods that request nvidia.com/gpu still land there. The VMs have no GPU."
summary "Growing"
