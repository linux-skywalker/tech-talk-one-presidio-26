#!/usr/bin/env bash
# EKS + H100 session, staged and re-runnable. UNTESTED on AWS: written on an RTX 4070 machine. See EKS-READY.md.
# usage:  REGION=us-east-1 AZ=us-east-1a bash scripts/eks/session.sh <stage>      (log with: ... 2>&1 | tee -a logs/eks_session.log)
# stages: preflight   free checks at home, run BEFORE paying (quota, zone offering, ECR images, tools, dry run)
#         cluster     create the one-node H100 cluster, check node, EBS, storage class
#         operator    Operator with mig.strategy=single (MIG_STRATEGY), driver and toolkit installers OFF, our MIG profiles, driver version check
#         probe       read-only: is this GPU MIG-capable (nvidia-smi mig -lgip)? Stops `all` early if not, so you can tear down before spending more
#         mig1g       apply MIG profile all-1g.10gb, verify slices, then run the memory test
#         mig2g       apply all-2g.20gb, run the serve + train concurrency session, failure tests, load test
#         all         preflight is NOT included. Runs cluster, operator, probe, mig1g, mig2g and stops at the first failed stage
#         status      show nodes, pods, MIG labels
#         teardown    delete the cluster and list leftovers (asks first, FORCE=1 skips the question)
# env:    REGION (required), AZ (zone offering the instance), CLUSTER (default gpu-talk), INSTANCE (default p5.4xlarge; AWS-documented MIG fallback: p4d.24xlarge),
#         MIG_STRATEGY (single|mixed, default single; AWS's AL2023 page uses mixed), USE_LB=1 keeps the LoadBalancer Service
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
export PATH=$HOME/.local/bin:$PATH AWS_PAGER=""
: "${REGION:?set REGION, e.g. REGION=us-east-1}"
CLUSTER=${CLUSTER:-gpu-talk}; INSTANCE=${INSTANCE:-p5.4xlarge}; MIG_STRATEGY=${MIG_STRATEGY:-single}
case $INSTANCE in p5.4xlarge) VCPU=16;; p4d.24xlarge|p4de.24xlarge) VCPU=96;; p5.48xlarge|p5e.48xlarge|p5en.48xlarge) VCPU=192;; *) VCPU=0;; esac   # vCPUs the quota must allow (0 = unknown, check by hand)
[ -f logs/.eks_env ] && . logs/.eks_env          # remembers NO_RUNTIMECLASS from an earlier stage
PASS=0; FAIL=0; T0=$(date +%s)
phase() { echo; echo "=== $* ($(date +%H:%M:%S), +$(( $(date +%s) - T0 ))s)"; }
note() { echo "       $*"; }
verdict() { if [ "$1" = 0 ]; then PASS=$((PASS+1)); echo "[PASS] $2"; else FAIL=$((FAIL+1)); echo "[FAIL] $2"; fi; return "$1"; }
check() { local d="$1"; shift; "$@" >/dev/null 2>&1; verdict $? "$d"; }
step() { local d="$1"; shift; local t=$(date +%s); "$@"; local rc=$?; echo "eks-h100,\"$d\",$(( $(date +%s) - t )),$rc" >> logs/steps.csv; note "$d: $(( $(date +%s) - t )) s (rc=$rc)"; return $rc; }
ACC=${ACC:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}
render() { # render <manifest>: fills ACCOUNT_ID, REGION, AZ; drops runtimeClassName if the cluster has none; ClusterIP instead of LoadBalancer
  local out; out=$(sed -e "s/ACCOUNT_ID/${ACC:-ACCOUNT_ID}/g" -e "s/REGION/$REGION/g" -e "s/\"AZ\"/\"${AZ:-AZ}\"/" -e "s/INSTANCE_TYPE/$INSTANCE/" "$1")
  [ -n "${MIG_RES:-}" ] && out=$(printf '%s\n' "$out" | sed "s#nvidia.com/gpu: 1#$MIG_RES: 1#")   # MIG_STRATEGY=mixed: pods ask for the slice resource
  [ "${NO_RUNTIMECLASS:-0}" = 1 ] && out=$(printf '%s\n' "$out" | sed '/runtimeClassName/d')
  [ "${USE_LB:-0}" != 1 ] && out=$(printf '%s\n' "$out" | sed 's/type: LoadBalancer/type: ClusterIP/')
  printf '%s\n' "$out"
}
apply() { render "$1" | kubectl apply -f - ; }
wait_for() { # wait_for <seconds> <description> <command...>
  local n=$1 d=$2; shift 2; for _ in $(seq 1 $(( n / 3 ))); do "$@" >/dev/null 2>&1 && return 0; sleep 3; done; return 1
}
node() { kubectl get nodes -o name | head -1 | cut -d/ -f2; }
gpus() { local r; r=$(echo "${MIG_RES:-nvidia.com/gpu}" | sed 's/\./\\./g'); kubectl get node "$(node)" -o jsonpath="{.status.allocatable.$r}" 2>/dev/null; }
pf_start() { kubectl port-forward svc/serve 18000:8000 >/dev/null 2>&1 & echo $! > logs/.eks_pf.pid; sleep 3; }
pf_stop() { [ -f logs/.eks_pf.pid ] && kill "$(cat logs/.eks_pf.pid)" 2>/dev/null; rm -f logs/.eks_pf.pid; }
serve_models() { kubectl exec deploy/serve -- python -c 'import urllib.request as u; print(u.urlopen("http://localhost:8000/v1/models").read().decode())' 2>/dev/null; }
export -f serve_models
smi_in_cluster() { kubectl exec -n gpu-operator ds/nvidia-device-plugin-daemonset -- nvidia-smi "$@" 2>&1; }
summary() { echo; echo "---- stage result: PASS=$PASS FAIL=$FAIL (+$(( $(date +%s) - T0 ))s)"; [ "$FAIL" = 0 ]; }

