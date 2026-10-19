# EKS + H100 branch (`eks-h100`): ready to run, nothing here has run on AWS

Everything on this branch was written on an RTX 4070 machine, which cannot do MIG. The scripts reuse what worked there, but every AWS-specific line is untested. Items marked VERIFY are things I could not confirm. Read them before paying for anything.

Goal of the session: (1) MIG gives real memory isolation (the 4070 only showed time slicing failing and MPS limiting memory), (2) the same manifests and scripts run on a managed cloud (Moving), (3) which 4070 problems disappear on EKS. Results go in `results-eks-h100.md`, never mixed with the 4070 tables.

## Files
| File | Purpose |
|---|---|
| `scripts/eks/session.sh` | All stages, re-runnable: `preflight`, `cluster`, `operator`, `mig1g`, `mig2g`, `all`, `status`, `teardown` |
| `scripts/eks/deadman.sh` | Optional: deletes the cluster after N hours so a forgotten cluster cannot bill for days |
| `scripts/eks_push_images.sh` | Copies the two images from the local registry to ECR (run at home, before the cluster) |
| `k8s/eks/cluster.yaml` | One p5.4xlarge node, EBS CSI add-on, node group pinned to one zone |
| `k8s/eks/{pvc,storageclass,train-job,serve-deployment,mig-memtest}.yaml` | Manifests (ECR names, gp3, MIG memory test) |
| `k8s/eks/MIG-SESSION.md` | The same plan as manual commands, with the reasoning |
| `results-eks-h100.md` | Empty results table to fill in |

## Run order
```bash
# 0. one-time tools, per-user, no sudo
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip && unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install -i ~/.local/aws-cli -b ~/.local/bin
curl -fsSL https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz | tar xz -C ~/.local/bin eksctl
aws configure                                   # or SSO; then: aws sts get-caller-identity

# 1. at home, free
export REGION=us-east-1                         # pick the region where you have quota
REGION=$REGION scripts/eks_push_images.sh       # ~21 GB upload, prints ACCOUNT_ID
REGION=$REGION AZ=<zone> bash scripts/eks/session.sh preflight        # zone list is printed if AZ is unset

# 2. the paid part (log everything)
export AZ=<zone>
REGION=$REGION nohup bash scripts/eks/deadman.sh 5 > logs/eks_deadman.log 2>&1 &     # optional, see the file
bash scripts/eks/session.sh all 2>&1 | tee -a logs/eks_session.log                   # cluster, operator, mig1g, mig2g
# or one stage at a time: cluster | operator | mig1g | mig2g | status

# 3. always
REGION=$REGION bash scripts/eks/session.sh teardown    # asks you to type yes; then check the leftover list is empty
```
Each stage prints PASS or FAIL lines like `scripts/rehearsal.sh` does, writes timings to `logs/steps.csv` (labelled `eks-h100`), and stops `all` at the first failed stage. After fixing, rerun only that stage.

Time and cost: p5.4xlarge was listed at about $6.88/hr on-demand in us-east-1 by price aggregators (VERIFY on the AWS pricing page), plus the EKS control plane and EBS. I expect roughly 2 to 3 hours of paid time for the whole script, but the cluster creation time is a guess.

## What the stages do
1. **preflight** (free): tools present, AWS login, P-instance vCPU quota, the zone offers p5.4xlarge, both ECR images exist, `eksctl --dry-run` accepts the config.
2. **cluster**: `eksctl create cluster`, node Ready, instance type check, EBS CSI running, gp3 StorageClass.
3. **operator**: Helm install with `mig.strategy=single`, driver and toolkit installers OFF (the toolkit installer broke the 4070 host), GPU visible, RuntimeClass check (manifests lose `runtimeClassName` if the class is missing), smoke pod, **driver must be R580 or newer** for our CUDA 13 images.
4. **mig1g**: profile `all-1g.10gb` (7 slices), the greedy/steady memory test. Pass means greedy hit a limit and steady could still grow.
5. **mig2g**: profile `all-2g.20gb` (3 slices), training and serving running at the same time on separate slices, training pod delete (time to replacement and checkpoint resume), serve pod delete, load test, manifest diff counts for the Moving claim.

## Things I expect to go wrong, and what to do
| Symptom | Likely cause | Action |
|---|---|---|
| preflight: quota fails or unreadable | New accounts have 0 P-instance vCPUs. The quota code `L-417A185B` is from memory (VERIFY) | Request "Running On-Demand P instances" in Service Quotas. This can take days, start first |
| cluster: `InsufficientInstanceCapacity` | P5 capacity is scarce | Another zone or region, retry later, or a Capacity Block. Delete the half-created stack: `eksctl delete cluster` |
| cluster: node has no GPU driver | `amiFamily: AmazonLinux2023` may not pick the NVIDIA accelerated AMI (VERIFY in eksctl docs). A recommended accelerated AMI id may be available from the SSM parameter `/aws/service/eks/optimized-ami/<k8s-version>/amazon-linux-2023/x86_64/nvidia/recommended/image_id` (VERIFY the path) | Look up the AMI id and set `ami:` in the node group, following the eksctl docs for AL2023 custom AMIs |
| operator stage: driver below R580 | AMI driver older than the CUDA 13 wheels need | Plan B: rebuild `gpu-train` and `gpu-serve` with CUDA 12 builds of torch and vLLM, push again. I have not prepared or tested those Dockerfiles. Check this early, it costs images and time |
| operator: GPU never appears | Operator pods failing | `kubectl get pods -n gpu-operator`, `kubectl logs` the failing pod. Do NOT turn on `toolkit.enabled`: on the 4070 it replaced k3s's containerd config and broke the node |
| mig stage: `state=failed` or stuck pending | The MIG manager may need a GPU reset or node reboot on a cloud VM. NVIDIA's guide mentions `WITH_REBOOT` for Google Cloud; nothing EKS-specific found | `kubectl logs -n gpu-operator ds/nvidia-mig-manager`; `aws ec2 reboot-instances --instance-ids <id>`. Record exactly what happened. If MIG is not supported on this instance size, that is the finding (not confirmed either way for p5.4xlarge, VERIFY) |
| mig stage: profile name not found | Names differ by GPU | `kubectl get cm -n gpu-operator default-mig-parted-config -o yaml \| grep -E '^    all-'` and pass the real name |
| Known NVIDIA issue | Some 570-series drivers cannot schedule on nodes that mix MIG slices and whole GPUs | Use a different driver version if you hit it |
| pods `ImagePullBackOff` | ECR permissions or wrong account/region in the image name | `kubectl describe pod`. Managed node groups normally get ECR read access (VERIFY) |
| PVC stuck `Pending` | EBS CSI add-on or its IAM role missing | `kubectl get pods -n kube-system \| grep ebs`; `kubectl describe pvc work` |
| vLLM fails inside a slice | 1g.10gb is tight for vLLM | The workload stage uses 2g.20gb for that reason |
| `nvidia-smi` per-slice output empty | The device plugin container may not ship `nvidia-smi` (VERIFY) | Run it on the node: `kubectl debug node/<name> -it --image=ubuntu -- chroot /host nvidia-smi` |
| Do not combine | Time slicing or MPS config together with MIG | Do not apply `k8s/time-slicing-config.yaml` or `k8s/mps-config.yaml` on this cluster |

## After the session
- Teardown, then confirm no clusters, volumes or load balancers remain, and look at the AWS billing page the next day.
- Fill `results-eks-h100.md`. Failures with exact errors are demo material.
- Do not claim: Growing (one node), MIG fault isolation (only memory was tested), anything about other GPUs, or MIG on p5.4xlarge before it has worked.
