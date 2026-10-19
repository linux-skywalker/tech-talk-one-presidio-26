# EKS + H100 session plan: MIG, "Moving" and the same comparison (UNTESTED)

Scripted version of this plan: `EKS-READY.md` and `scripts/eks/session.sh`. This file explains the reasoning.

Goal: get the evidence this repo cannot produce on an RTX 4070. (1) MIG gives real memory isolation, (2) the same manifests run on a managed cloud (Moving), (3) which RTX-4070 workarounds disappear on EKS. Write results in `results-eks-h100.md`, never mixed with the 4070 tables. Log every step with `scripts/log_step.sh eks-h100 "<step>" -- <command>`.

Everything below comes from NVIDIA's and AWS's docs or from what worked on the 4070. None of it has run on EKS. Items marked VERIFY are things I could not confirm.

Budget: p5.4xlarge was listed at about $6.88/hr on-demand in us-east-1 by price aggregators (VERIFY on the AWS pricing page), plus the EKS control plane and EBS. A 4 hour session is roughly $30 to $50. Time-box it and tear down at the end.

## A. At home, before paying (all free or nearly free)
1. **Quota.** New accounts often have 0 vCPUs for P instances. p5.4xlarge needs 16. Request "Running On-Demand P instances" in the Service Quotas console, and check it (the quota code L-417A185B is from memory, VERIFY):
   ```bash
   aws service-quotas get-service-quota --service-code ec2 --quota-code L-417A185B --region $REGION --query Quota.Value
   ```
2. **Offering and zone.** Find a zone that offers the instance and put it in `cluster.yaml`:
   ```bash
   aws ec2 describe-instance-type-offerings --location-type availability-zone --filters Name=instance-type,Values=p5.4xlarge --region $REGION --query 'InstanceTypeOfferings[].Location'
   ```
   P5 capacity can be scarce. If the node group fails with an insufficient capacity error, try another zone or region, or ask AWS about a capacity reservation or Capacity Block. Have a plan B before the clock starts.
3. **Tools, per-user, no sudo.** `aws` CLI v2 and `eksctl` into `~/.local/bin` (kubectl and helm are already there). Confirm `aws sts get-caller-identity` works.
4. **Push the images to ECR now** (about 21 GB of upload; do it at home, ECR storage is cheap):
   ```bash
   REGION=us-east-1 scripts/eks_push_images.sh      # prints ACCOUNT_ID and REGION
   export ACC=<account id> REGION=<region>
   ```
5. **Dry run:** edit `k8s/eks/cluster.yaml` (REGION, AZ), then `eksctl create cluster -f k8s/eks/cluster.yaml --dry-run`.
6. **Open question to settle early (VERIFY):** that MIG works on the single-GPU p5.4xlarge. My searches did not confirm it. Check AWS's P5 documentation. If it does not, fall back to a larger P-family instance or another provider with an A100, and tell me.

## B. The session (start the timer)
```bash
export REGION=... ACC=...   AWS_PAGER=""
```
1. **Cluster** (timed):
   ```bash
   scripts/log_step.sh eks-h100 "eksctl create cluster incl. GPU node and EBS CSI" -- eksctl create cluster -f k8s/eks/cluster.yaml
   kubectl get nodes -o wide
   ```
   VERIFY the node uses the NVIDIA accelerated AMI: `kubectl get node -o jsonpath='{.items[0].status.nodeInfo.osImage}'` and then check for a driver in step 3. If there is no driver, the AMI choice in `cluster.yaml` is wrong.
2. **Storage class:** `kubectl apply -f k8s/eks/storageclass.yaml`
3. **Operator with the MIG strategy** (single: slices appear as `nvidia.com/gpu`, so our manifests work unchanged). Driver and toolkit installers OFF. The toolkit installer broke the 4070 host, and the accelerated AMI ships both:
   ```bash
   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
   scripts/log_step.sh eks-h100 "operator install to nvidia.com/gpu visible" -- helm install gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace \
     --set mig.strategy=single --set driver.enabled=false --set toolkit.enabled=false \
     --set 'dcgmExporter.env[0].name=DCGM_EXPORTER_INTERVAL' --set-string 'dcgmExporter.env[0].value=1000'
   kubectl get pods -n gpu-operator
   kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'; echo   # 1 before MIG
   kubectl apply -f k8s/smoke-nvidia-smi.yaml && sleep 20 && kubectl logs nvidia-smi    # driver version and the H100
   ```
   Record which RTX-4070 workarounds were needed (none expected). If the driver is older than R580, the CUDA 13 images will fail at CUDA init; rebuild them with a CUDA 12 torch wheel and push again.