stage_preflight() {
  phase "preflight (free)"
  for t in aws eksctl kubectl helm jq docker curl; do check "tool installed: $t" command -v $t; done
  check "AWS credentials work" aws sts get-caller-identity
  local q qn; q=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-417A185B --region "$REGION" --query Quota.Value --output text 2>/dev/null)
  qn=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-417A185B --region "$REGION" --query Quota.QuotaName --output text 2>/dev/null)
  if [ -z "$q" ] || [ "$q" = None ]; then note "could not read the P-instance vCPU quota (L-417A185B). Check Service Quotas in the console: 'Running On-Demand P instances'"
  else note "quota L-417A185B is named: $qn"; verdict $([ "${q%.*}" -ge "$VCPU" ] && echo 0 || echo 1) "P-instance on-demand vCPU quota is $q ($INSTANCE needs $VCPU; 0 means unknown size, check by hand)"; fi
  if [ -z "${AZ:-}" ]; then
    verdict 1 "AZ is not set. Zones offering $INSTANCE in $REGION: $(aws ec2 describe-instance-type-offerings --location-type availability-zone --filters Name=instance-type,Values=$INSTANCE --region "$REGION" --query 'InstanceTypeOfferings[].Location' --output text 2>/dev/null)"
  else
    check "$INSTANCE offered in $AZ" bash -c "aws ec2 describe-instance-type-offerings --location-type availability-zone --filters Name=instance-type,Values=$INSTANCE Name=location,Values=$AZ --region $REGION --query 'InstanceTypeOfferings[0].InstanceType' --output text | grep -q $INSTANCE"
  fi
  for r in gpu-train gpu-serve; do check "ECR image $r:v1 exists" aws ecr describe-images --region "$REGION" --repository-name $r --image-ids imageTag=v1; done
  render k8s/eks/cluster.yaml > logs/.eks_cluster.yaml
  check "cluster.yaml renders and eksctl accepts it (dry run)" eksctl create cluster -f logs/.eks_cluster.yaml --dry-run
  note "MIG on $INSTANCE: AWS's EKS MIG page lists only 8-GPU sizes (p4d, p5.48xlarge, ...). p5.4xlarge is NOT listed, so the probe stage decides. Fallback: INSTANCE=p4d.24xlarge (needs 96 vCPUs of quota)."
  note "if a check failed: quota -> request it (can take days). ECR -> REGION=$REGION scripts/eks_push_images.sh. Offering -> try another zone or region, or a Capacity Block."
  note "cost reminder: p5.4xlarge about 6.88 USD/hr on-demand per price aggregators (VERIFY, other sizes cost far more), plus EKS control plane and EBS. Tear down with: bash scripts/eks/session.sh teardown"
  summary
}

