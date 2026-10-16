# RUNBOOK

Exact commands in order. Run from the repo root (`~/projects/tech-talk`). Tested on WSL2 Ubuntu 22.04, RTX 4070, Windows driver 615.78.
Timing helper: prefix any command with `scripts/log_step.sh <path> "<description>" --` to append wall-clock seconds to `logs/steps.csv`.

## Phase 0: verify the environment
```bash
nvidia-smi
docker run --rm --gpus all ubuntu:22.04 nvidia-smi -L    # fails until the NVIDIA Container Toolkit is installed (Phase 2 step K1)
```

## Phase 1: traditional path (everything by hand)
```bash
# 1. tools (python3-venv needs sudo, so use a per-user uv instead)
pip install --user uv && export PATH=$HOME/.local/bin:$PATH
# 2. venv
uv venv .venv-trad --python 3.10
# 3. vLLM (pulls torch + CUDA wheels)
uv pip install --python .venv-trad/bin/python vllm
# 4. training libs
uv pip install --python .venv-trad/bin/python trl peft datasets accelerate
#    (pinned versions: scripts/requirements-trad.lock)
# 5. fine-tune, 9 epochs, about 10 min, checkpoints every 25 steps
EPOCHS=9 .venv-trad/bin/python scripts/train.py --out outputs/trad_break
# 6. serve base + tuned adapter (needs 0.4, 0.3 does not fit; flashinfer disabled inside serve.sh)
export PATH=$PWD/.venv-trad/bin:$PATH
ADAPTER=outputs/trad_break/final GPU_UTIL=0.4 scripts/serve.sh
# 7. ask (second terminal)
scripts/ask.sh Qwen/Qwen2.5-1.5B-Instruct "Give three tips for staying focused."
scripts/ask.sh tuned "Give three tips for staying focused."
```
Failure demo:
```bash
EPOCHS=9 .venv-trad/bin/python scripts/train.py --out outputs/trad_break   # terminal A
pkill -9 -f '[s]cripts/train.py'                                            # terminal B, around step 360
# nothing restarts it. Resume by hand (script finds the latest checkpoint):
EPOCHS=9 .venv-trad/bin/python scripts/train.py --out outputs/trad_break
```
GPU sampling during any run: `scripts/gpu_sample.sh logs/out.csv &` (kill it afterwards).

## Phase 2: Kubernetes path

### Platform setup (one time)
```bash
# K1. system installs: container toolkit, docker nvidia runtime, k3s (needs sudo, 156 s)
sudo bash scripts/phase2_install.sh
# K2. WSL2 workaround: k3s 1.36 refuses cgroup v1
sudo mkdir -p /etc/rancher/k3s && printf 'kubelet-arg:\n  - "fail-cgroupv1=false"\n' | sudo tee /etc/rancher/k3s/config.yaml && sudo systemctl restart k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get nodes     # wait for Ready
# K3. WSL2 workaround: shared root mount (NOT persistent, repeat after every WSL restart)
sudo mount --make-rshared /
# K4. GPU Operator (driver and toolkit installers OFF: driver is Windows, toolkit is apt)
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
helm install gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace --set driver.enabled=false --set toolkit.enabled=false
# K5. WSL2 workaround: Operator cannot detect the GPU (no PCI device), label the node by hand
kubectl label node $(kubectl get nodes -o name | cut -d/ -f2) feature.node.kubernetes.io/pci-10de.present=true
# K6. success check
kubectl describe node | grep -E "nvidia.com/gpu"                          # nvidia.com/gpu: 1
kubectl apply -f k8s/smoke-nvidia-smi.yaml && kubectl logs nvidia-smi    # shows the RTX 4070
```
helm was not installed on this machine. Per-user install, no sudo:
```bash
curl -fsSL -o /tmp/helm.tgz https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz && tar xzf /tmp/helm.tgz -C /tmp linux-amd64/helm && install -m755 /tmp/linux-amd64/helm ~/.local/bin/helm
```

### Images (one time)
```bash
docker run -d -p 5000:5000 --restart always --name registry registry:2
docker build -f docker/Dockerfile.train -t localhost:5000/gpu-train:v1 . && docker push localhost:5000/gpu-train:v1
docker build -f docker/Dockerfile.serve -t localhost:5000/gpu-serve:v1 . && docker push localhost:5000/gpu-serve:v1
```

### Run
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl apply -f k8s/pvc.yaml -f k8s/train-job.yaml
kubectl logs -f job/train
kubectl apply -f k8s/serve-deployment.yaml           # after the Job completes (one GPU)
PORT=30080 scripts/ask.sh tuned "Give three tips for staying focused."
```

### Failure demos
```bash
kubectl delete pod -l app=train                       # Job makes a new pod, resumes from the latest checkpoint
kubectl logs job/train | grep resume_from             # shows checkpoint-N
kubectl delete pod -l app=serve                       # Deployment replaces it
until curl -s localhost:30080/v1/models | grep -q tuned; do sleep 2; done; echo back
```

### Sharing demo (one GPU, two workloads)
```bash
# vLLM already running and holding the GPU
kubectl apply -f k8s/train-share-job.yaml
kubectl get pods; kubectl describe pod -l app=train-share | grep -A2 Events    # Pending: Insufficient nvidia.com/gpu
scripts/gpu_sample.sh logs/before.csv &                                        # or: watch -n1 nvidia-smi
# enable time slicing
kubectl apply -f k8s/time-slicing-config.yaml
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config","default":"any"}}}}'
kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'  # 4
kubectl get pods                                                               # train-share now Running next to serve
```
Watch memory: both together peak at about 11.9 of 12.3 GB.

### After a WSL restart
```bash
sudo mount --make-rshared /          # K3 again
sudo systemctl status k3s            # starts on boot via systemd
```

### Tear down
```bash
kubectl delete -f k8s/serve-deployment.yaml -f k8s/train-job.yaml -f k8s/train-share-job.yaml
```

## Reset between takes (important)
Both training scripts auto-resume, so a second run on old outputs finishes in about 2 seconds ("done in 2s"). Reset first:
```bash
# traditional
rm -rf outputs/trad_break
# kubernetes (also gives a true cold start: fresh model download)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl delete -f k8s/serve-deployment.yaml -f k8s/train-job.yaml -f k8s/train-share-job.yaml --ignore-not-found
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type json -p '[{"op":"remove","path":"/spec/devicePlugin/config"}]'   # time slicing off
kubectl delete -f k8s/time-slicing-config.yaml --ignore-not-found
kubectl delete pvc work --ignore-not-found
kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'    # should print 1
```
Do not run the traditional and Kubernetes workloads at the same time: both want the same GPU.
