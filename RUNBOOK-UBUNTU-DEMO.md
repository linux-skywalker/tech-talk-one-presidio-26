# Demo runbook (native Ubuntu, RTX 4070)

Copy-paste only. Run from the repo root. No Claude needed. Commands marked UNTESTED HERE were only run on WSL2 (`RUNBOOK.md`) and must be rehearsed once on this machine before recording.

## 0. Terminal setup (once per shell)
```bash
cd ~/tech-talk-one-presidio-26
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export PATH=$HOME/.local/bin:$PWD/.venv-trad/bin:$PATH
```
Suggested layout: pane A runs the commands, pane B `watch -n1 nvidia-smi`, pane C `k9s -n default` (Kubernetes part only).

Docker needs the `docker` group. If `docker ps` says permission denied, log out and in once, or prefix with `sg docker -c "..."`.

## 1. Pre-flight check (1 minute, before recording)
```bash
nvidia-smi --query-gpu=name,driver_version,memory.used --format=csv     # RTX 4070, 590.48.01, under 1000 MiB used
kubectl get nodes                                                       # Ready
kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'; echo   # 1
kubectl get pods -n gpu-operator --no-headers | awk '{print $1,$2,$3}'  # Running or Completed
curl -s localhost:5000/v2/_catalog                                      # gpu-serve and gpu-train
curl -s -o /dev/null -w "grafana HTTP %{http_code}\n" localhost:30300/login   # 200
ls ~/.cache/huggingface/hub | head -3                                   # Qwen model cached
```
Model weights must already be downloaded (they are, from the Phase 1 run). Only one workload may use the GPU at a time, so stop everything from the other path first (`pgrep -af vllm`, `kubectl get pods`).

## 2. Reset between takes (do this before EVERY take)
Training auto-resumes, so a second run on old outputs ends in about 2 s unless you reset.
```bash
# traditional
pkill -f '[v]llm serve'; rm -rf outputs/trad_break outputs/trad_kill
# kubernetes
kubectl delete -f k8s/serve-deployment.yaml -f k8s/train-job.yaml -f k8s/train-share-job.yaml --ignore-not-found
kubectl delete pvc work --ignore-not-found                              # fresh checkpoints and a cold model download in the pod
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type json -p '[{"op":"remove","path":"/spec/devicePlugin/config"}]' 2>/dev/null   # time slicing off
kubectl delete -f k8s/time-slicing-config.yaml --ignore-not-found
kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'; echo   # must print 1 (wait up to 30 s)
```
Do not run the `pkill` line as part of a longer line containing `scripts/train.py` text, it kills its own shell. The bracket form `'[v]llm serve'` is safe on its own.

## 3. Part 1: traditional path
```bash
# fine-tune, about 9 min (900 steps, checkpoints every 25)
EPOCHS=9 .venv-trad/bin/python scripts/train.py --out outputs/trad_break
```
Failure demo: start the line above in pane A, then in pane B around step 360:
```bash
pkill -9 -f '[.]venv-trad/bin/python scripts/train.py'
```
Show that nothing restarts it (`pgrep -af '[s]cripts/train.py'` prints nothing), then resume by hand in pane A with the same training command (it says `resume_from_checkpoint=...`).

Serve and ask (after training has finished):
```bash
ADAPTER=outputs/trad_break/final GPU_UTIL=0.4 scripts/serve.sh          # ready in about 50 s. 0.3 FAILS (no KV cache), keep 0.4
# second terminal
scripts/ask.sh Qwen/Qwen2.5-1.5B-Instruct "Give three tips for staying focused."
scripts/ask.sh tuned "Give three tips for staying focused."
scripts/loadtest.sh 8000 Qwen/Qwen2.5-1.5B-Instruct 60 16               # optional, 60 s
```
Stop serving before the Kubernetes part: `pkill -f '[v]llm serve'`.

## 4. Part 2: Kubernetes path
Training Job on a PVC:
```bash
kubectl apply -f k8s/pvc.yaml -f k8s/train-job.yaml
kubectl get pods -w                                                     # Pending, ContainerCreating, Running (about 25 s). Ctrl+C to leave
kubectl logs -f job/train | tr '\r' '\n'                                # first step after about 2.5 min on a cold pod
```
Failure demo, once `kubectl exec job/train -- ls /work/outputs/k8s` shows a checkpoint (about 3 min in):
```bash
kubectl delete pod -l app=train
kubectl get pods -w                                                     # new pod appears by itself, Running in about 35 s
kubectl logs job/train | grep -o 'resume_from_checkpoint=[^ ]*'         # checkpoint-N
```
Wait for the Job to finish (about 9 to 13 min): `kubectl wait --for=condition=complete job/train --timeout=1200s`