stage_cluster() {
  phase "cluster"
  [ -n "${AZ:-}" ] || { verdict 1 "AZ must be set"; summary; return 1; }
  render k8s/eks/cluster.yaml > logs/.eks_cluster.yaml
  step "eksctl create cluster incl. GPU node and EBS CSI" eksctl create cluster -f logs/.eks_cluster.yaml
  verdict $? "eksctl create cluster succeeded" || { note "capacity errors: try another AZ/region or a Capacity Block. Check: eksctl utils describe-stacks --cluster $CLUSTER --region $REGION"; summary; return 1; }
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null
  check "node Ready" wait_for 600 "node ready" bash -c 'kubectl get nodes --no-headers | grep -qw Ready'
  note "node: $(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.osImage} | {.items[0].metadata.labels.node\.kubernetes\.io/instance-type}')"
  check "instance type is $INSTANCE" bash -c "kubectl get nodes -o jsonpath='{.items[0].metadata.labels.node\.kubernetes\.io/instance-type}' | grep -q $INSTANCE"
  check "node OS image is the NVIDIA accelerated AMI (driver present)" bash -c "kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.osImage}' | grep -qi amazon"
  check "EBS CSI controller running" wait_for 300 "ebs csi" bash -c 'kubectl get pods -n kube-system --no-headers | grep ebs-csi | grep -q Running'
  check "gp3 StorageClass applied" kubectl apply -f k8s/eks/storageclass.yaml
  summary
}

stage_operator() {
  phase "GPU Operator, mig.strategy=$MIG_STRATEGY, driver and toolkit installers OFF, our MIG profiles"
  helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null 2>&1; helm repo update >/dev/null 2>&1
  kubectl create namespace gpu-operator --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  check "MIG profile ConfigMap applied" kubectl apply -f k8s/eks/mig-parted-config.yaml
  step "operator helm install" helm install gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace \
    --set mig.strategy=$MIG_STRATEGY --set driver.enabled=false --set toolkit.enabled=false \
    --set migManager.config.name=custom-mig-parted-config --set migManager.config.create=false \
    --set 'migManager.env[0].name=WITH_REBOOT' --set-string 'migManager.env[0].value=true' \
    --set 'dcgmExporter.env[0].name=DCGM_EXPORTER_INTERVAL' --set-string 'dcgmExporter.env[0].value=1000'
  verdict $? "helm install succeeded" || { summary; return 1; }
  t=$(date +%s)
  check "nvidia.com/gpu visible on the node" wait_for 600 "gpu visible" bash -c '[ "$(kubectl get nodes -o jsonpath="{.items[0].status.allocatable.nvidia\.com/gpu}")" = 1 ]'
  note "operator install to GPU visible: $(( $(date +%s) - t )) s (4070: 33 s)"
  echo "eks-h100,\"operator GPU visible after helm\",$(( $(date +%s) - t )),0" >> logs/steps.csv
  kubectl get pods -n gpu-operator --no-headers | awk '{print "       "$1,$2,$3}'
  if kubectl get runtimeclass nvidia >/dev/null 2>&1; then note "RuntimeClass nvidia exists"; else
    note "RuntimeClass nvidia is missing: manifests will be rendered without runtimeClassName"; echo "export NO_RUNTIMECLASS=1" >> logs/.eks_env; export NO_RUNTIMECLASS=1; fi
  kubectl delete pod nvidia-smi --ignore-not-found >/dev/null 2>&1
  apply k8s/smoke-nvidia-smi.yaml >/dev/null
  check "smoke pod ran nvidia-smi" wait_for 240 "smoke" bash -c '[ "$(kubectl get pod nvidia-smi -o jsonpath="{.status.phase}")" = Succeeded ]'
  local out drv; out=$(kubectl logs nvidia-smi 2>&1); echo "$out" | grep -E "Driver Version|H100" | sed 's/^/       /' | cut -c1-110
  drv=$(echo "$out" | grep -o 'Driver Version: [0-9]*' | grep -o '[0-9]*$')
  verdict $([ -n "$drv" ] && [ "$drv" -ge 580 ] && echo 0 || echo 1) "driver ${drv:-unknown} supports CUDA 13 images (needs R580 or newer)"
  [ -n "$drv" ] && [ "$drv" -lt 580 ] && note "PLAN B: driver too old. Rebuild train and serve with a CUDA 12 torch/vLLM build, push to ECR, rerun. See EKS-READY.md."
  kubectl delete pod nvidia-smi --ignore-not-found >/dev/null 2>&1
  summary
}

