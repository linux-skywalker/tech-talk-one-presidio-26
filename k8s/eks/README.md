# EKS variants (untested, prepared on WSL2)

Differences from `k8s/`: ECR image names (replace ACCOUNT_ID and REGION), EBS gp3 StorageClass and PVC, LoadBalancer Service instead of NodePort.
Before applying:
1. Cluster with an EKS accelerated AMI node group (Amazon Linux 2023 NVIDIA). The AMI ships the driver and toolkit.
2. EBS CSI add-on: `eksctl create addon --name aws-ebs-csi-driver --cluster <name>`, then `kubectl apply -f k8s/eks/storageclass.yaml`.
3. GPU Operator with `--set driver.enabled=false --set toolkit.enabled=false`.
4. Push images to ECR: `aws ecr create-repository --repository-name gpu-train` (and gpu-serve), `aws ecr get-login-password | docker login ...`, `docker tag` and `docker push`.
5. The images use torch with CUDA 13.0. If the AMI driver is older than R580, rebuild with a CUDA 12.x torch wheel or the pods fail at CUDA init.
6. Use `kubectl get svc serve` for the load balancer address. `runtimeClassName: nvidia` requires the RuntimeClass to exist; the Operator creates it. If it does not, delete that line.
