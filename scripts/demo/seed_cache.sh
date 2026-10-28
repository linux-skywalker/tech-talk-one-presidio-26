#!/usr/bin/env bash
# Keeps the PVC "work" warm so Kubernetes steps never wait on the internet: copies the models and dataset from this host's Hugging Face
# cache into /work/hf-cache once (marker file), and with --reset-outputs clears only the training outputs (checkpoints, adapter).
# usage: bash scripts/demo/seed_cache.sh [--reset-outputs]
source "$(dirname "$0")/common.sh"
SRC=$HOME/.cache/huggingface
kubectl apply -f k8s/pvc.yaml >/dev/null
helper() { # helper <shell command run inside a pod that mounts the PVC>; stdin is passed through
  kubectl delete pod seed --ignore-not-found --wait=true >/dev/null 2>&1
  kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: seed}
spec:
  restartPolicy: Never
  containers:
  - name: seed
    image: localhost:5000/gpu-train:v1
    command: ["sleep", "3600"]
    volumeMounts: [{name: work, mountPath: /work}]
  volumes: [{name: work, persistentVolumeClaim: {claimName: work}}]
YAML
  kubectl wait --for=condition=Ready pod/seed --timeout=180s >/dev/null || return 1
  kubectl exec -i seed -- sh -c "$1"; local rc=$?
  kubectl delete pod seed --wait=false >/dev/null 2>&1; return $rc
}
if [ "$1" = "--reset-outputs" ]; then helper 'rm -rf /work/outputs' </dev/null && echo "training outputs cleared (model cache kept)"; exit; fi
if helper 'test -f /work/hf-cache/.seeded' </dev/null 2>/dev/null; then echo "model cache already in the PVC"; exit 0; fi
echo "Seeding the PVC from $SRC (one time, a few minutes)..."
tar -C "$SRC" -ch --exclude=onnx hub/models--Qwen--Qwen2.5-1.5B-Instruct hub/models--HuggingFaceTB--SmolLM2-135M-Instruct hub/datasets--tatsu-lab--alpaca datasets \
 | helper 'mkdir -p /work/hf-cache && tar -C /work/hf-cache -x && touch /work/hf-cache/.seeded && du -sh /work/hf-cache' && echo "seeded"
