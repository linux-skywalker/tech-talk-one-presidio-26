#!/usr/bin/env bash
# Set up a fresh Ubuntu machine with an NVIDIA GPU for this repo. Safe to re-run, every stage skips what already exists.
# usage: bash scripts/bootstrap.sh <stage>      stages: check | sudo | user | cluster | images | models | verify | all | status
#   check    read-only: GPU, driver, disk, RAM, internet. Run this first.
#   sudo     prints the ONE block that needs sudo (you run it), then verifies the result. Never runs sudo itself.
#   user     per-user tools in ~/.local/bin (uv, helm, k9s) and the Python env .venv-trad (vLLM, trl, peft)
#   cluster  GPU Operator (driver and toolkit installers OFF), Grafana stack, local registry, dashboard
#   images   builds and pushes gpu-train:v1 and gpu-serve:v1 to localhost:5000 (about 14 min, about 21 GB)
#   models   downloads the model weights and dataset into the Hugging Face cache
#   verify   PASS/FAIL checks, ends with a GPU smoke pod
#   all      check, user, cluster, images, models, verify (run `sudo` stage and its block before this)
# Tested only on one machine (Ubuntu 24.04, RTX 4070 12 GB). Other machines may differ; failures are reported, not hidden.
cd "$(dirname "$0")/.." || exit 1
export PATH=$HOME/.local/bin:$PWD/.venv-trad/bin:$PATH KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
OPERATOR_VERSION=${OPERATOR_VERSION:-v26.7.2}; MONITORING_VERSION=${MONITORING_VERSION:-92.10.1}
HELM_VERSION=${HELM_VERSION:-v3.19.0}; K9S_VERSION=${K9S_VERSION:-v0.50.9}
PASS=0; FAIL=0; WARN=0
ok()   { PASS=$((PASS+1)); echo "[PASS] $*"; }
bad()  { FAIL=$((FAIL+1)); echo "[FAIL] $*"; }
warn() { WARN=$((WARN+1)); echo "[WARN] $*"; }
note() { echo "       $*"; }
stage() { echo; echo "=== $* ($(date +%H:%M:%S))"; }
chk()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
dk()   { docker "$@" 2>/dev/null || sg docker -c "docker $*"; }   # works before the shell is in the docker group
timed() { local t=$(date +%s); "$@"; local rc=$?; note "took $(( $(date +%s) - t )) s"; return $rc; }

do_check() {
  stage "check: this machine"
  . /etc/os-release; note "OS: $PRETTY_NAME, kernel $(uname -r)"
  [ "$ID" = ubuntu ] && ok "Ubuntu" || warn "not Ubuntu ($ID): scripts/phase2_install.sh uses apt"
  if command -v nvidia-smi >/dev/null && nvidia-smi >/dev/null 2>&1; then
    ok "GPU visible: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | head -1)"
    local drv; drv=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | cut -d. -f1)
    [ "${drv:-0}" -ge 580 ] && ok "driver $drv or newer (CUDA 13 images need R580+)" || bad "driver ${drv:-none} is older than R580: the CUDA 13 images will fail at CUDA init"
    local mem; mem=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
    [ "${mem:-0}" -ge 11000 ] && ok "GPU memory ${mem} MiB (tested with 12 GB)" || warn "GPU memory ${mem} MiB: demo fractions (GPU_UTIL) were tuned for 12 GB"
    nvidia-smi mig -lgip 2>&1 | grep -q "No MIG-supported" && note "MIG: not supported on this GPU (expected on RTX cards)" || note "MIG: check 'nvidia-smi mig -lgip'"
  else bad "no working nvidia-smi: install the NVIDIA driver (R580 or newer) first"; fi
  local free; free=$(df --output=avail -BG / | tail -1 | tr -dc 0-9)
  [ "$free" -ge 50 ] && ok "root disk ${free} GB free" || warn "root disk ${free} GB free: images and k3s need about 50 GB. Use scripts/move_storage_to_home.sh if /home is bigger"
  local ram; ram=$(free -g | awk '/Mem:/{print $2}')
  [ "$ram" -ge 16 ] && ok "RAM ${ram} GB" || warn "RAM ${ram} GB (tested with 31 GB)"
  [ -f /sys/fs/cgroup/cgroup.controllers ] && ok "cgroup v2" || warn "cgroup v1: untested"
  chk "internet reaches Hugging Face and the NVIDIA Helm repo" bash -c 'curl -sI -m 8 https://huggingface.co >/dev/null && curl -sI -m 8 https://helm.ngc.nvidia.com/nvidia/index.yaml >/dev/null'
}