stage_probe() {
  phase "probe: is $INSTANCE MIG-capable? (read-only, changes nothing)"
  kubectl delete pod mig-probe --ignore-not-found >/dev/null 2>&1
  apply k8s/eks/mig-probe.yaml >/dev/null
  wait_for 240 "probe pod finished" bash -c 'p=$(kubectl get pod mig-probe -o jsonpath="{.status.phase}"); [ "$p" = Succeeded ] || [ "$p" = Failed ]'
  local out; out=$(kubectl logs mig-probe 2>&1); echo "$out" | sed 's/^/       /' | head -30
  kubectl delete pod mig-probe --ignore-not-found >/dev/null 2>&1
  echo "$out" | grep -q "No MIG-supported" && { verdict 1 "$INSTANCE reports NO MIG-supported devices"; note "That is the finding. Record it in results-eks-h100.md, then: bash scripts/eks/session.sh teardown. To try a documented MIG size: INSTANCE=p4d.24xlarge (needs 96 vCPUs quota)."; summary; return 1; }
  echo "$out" | grep -qE "MIG [0-9]g\.[0-9]+gb" && verdict 0 "$INSTANCE lists MIG GPU instance profiles" || { verdict 1 "no MIG profiles listed (see output above)"; summary; return 1; }
  note "record: GPU/driver/MIG mode lines above go into results-eks-h100.md"
  summary
}

apply_mig() { # apply_mig <profile> <expected slice count>
  local p=$1 want=$2 n; n=$(node)
  check "no workload pods running (MIG change needs a free GPU)" bash -c '! kubectl get pods --no-headers 2>/dev/null | grep -q .'
  kubectl get cm -n gpu-operator custom-mig-parted-config -o yaml 2>/dev/null | grep -q "^      $p:" || note "profile $p not found in custom-mig-parted-config (see k8s/eks/mig-parted-config.yaml)"
  if [ "$MIG_STRATEGY" = mixed ]; then MIG_RES="nvidia.com/mig-${p#all-}"; export MIG_RES; sed -i '/^export MIG_RES=/d' logs/.eks_env 2>/dev/null; echo "export MIG_RES=$MIG_RES" >> logs/.eks_env; note "mixed strategy: slices are advertised as $MIG_RES"; fi
  local t=$(date +%s)
  kubectl label node "$n" nvidia.com/mig.config="$p" --overwrite >/dev/null
  local st=""; for _ in $(seq 1 200); do st=$(kubectl get node "$n" -o jsonpath='{.metadata.labels.nvidia\.com/mig\.config\.state}'); case "$st" in success|failed) break;; esac; sleep 3; done
  echo "eks-h100,\"MIG $p label to state=$st\",$(( $(date +%s) - t )),0" >> logs/steps.csv
  verdict $([ "$st" = success ] && echo 0 || echo 1) "MIG $p applied (state=$st) in $(( $(date +%s) - t )) s"
  if [ "$st" != success ]; then note "diagnose: kubectl logs -n gpu-operator ds/nvidia-mig-manager ; a reboot may be needed: aws ec2 reboot-instances --region $REGION --instance-ids <id>"; return 1; fi
  check "node advertises $want slices" wait_for 300 "slices" bash -c "[ \"\$(kubectl get node $n -o jsonpath=\"{.status.allocatable.$(echo "${MIG_RES:-nvidia.com/gpu}" | sed 's/\./\\./g')}\")\" = $want ]"
  note "allocatable nvidia.com/gpu = $(gpus)"
  smi_in_cluster -L | grep -E "MIG|GPU" | head -10 | sed 's/^/       /' | cut -c1-110
}

