#!/usr/bin/env bash
# Intro for the recording: shows the setup code, traditional pieces first, then the Kubernetes + NVIDIA pieces. Nothing is run or changed.
# usage: bash scripts/demo/0-tour.sh        (Enter between sections; AUTO=1 straight through)
source "$(dirname "$0")/common.sh"
view() { echo; echo "${YEL}# $1${R}"; sed -n "${2:-1,40}p" "$1" | cut -c1-150; }
step 0 "Setup tour: what we set up, as code"
echo "${B}Traditional: scripts and a pinned environment${R}"
view scripts/requirements-trad.lock 1,8; say "  ... $(wc -l < scripts/requirements-trad.lock) pinned packages in total"
view scripts/serve.sh 1,10
view scripts/train.py 1,14
pause
echo "${B}Kubernetes + NVIDIA: Helm for the platform, manifests for the workloads${R}"
echo; echo "${YEL}# GPU Operator, one Helm install (driver and toolkit come from the host)${R}"
echo "helm install gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace --version $(helm list -n gpu-operator -o json | jq -r '.[0].chart' | sed 's/gpu-operator-//') \\"
echo "  --set driver.enabled=false --set toolkit.enabled=false"
echo; echo "${YEL}# Monitoring, one Helm install (values file)${R}"; sed -n 1,25p k8s/monitoring-values.yaml | cut -c1-120
view docker/Dockerfile.train 1,12
view k8s/pvc.yaml 1,20
view k8s/train-job.yaml 1,30
pause
echo "${B}Everything in this repo, by kind${R}"
printf '  %-28s %s\n' "Dockerfiles:" "$(ls docker | tr '\n' ' ')"
printf '  %-28s %s\n' "Kubernetes manifests:" "$(ls k8s/*.yaml | wc -l) files in k8s/"
printf '  %-28s %s\n' "Helm releases:" "$(helm list -A --no-headers | awk '{print $1}' | tr '\n' ' ')"
printf '  %-28s %s\n' "Dashboards as code:" "$(ls k8s/dashboards | tr '\n' ' ')"
note "Images are the one-time cost: builds measured at 258 s (training) and 601 s (serving)."