do_sudo() {
  stage "sudo: system-wide installs (you run these, this script never does)"
  cat <<EOF
Run this block once, then log out and in (or use: sg docker -c "...") so the docker group applies:

  sudo apt-get update && sudo apt-get install -y python3-venv docker.io curl jq
  sudo usermod -aG docker \$USER
  sudo bash $PWD/scripts/phase2_install.sh      # NVIDIA container toolkit, docker nvidia runtime, k3s

Do NOT enable the Operator's toolkit installer afterwards: on our host it overwrote the k3s containerd config and broke the node.
EOF
  stage "sudo: verifying what is installed"
  chk "docker installed" command -v docker
  chk "nvidia-ctk installed" command -v nvidia-ctk
  chk "docker nvidia runtime registered" bash -c 'docker info 2>/dev/null | grep -qi nvidia || sg docker -c "docker info" 2>/dev/null | grep -qi nvidia'
  chk "k3s service active" bash -c 'systemctl is-active k3s | grep -qx active'
  chk "kubeconfig readable" test -r "$KUBECONFIG"
  chk "jq installed" command -v jq
}

do_user() {
  stage "user: tools in ~/.local/bin"
  mkdir -p ~/.local/bin
  if ! command -v uv >/dev/null; then timed pip install --user --break-system-packages -q uv; fi
  chk "uv" command -v uv
  if ! command -v helm >/dev/null; then
    timed bash -c "curl -fsSL https://get.helm.sh/helm-$HELM_VERSION-linux-amd64.tar.gz | tar -xz -C /tmp linux-amd64/helm && mv /tmp/linux-amd64/helm ~/.local/bin/helm"
  fi
  chk "helm" helm version --short
  if ! command -v k9s >/dev/null; then
    timed bash -c "curl -fsSL https://github.com/derailed/k9s/releases/download/$K9S_VERSION/k9s_Linux_amd64.tar.gz | tar -xz -C ~/.local/bin k9s"
  fi
  chk "k9s" command -v k9s
  stage "user: Python env .venv-trad (vLLM, trl, peft)"
  if [ ! -x .venv-trad/bin/python ]; then timed uv venv .venv-trad --python 3.10; fi
  if ! .venv-trad/bin/python -c 'import vllm, trl, peft' 2>/dev/null; then
    timed uv pip install --python .venv-trad/bin/python "vllm==0.31.0" "trl==1.14.2" "peft==0.21.2" datasets accelerate
  fi
  chk "vLLM, trl, peft import" .venv-trad/bin/python -c 'import vllm, trl, peft'
  chk "torch sees the GPU" .venv-trad/bin/python -c 'import torch; assert torch.cuda.is_available()'
}

do_cluster() {
  stage "cluster: node and Helm repos"
  chk "node Ready" bash -c 'kubectl get nodes --no-headers | grep -qw Ready'
  helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null 2>&1
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
  helm repo update >/dev/null 2>&1
  stage "cluster: GPU Operator $OPERATOR_VERSION (driver and toolkit installers OFF)"
  if ! helm status gpu-operator -n gpu-operator >/dev/null 2>&1; then
    timed helm upgrade --install gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace --version "$OPERATOR_VERSION" \
      --set driver.enabled=false --set toolkit.enabled=false \
      --set 'dcgmExporter.env[0].name=DCGM_EXPORTER_INTERVAL' --set-string 'dcgmExporter.env[0].value=1000' >/dev/null
  else note "already installed"; fi
  local t=$(date +%s)
  for i in $(seq 1 120); do [ "$(kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null)" = 1 ] && break; sleep 3; done
  [ "$(kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null)" = 1 ] \
    && ok "node advertises nvidia.com/gpu: 1 ($(( $(date +%s) - t )) s wait)" \
    || bad "nvidia.com/gpu never appeared: kubectl get pods -n gpu-operator; kubectl describe node | grep -i nvidia"
  stage "cluster: Grafana and Prometheus"
  if ! helm status monitoring -n monitoring >/dev/null 2>&1; then
    timed helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace \
      --version "$MONITORING_VERSION" -f k8s/monitoring-values.yaml >/dev/null
  else note "already installed"; fi
  for i in $(seq 1 60); do [ "$(curl -s -o /dev/null -w '%{http_code}' localhost:30300/login)" = 200 ] && break; sleep 3; done
  chk "Grafana answers on :30300" bash -c '[ "$(curl -s -o /dev/null -w "%{http_code}" localhost:30300/login)" = 200 ]'
  GRAFANA=localhost:30300 bash scripts/import_dashboard.sh >/dev/null 2>&1 && ok "DCGM dashboard imported" || warn "dashboard import failed: rerun scripts/import_dashboard.sh later"
  bash scripts/import_review_dashboard.sh >/dev/null 2>&1 && ok "review dashboard imported (/d/gpu-review)" || warn "review dashboard import failed: rerun scripts/import_review_dashboard.sh later"
  stage "cluster: local image registry on :5000"
  if ! dk ps --format '{{.Names}}' | grep -qx registry; then timed dk run -d -p 5000:5000 --restart always --name registry registry:2 >/dev/null; else note "already running"; fi
  chk "registry answers" bash -c 'curl -s localhost:5000/v2/_catalog | grep -q repositories'
}