stage_mig1g() {
  phase "MIG all-1g.10gb and the memory test"
  apply_mig all-1g.10gb 7 || { summary; return 1; }
  kubectl delete pod mem-greedy mem-steady --ignore-not-found >/dev/null 2>&1
  apply k8s/eks/mig-memtest.yaml >/dev/null
  note "memory test running (about 110 s)"; sleep 110
  local g s; g=$(kubectl logs mem-greedy 2>&1 | grep -E "sees|stopped"); s=$(kubectl logs mem-steady 2>&1 | grep -E "sees|holds|GREW|NOT grow")
  echo "$g" | sed 's/^/       greedy: /'; echo "$s" | sed 's/^/       steady: /'
  verdict $(echo "$g" | grep -q stopped && echo 0 || echo 1) "greedy pod hit a memory limit"
  verdict $(echo "$s" | grep -q "GREW" && echo 0 || echo 1) "steady pod could still grow (isolation holds)"
  note "4070 reference: time slicing -> steady could NOT grow. MPS -> greedy stopped at 5 GiB, steady grew."
  kubectl delete pod mem-greedy mem-steady --ignore-not-found >/dev/null 2>&1
  summary
}

stage_mig2g() {
  phase "MIG all-2g.20gb: serve and train at the same time on separate slices"
  apply_mig all-2g.20gb 3 || { summary; return 1; }
  apply k8s/eks/pvc.yaml >/dev/null; apply k8s/eks/train-job.yaml >/dev/null; apply k8s/eks/serve-deployment.yaml >/dev/null
  check "training pod Running" wait_for 600 "train" bash -c '[ "$(kubectl get pod -l app=train -o jsonpath="{.items[0].status.phase}")" = Running ]'
  check "serve pod Running at the same time (no Pending)" wait_for 600 "serve" bash -c '[ "$(kubectl get pod -l app=serve -o jsonpath="{.items[0].status.phase}")" = Running ]'
  kubectl get pods -o wide --no-headers | awk '{print "       "$1,$3,$7}'
  check "base model serving while training runs" wait_for 600 "serve ready" bash -c 'serve_models | grep -q Qwen'
  local old; old=$(kubectl get pod -l app=train -o name | head -1)
  check "checkpoint on the PVC" wait_for 900 "ckpt" bash -c "kubectl exec $old -- sh -c 'ls /work/outputs/k8s | grep -q checkpoint-1'"
  local t=$(date +%s); kubectl delete "$old" --wait=false >/dev/null
  local new=""; for _ in $(seq 1 200); do new=$(kubectl get pod -l app=train -o name | grep -v "$old" | head -1); [ -n "$new" ] && [ "$(kubectl get "$new" -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ] && break; sleep 1; done
  note "training pod delete to replacement Running: $(( $(date +%s) - t )) s (4070: 32 s)"
  echo "eks-h100,\"train pod delete to replacement Running\",$(( $(date +%s) - t )),0" >> logs/steps.csv
  check "replacement resumed from a checkpoint" wait_for 180 "resume" bash -c "kubectl logs $new | grep -q resume_from_checkpoint"
  note "$(kubectl logs "$new" 2>/dev/null | grep -o 'resume_from_checkpoint=[^ ]*' | head -1)"
  check "training Job completes" kubectl wait --for=condition=complete job/train --timeout=1800s
  kubectl rollout restart deploy/serve >/dev/null
  check "serve restarted and lists the tuned model" wait_for 600 "tuned" bash -c 'serve_models | grep -q tuned'
  pf_start; local Q="Give three tips for staying focused."
  check "tuned answer through port-forward" bash -c "PORT=18000 scripts/ask.sh tuned '$Q' | grep -q ."
  t=$(date +%s); kubectl delete pod -l app=serve --wait=false >/dev/null; sleep 3; pf_stop
  wait_for 600 "serve back" bash -c 'serve_models | grep -q tuned'
  verdict $? "serve pod replaced itself and answers again"; note "serve pod delete to answering: $(( $(date +%s) - t )) s (4070: 77 s)"
  echo "eks-h100,\"serve pod delete to answering\",$(( $(date +%s) - t )),0" >> logs/steps.csv
  pf_start; note "load test (16 clients, 60 s): $(scripts/loadtest.sh 18000 Qwen/Qwen2.5-1.5B-Instruct 60 16 2>&1 | tail -1)"; pf_stop
  note "per-slice GPU memory:"; smi_in_cluster --query-gpu=name,memory.used,memory.total --format=csv | sed 's/^/       /' | head -6
  note "Moving evidence (changed lines, local vs EKS manifests):"
  for f in train-job serve-deployment pvc; do note "$f: $(diff k8s/$f.yaml k8s/eks/$f.yaml | grep -c '^[<>]') lines differ"; done
  summary
}

stage_status() { kubectl get nodes -o wide; kubectl get pods -A --no-headers | awk '$4!="Running"&&$4!="Completed"{print "not ready:",$2,$4}'; kubectl get node "$(node)" -o json | jq -r '.metadata.labels | to_entries[] | select(.key|test("mig|gpu.product|gpu.count")) | "\(.key)=\(.value)"'; echo "allocatable gpu: $(gpus)"; }

stage_teardown() {
  phase "teardown"
  if [ "${FORCE:-0}" != 1 ]; then read -r -p "Delete cluster $CLUSTER in $REGION and everything on it? [type yes] " a; [ "$a" = yes ] || { echo "aborted"; return 1; }; fi
  step "eksctl delete cluster" eksctl delete cluster --name "$CLUSTER" --region "$REGION" --wait
  echo "-- leftovers (should all be empty):"
  echo "clusters:           $(aws eks list-clusters --region "$REGION" --query clusters --output text)"
  echo "available volumes:  $(aws ec2 describe-volumes --region "$REGION" --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text)"
  echo "load balancers:     $(aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerName' --output text 2>/dev/null)"
  echo "classic LBs:        $(aws elb describe-load-balancers --region "$REGION" --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text 2>/dev/null)"
  rm -f logs/.eks_env logs/.eks_cluster.yaml
  echo "ECR repos remain (cheap); delete with: aws ecr delete-repository --region $REGION --force --repository-name gpu-train (and gpu-serve)"
}

case "${1:-}" in
  preflight) stage_preflight ;;
  cluster)   stage_cluster ;;
  operator)  stage_operator ;;
  mig1g)     stage_mig1g ;;
  mig2g)     stage_mig2g ;;
  probe)     stage_probe ;;
  status)    stage_status ;;
  teardown)  stage_teardown ;;
  all)       for s in cluster operator probe mig1g mig2g; do "stage_$s" || { echo "STOPPED at stage $s. Fix it, then rerun that stage alone: bash scripts/eks/session.sh $s"; exit 1; }; done ;;
  *) sed -n '2,15p' "$0"; exit 2 ;;
esac
