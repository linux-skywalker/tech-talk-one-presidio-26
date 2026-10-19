# MIG on EKS with an H100 (untested, written on WSL2 where MIG is impossible)

H100 80 GB profile names differ from A100 40 GB. List the real ones first:
    kubectl exec -n gpu-operator ds/nvidia-device-plugin-daemonset -- nvidia-smi mig -lgip

Operator install flags for a MIG demo (mixed strategy lets pods request specific slices):
    --set mig.strategy=mixed --set driver.enabled=false --set toolkit.enabled=false

Label the node to ask the MIG manager for a layout (the Operator ships `all-1g.10gb`, `all-2g.20gb`, `all-3g.40gb` style configs, check the exact names with the command below):
    kubectl get cm -n gpu-operator default-mig-parted-config -o yaml | grep -E "^  *all-"
    kubectl label node <node> nvidia.com/mig.config=all-3g.40gb --overwrite
The MIG manager enables MIG mode and may need the GPU reset or a node reboot. Wait for `nvidia.com/mig.config.state=success`.

Pods then request a slice instead of a whole GPU, for example in resources.limits:
    nvidia.com/mig-3g.40gb: 1
Edit k8s/eks/serve-deployment.yaml and train-share-job.yaml to use that resource name (serve and training each get a slice).
A 1.5B model needs about 10 GB for vLLM at 0.3 of a slice, and about 8 GB for LoRA training at batch 1, so a 2g.20gb slice is the smallest comfortable one.
