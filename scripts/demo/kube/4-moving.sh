#!/usr/bin/env bash
# Metric 4 of 6, Kubernetes + NVIDIA: same manifests elsewhere. Live: server-side validation of the 4 manifests, cluster facts, diff against the WSL2 branch.
# usage: bash scripts/demo/kube/4-moving.sh        (about 30 seconds)
source "$(dirname "$0")/../common.sh"
step 4 "Moving (Kubernetes + NVIDIA)"
fix "Kubernetes is a standard API, so the same manifests apply on any conformant cluster. The host differences stay below it."
echo "${B}This cluster${R}"
say "  server:   $(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion')"
say "  node:     $(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.osImage} / kernel {.items[0].status.nodeInfo.kernelVersion} / {.items[0].status.nodeInfo.containerRuntimeVersion}')"
say "  GPU:      $(kubectl get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.labels.nvidia\.com/gpu\.product}'), driver $(kubectl get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.labels.nvidia\.com/cuda\.driver-version\.full}')"
echo "${B}The 4 manifests validated by the API server (nothing is created)${R}"
for f in pvc train-job serve-deployment time-slicing-config; do printf '  %-24s ' k8s/$f.yaml; kubectl apply --dry-run=server -f k8s/$f.yaml 2>&1 | tail -1 | cut -c1-90; done
echo "${B}Same files on the WSL2 machine? Lines changed between the WSL2 branch and this one${R}"
show git diff --stat wsl ubuntu-4070 -- k8s/train-job.yaml k8s/serve-deployment.yaml k8s/pvc.yaml k8s/time-slicing-config.yaml
CH=$(git diff --numstat wsl ubuntu-4070 -- k8s/train-job.yaml k8s/serve-deployment.yaml k8s/pvc.yaml k8s/time-slicing-config.yaml | awk '{s+=$1+$2} END{print s+0}')
echo "(no diff lines above means 0 changed lines)"
echo "${B}What differed underneath (host level, from results-ubuntu-4070.md)${R}"
say "  WSL2 needed 3 Operator workarounds; native Ubuntu needed 0 (the Operator's toolkit installer must stay off on k3s: it overwrote k3s's containerd config)."
say "  Same Helm install, same manifests; the difference sits below the Kubernetes API."
echo "${B}Scoreboard: moving, Kubernetes${R}"
echo "  manifests changed between WSL2 and native Ubuntu:  $CH lines in 4 files"
echo "  Operator workarounds: 3 on WSL2, 0 on native Ubuntu (host-level, not manifest changes)"
echo "  another cloud:  not run"
result "Moving" "$CH changed lines in 4 manifests between WSL2 and native Ubuntu; the API server accepts them as they are; another cloud not run"