4. **Apply MIG** (no GPU workloads running):
   ```bash
   NODE=$(kubectl get nodes -o name | head -1 | cut -d/ -f2)
   kubectl get cm -n gpu-operator default-mig-parted-config -o yaml | grep -E "^  *all-"      # exact profile names
   kubectl label node $NODE nvidia.com/mig.config=all-1g.10gb --overwrite
   until [ "$(kubectl get node $NODE -o jsonpath='{.metadata.labels.nvidia\.com/mig\.config\.state}')" = success ]; do sleep 5; done
   kubectl get node $NODE -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'; echo           # 7 expected
   ```
   Time it. The MIG manager may need a reset or reboot on a cloud VM (NVIDIA's guide mentions `WITH_REBOOT` for Google Cloud; nothing EKS-specific found). If the state goes to `failed`, check `kubectl logs -n gpu-operator ds/nvidia-mig-manager` and record the failure.
5. **MIG memory test** (the evidence the 4070 cannot give):
   ```bash
   sed "s/ACCOUNT_ID/$ACC/; s/REGION/$REGION/" k8s/eks/mig-memtest.yaml | kubectl apply -f -
   sleep 110
   kubectl logs mem-greedy | grep -E "sees|stopped"; kubectl logs mem-steady | grep -E "sees|holds|GREW|NOT"
   kubectl delete pod mem-greedy mem-steady
   ```
   4070 reference (single runs): time slicing, steady could NOT grow; MPS, steady grew; greedy stopped at its limit (5 GiB). Expected on MIG: each pod sees its own slice (about 10 GB), greedy stops there, steady grows.
6. **Serve and train on separate slices, both at once** (the real workload demo). Use a bigger slice so training fits:
   ```bash
   kubectl label node $NODE nvidia.com/mig.config=all-2g.20gb --overwrite     # wait for success again
   for f in storageclass.yaml pvc.yaml; do kubectl apply -f k8s/eks/$f; done
   for f in train-job.yaml serve-deployment.yaml; do sed "s/ACCOUNT_ID/$ACC/; s/REGION/$REGION/" k8s/eks/$f | kubectl apply -f -; done
   kubectl get pods        # BOTH Running at once, no Pending, no OOM
   ```
   Note: the serve Deployment looks for the adapter at `/work/outputs/k8s/final` on the PVC. `scripts/serve.sh` serves the base model only when that folder does not exist yet, so serve starts fine alongside training and gains the `tuned` model only if you restart it after training finishes. Record GPU memory per slice with `kubectl exec -n gpu-operator ds/nvidia-device-plugin-daemonset -- nvidia-smi` (VERIFY the container has nvidia-smi; otherwise run it on the node).
7. **Failure and Moving evidence** (same tests as the 4070): delete the training pod and time delete to first step; delete the serve pod and time recovery. Moving: list how many lines differ between local and EKS manifests:
   ```bash
   for f in train-job serve-deployment pvc; do echo "$f: $(diff k8s/$f.yaml k8s/eks/$f.yaml | grep -c '^[<>]') changed lines"; done
   ```
   and the image push time from section A.4. Say honestly that the manifests changed (image names, storage class, Service type), so "same setup" means a small, known diff, not zero.
8. **Optional:** Grafana is not needed for MIG. Skip it unless time remains.

## C. Tear down (do not skip, the meter runs)
```bash
eksctl delete cluster -f k8s/eks/cluster.yaml
aws ec2 describe-volumes --region $REGION --filters Name=status,Values=available --query 'Volumes[].VolumeId'      # leftover EBS volumes
aws elbv2 describe-load-balancers --region $REGION --query 'LoadBalancers[].LoadBalancerName'                      # leftover load balancers (the serve Service)
aws eks list-clusters --region $REGION
```
Delete any leftover volumes or load balancers. Optionally delete the ECR repos (`aws ecr delete-repository --force --repository-name gpu-train`, same for gpu-serve). Check the AWS billing page the next day.

## D. What to record in `results-eks-h100.md`
MIG: supported yes/no on this instance, time from label to `success`, slice count, memory test result per pod. Operator: time to GPU visible, workarounds needed (count). Failure recovery times and time to first step. Image push time. Manifest diff line counts. Total session time and cost. Anything that failed, with the exact error: failures are demo material.

## E. Do not claim afterwards
Growing (this is one node), MIG fault isolation (only memory was tested unless you add a crash test), anything about other GPUs or regions.
