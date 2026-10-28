#!/usr/bin/env bash
# Removes the Growing demo: CPU deployment, k3s nodes grow-*, Multipass VMs.
source "$(dirname "$0")/common.sh"
kubectl delete -f k8s/serve-cpu.yaml --ignore-not-found >/dev/null 2>&1
for n in $(kubectl get nodes -o name | grep grow-); do kubectl delete "$n" >/dev/null 2>&1; done
for v in $(multipass list --format csv 2>/dev/null | cut -d, -f1 | grep '^grow-'); do multipass delete --purge "$v"; done
kubectl get nodes; multipass list