do_images() {
  stage "images: build and push (about 14 min first time)"
  for n in train serve; do
    if curl -s localhost:5000/v2/_catalog | grep -q "gpu-$n"; then note "gpu-$n already in the registry"; continue; fi
    timed dk build -f docker/Dockerfile.$n -t localhost:5000/gpu-$n:v1 . >/dev/null && timed dk push localhost:5000/gpu-$n:v1 >/dev/null
    chk "gpu-$n:v1 in the registry" bash -c "curl -s localhost:5000/v2/_catalog | grep -q gpu-$n"
  done
  note "Docker keeps its own copy of each image (about 21 GB). To free it: docker rmi localhost:5000/gpu-train:v1 localhost:5000/gpu-serve:v1 (the registry keeps its copy)"
}

do_models() {
  stage "models: Hugging Face cache"
  export HF_HUB_DISABLE_PROGRESS_BARS=1
  timed .venv-trad/bin/python - <<'EOF' 2>&1 | grep -v unauthenticated
from huggingface_hub import snapshot_download
for m in ["Qwen/Qwen2.5-1.5B-Instruct", "HuggingFaceTB/SmolLM2-135M-Instruct"]:
    snapshot_download(m, allow_patterns=["*.json", "*.safetensors", "*.txt"])
from datasets import load_dataset
load_dataset("tatsu-lab/alpaca", split="train[:800]")
EOF
  chk "Qwen2.5-1.5B-Instruct cached" test -d ~/.cache/huggingface/hub/models--Qwen--Qwen2.5-1.5B-Instruct
  chk "SmolLM2-135M-Instruct cached" test -d ~/.cache/huggingface/hub/models--HuggingFaceTB--SmolLM2-135M-Instruct
}

do_verify() {
  stage "verify"
  chk "GPU visible" nvidia-smi -L
  chk "node Ready" bash -c 'kubectl get nodes --no-headers | grep -qw Ready'
  chk "1 allocatable GPU (no sharing active)" bash -c '[ "$(kubectl get node -o jsonpath="{.items[0].status.allocatable.nvidia\.com/gpu}")" = 1 ]'
  chk "Operator pods healthy" bash -c '! kubectl get pods -n gpu-operator --no-headers | awk "\$3!=\"Running\"&&\$3!=\"Completed\"" | grep -q .'
  chk "registry has gpu-train and gpu-serve" bash -c 'curl -s localhost:5000/v2/_catalog | grep -q gpu-train && curl -s localhost:5000/v2/_catalog | grep -q gpu-serve'
  chk "Grafana answers" bash -c '[ "$(curl -s -o /dev/null -w "%{http_code}" localhost:30300/login)" = 200 ]'
  chk "model weights cached" test -d ~/.cache/huggingface/hub/models--Qwen--Qwen2.5-1.5B-Instruct
  chk "python env can import vLLM" .venv-trad/bin/python -c 'import vllm'
  note "GPU smoke pod (runs nvidia-smi inside Kubernetes)"
  kubectl delete -f k8s/smoke-nvidia-smi.yaml --ignore-not-found >/dev/null 2>&1
  kubectl apply -f k8s/smoke-nvidia-smi.yaml >/dev/null 2>&1
  for i in $(seq 1 60); do p=$(kubectl get pod nvidia-smi -o jsonpath='{.status.phase}' 2>/dev/null); [ "$p" = Succeeded ] || [ "$p" = Failed ] && break; sleep 3; done
  chk "smoke pod shows the GPU" bash -c 'kubectl logs nvidia-smi | grep -q "NVIDIA-SMI"'
  kubectl delete -f k8s/smoke-nvidia-smi.yaml --ignore-not-found >/dev/null 2>&1
}

summary() { echo; echo "================ PASS=$PASS FAIL=$FAIL WARN=$WARN ================"; [ "$FAIL" = 0 ]; }

case "${1:-}" in
  check) do_check ;;
  sudo) do_sudo ;;
  user) do_user ;;
  cluster) do_cluster ;;
  images) do_images ;;
  models) do_models ;;
  verify) do_verify ;;
  status) do_verify ;;
  all) do_check; do_user; do_cluster; do_images; do_models; do_verify ;;
  *) sed -n 2,12p "$0"; exit 2 ;;
esac
summary
