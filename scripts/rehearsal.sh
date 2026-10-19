#!/usr/bin/env bash
# Full dress rehearsal of RUNBOOK-UBUNTU-DEMO.md sections 1 to 4 and 6 (sharing skipped). About 30 minutes.
# usage: bash scripts/rehearsal.sh 2>&1 | tee logs/rehearsal_ubuntu.log
# Prints PASS or FAIL per check and a summary at the end. It resets both paths first (deletes outputs/trad_break and the PVC).
cd "$(dirname "$0")/.." || exit 1
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml PATH=$HOME/.local/bin:$PWD/.venv-trad/bin:$PATH
PASS=0; FAIL=0; T0=$(date +%s); declare -a SUMMARY
now() { echo $(( $(date +%s) - T0 )); }
check() { # check <description> <command...>
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "[PASS] $d"; SUMMARY+=("PASS  $d"); else FAIL=$((FAIL+1)); echo "[FAIL] $d"; SUMMARY+=("FAIL  $d"); fi
}
verdict() { # verdict <exit code> <description>
  if [ "$1" = 0 ]; then PASS=$((PASS+1)); echo "[PASS] $2"; SUMMARY+=("PASS  $2"); else FAIL=$((FAIL+1)); echo "[FAIL] $2"; SUMMARY+=("FAIL  $2"); fi
}
note() { echo "       $*"; SUMMARY+=("      $*"); }
phase() { echo; echo "=== $* (t=$(now)s)"; }
tstep() { tail -c 400 "$1" 2>/dev/null | tr '\r' '\n' | grep -oE '[0-9]+/900' | tail -1 | cut -d/ -f1; }
gpu_free() { [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)" -lt 1500 ]; }
trainpid() { pgrep -f '[.]venv-trad/bin/python scripts/train.py'; }

phase "1. Pre-flight"
check "GPU visible (RTX 4070)" bash -c 'nvidia-smi --query-gpu=name --format=csv,noheader | grep -q 4070'
check "node Ready" bash -c 'kubectl get nodes --no-headers | grep -qw Ready'
check "1 allocatable GPU (no sharing active)" bash -c '[ "$(kubectl get node -o jsonpath="{.items[0].status.allocatable.nvidia\.com/gpu}")" = 1 ]'
check "Operator pods healthy" bash -c '! kubectl get pods -n gpu-operator --no-headers | awk "\$3!=\"Running\"&&\$3!=\"Completed\"" | grep -q .'
check "registry has gpu-train and gpu-serve" bash -c 'curl -s localhost:5000/v2/_catalog | grep -q gpu-serve && curl -s localhost:5000/v2/_catalog | grep -q gpu-train'
check "Grafana answers" bash -c '[ "$(curl -s -o /dev/null -w "%{http_code}" localhost:30300/login)" = 200 ]'
check "model weights cached" test -d ~/.cache/huggingface/hub/models--Qwen--Qwen2.5-1.5B-Instruct
check "root disk has 20 GB or more free" bash -c '[ "$(df --output=avail -BG / | tail -1 | tr -dc 0-9)" -ge 20 ]'

phase "2. Reset"
pkill -f '[v]llm serve'; rm -rf outputs/trad_break outputs/trad_kill
kubectl delete -f k8s/serve-small.yaml -f k8s/serve-deployment.yaml -f k8s/train-job.yaml -f k8s/train-share-job.yaml --ignore-not-found >/dev/null 2>&1
kubectl delete pvc work --ignore-not-found >/dev/null 2>&1
for i in $(seq 1 40); do gpu_free && break; sleep 3; done
check "GPU idle after reset" gpu_free
check "no workload pods left" bash -c '[ "$(kubectl get pods --no-headers 2>/dev/null | wc -l)" = 0 ]'

phase "3. Traditional path: fine-tune, kill, resume, serve"
EPOCHS=9 .venv-trad/bin/python scripts/train.py --out outputs/trad_break > logs/rehearsal_trad_train.log 2>&1 &
S=""; for i in $(seq 1 600); do trainpid >/dev/null || break; S=$(tstep logs/rehearsal_trad_train.log); [ -n "$S" ] && [ "$S" -ge 362 ] && break; sleep 1; done
check "training reached step 362 before the kill" bash -c "[ '${S:-0}' -ge 362 ]"
pkill -9 -f '[.]venv-trad/bin/python scripts/train.py'; sleep 2
LASTCK=$(ls outputs/trad_break 2>/dev/null | grep checkpoint | sort -t- -k2 -n | tail -1)
check "training process is dead after kill" bash -c '! pgrep -f "[.]venv-trad/bin/python scripts/train.py"'
note "killed at step $S, last checkpoint $LASTCK"
sleep 20
check "nothing restarted the training (20 s later)" bash -c '! pgrep -f "[.]venv-trad/bin/python scripts/train.py"'
t=$(date +%s); EPOCHS=9 .venv-trad/bin/python scripts/train.py --out outputs/trad_break > logs/rehearsal_trad_resume.log 2>&1
check "manual resume finished and wrote the adapter" test -d outputs/trad_break/final
check "resume used the checkpoint" grep -q "resume_from_checkpoint" logs/rehearsal_trad_resume.log
note "resume to done: $(( $(date +%s) - t )) s"
for i in $(seq 1 40); do gpu_free && break; sleep 2; done
t=$(date +%s); (ADAPTER=outputs/trad_break/final GPU_UTIL=0.4 scripts/serve.sh > logs/rehearsal_trad_serve.log 2>&1 &)
for i in $(seq 1 90); do pgrep -f '[v]llm serve' >/dev/null || break; curl -s localhost:8000/v1/models | grep -q tuned && break; sleep 2; done
check "vLLM serves base and tuned" bash -c 'curl -s localhost:8000/v1/models | grep -q tuned'
note "vLLM start to ready: $(( $(date +%s) - t )) s"
Q="Give three tips for staying focused."
B=$(scripts/ask.sh Qwen/Qwen2.5-1.5B-Instruct "$Q"); T=$(scripts/ask.sh tuned "$Q")
check "base model answers" test -n "$B"
[ -n "$T" ] && [ "$T" != "$B" ]; verdict $? "tuned answer differs from base"
pkill -f '[v]llm serve'; for i in $(seq 1 40); do gpu_free && break; sleep 2; done

phase "4. Kubernetes path: Job, pod delete, serve, pod delete"
kubectl apply -f k8s/pvc.yaml -f k8s/train-job.yaml >/dev/null; t=$(date +%s)
for i in $(seq 1 60); do [ "$(kubectl get pod -l app=train -o jsonpath='{.items[0].status.phase}' 2>/dev/null)" = Running ] && break; sleep 2; done
check "training pod Running" bash -c '[ "$(kubectl get pod -l app=train -o jsonpath="{.items[0].status.phase}")" = Running ]'
note "apply to pod Running: $(( $(date +%s) - t )) s"
OLD=$(kubectl get pod -l app=train -o name | head -1)
for i in $(seq 1 300); do kubectl exec $OLD -- sh -c 'ls /work/outputs/k8s 2>/dev/null | grep -q "checkpoint-1[0-9][0-9]"' 2>/dev/null && break; sleep 3; done
check "checkpoints appear on the PVC" bash -c "kubectl exec $OLD -- sh -c 'ls /work/outputs/k8s | grep -q checkpoint'"
t=$(date +%s); kubectl delete $OLD --wait=false >/dev/null
NEW=""; for i in $(seq 1 120); do NEW=$(kubectl get pod -l app=train -o name 2>/dev/null | grep -v "$OLD" | head -1); [ -n "$NEW" ] && [ "$(kubectl get $NEW -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ] && break; sleep 1; done
note "pod delete to replacement Running: $(( $(date +%s) - t )) s"
check "Job created a replacement pod by itself" test -n "$NEW"
for i in $(seq 1 60); do kubectl logs $NEW 2>/dev/null | grep -q resume_from_checkpoint && break; sleep 2; done
check "replacement resumed from a checkpoint" bash -c "kubectl logs $NEW | grep -q resume_from_checkpoint"
note "$(kubectl logs $NEW 2>/dev/null | grep -o 'resume_from_checkpoint=[^ ]*' | head -1)"
check "training Job completes" kubectl wait --for=condition=complete job/train --timeout=1500s
for i in $(seq 1 60); do gpu_free && break; sleep 2; done
t=$(date +%s); kubectl apply -f k8s/serve-deployment.yaml >/dev/null
for i in $(seq 1 120); do curl -s localhost:30080/v1/models | grep -q tuned && break; sleep 3; done
check "serve Deployment answers with the tuned model" bash -c 'curl -s localhost:30080/v1/models | grep -q tuned'
note "serve apply to ready: $(( $(date +%s) - t )) s"
KT=$(PORT=30080 scripts/ask.sh tuned "$Q")
check "tuned answer via NodePort" test -n "$KT"
t=$(date +%s); kubectl delete pod -l app=serve --wait=false >/dev/null; sleep 3
for i in $(seq 1 120); do curl -s -m 3 localhost:30080/v1/models | grep -q tuned && break; sleep 2; done
check "serve pod replaced itself and answers again" bash -c 'curl -s localhost:30080/v1/models | grep -q tuned'
note "serve pod delete to answering: $(( $(date +%s) - t )) s"

phase "6. Dashboards"
check "Grafana has live GPU data" bash -c 'curl -s -u admin:admin -H "Content-Type: application/json" localhost:30300/api/ds/query -d "{\"queries\":[{\"refId\":\"A\",\"datasource\":{\"type\":\"prometheus\",\"uid\":\"prometheus\"},\"expr\":\"DCGM_FI_DEV_GPU_UTIL\",\"instant\":true}],\"from\":\"now-5m\",\"to\":\"now\"}" | jq -e ".results.A.frames[0].data.values[1][0] >= 0"'
check "dashboard defaults 5s refresh" bash -c 'curl -s -u admin:admin localhost:30300/api/dashboards/uid/Oxed_c6Wz | jq -e ".dashboard.refresh == \"5s\""'

phase "Cleanup"
kubectl delete -f k8s/serve-deployment.yaml -f k8s/train-job.yaml --ignore-not-found >/dev/null 2>&1

echo; echo "================ SUMMARY (total $(now) s) ================"
printf '%s\n' "${SUMMARY[@]}"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
