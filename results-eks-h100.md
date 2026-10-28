# Results: EKS with 1x H100 (p5.4xlarge), MIG and Moving (NOT RUN YET)

Plan: `k8s/eks/MIG-SESSION.md`. Fill this in during the session. Do not mix with `results-ubuntu-4070.md` or `results.md`. Ubuntu 4070 values are shown only for reference.

| Item | EKS H100 | Ubuntu 4070 (reference) |
|---|---|---|
| Instance, region, zone, driver version, AMI | | RTX 4070, driver 590.48.01 |
| MIG supported on this instance (yes/no) | | not possible |
| Time from `mig.config` label to `state=success`, slice count | | n/a |
| MIG memory test: greedy stops at, steady grows (yes/no) | | MPS: greedy 5 GiB, steady grew. Time slicing: steady could not grow |
| Serve and train running at once on separate slices, any Pending or OOM | | time slicing: second training Job OOM |
| `eksctl create cluster` to node Ready | | k3s ready in 27 s |
| Operator install to GPU visible | | 33 s |
| Workarounds needed (cgroup, PCI label, mounts) | | none |
| Image push to ECR | | local registry |
| Manifest lines changed vs local (train-job, serve-deployment, pvc) | | |
| Training pod delete to first step | | about 51 s |
| Serve pod delete to answering | | 81 s |
| Session length and cost | | n/a |
| What failed (exact errors) | | toolkit.enabled=true broke the node |