Serving Deployment (after the Job completes, one GPU) UNTESTED HERE:
```bash
kubectl apply -f k8s/serve-deployment.yaml
until curl -s localhost:30080/v1/models | grep -q tuned; do sleep 2; done; echo serving
PORT=30080 scripts/ask.sh tuned "Give three tips for staying focused."
```
Serve failure demo UNTESTED HERE:
```bash
kubectl delete pod -l app=serve
until curl -s localhost:30080/v1/models | grep -q tuned; do sleep 2; done; echo back     # about 100 s on WSL2
```
If the loop could hang, check the pod in another pane (`kubectl get pods`), do not trust the loop alone.

## 5. Sharing demo (one GPU, two workloads)
Use the small second model, not a second training Job: training next to the serve pod runs out of GPU memory (CUDA OOM, tested twice).
```bash
# serve Deployment already running and holding the GPU
kubectl apply -f k8s/serve-small.yaml                                   # Qwen2.5-0.5B on NodePort 30081
kubectl get pods                                                        # serve-small stays Pending
kubectl describe pod -l app=serve-small | grep -A3 Events               # Insufficient nvidia.com/gpu
kubectl apply -f k8s/time-slicing-config.yaml
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config","default":"any"}}}}'
kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'; echo   # 4
until curl -s localhost:30081/v1/models | grep -q 0.5B; do sleep 2; done; echo small model up   # about 60 to 90 s
PORT=30080 scripts/ask.sh tuned "Give three tips for staying focused."
PORT=30081 scripts/ask.sh Qwen/Qwen2.5-0.5B-Instruct "Give three tips for staying focused."
```
Say plainly: time slicing has no memory isolation. The OOM of a second training Job is the proof, keep it as the caveat. Do not mention MIG.

DISK WARNING: the root disk has about 25 GB free and each GPU pod start used about 6 GB of it. The first sharing attempt hit kubelet DiskPressure and evicted every pod. Check `df -h /` before recording (keep 25 GB or more free). If pods show Evicted: `kubectl delete pod --field-selector=status.phase=Failed -A`, wait for DiskPressure=False (`kubectl describe node | grep DiskPressure`), and the Deployments recreate their pods.

## 6. Dashboards
- k9s: `k9s -n default` (keys: `:pods`, `l` logs, `d` describe, `Ctrl+D` delete, `:q` quit). k9s shows CPU and memory, not GPU.
- GPU: `watch -n1 nvidia-smi`, or Grafana `http://localhost:30300/d/Oxed_c6Wz/nvidia-dcgm-exporter-dashboard` (admin / admin, last 5 minutes, refresh 5s). Panels filling in is NOT yet confirmed in a browser. Check before relying on it.

## 7. Numbers to quote (this machine only, single runs, see `results-ubuntu-4070.md`)
- Traditional: fine-tune 529 s, GPU 93% while active. vLLM ready in 48 s. Load test 1774 tok/s. Kill at step 362, last checkpoint 350, 12 steps lost, nothing restarted it.
- Kubernetes: Operator install to `nvidia.com/gpu: 1` in 33 s with no workarounds. Train pod Running 23 s after apply. Pod deleted, replacement Running in 34 s and resumed from a checkpoint by itself.
- Images: cold builds 258 s (train) and 601 s (serve).

## 8. If something goes wrong
```bash
kubectl get pods -A                                                     # anything not Running
kubectl describe pod <name> | tail -20
kubectl logs <pod> --tail=30
nvidia-smi                                                              # GPU still used by a leftover process?
pgrep -af '[v]llm serve|[s]cripts/train.py'                             # leftover traditional processes
kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'; echo   # 0 means the device plugin lost the GPU
```
A deleted GPU pod stays Terminating for up to about 60 s and holds the GPU, so its replacement waits Pending until then. This is normal, not a bug.

## 9. Do not claim
- The Operator installed the driver or the container toolkit (it did not here: both come from the host, the Operator ran with them off).
- Kubernetes made training faster or raised GPU utilization.
- Time slicing isolates memory, or anything about MIG.
- Model quality (loss about 0.1 is overfit, timing demo only).
- Native Ubuntu is faster than WSL2 because of Linux alone (different driver, single runs).
