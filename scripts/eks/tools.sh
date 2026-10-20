#!/usr/bin/env bash
# Per-user install (no sudo) of the AWS-side tools into ~/.local/bin: aws cli v2, eksctl, kubectl, helm. Re-runnable, skips what exists.
# usage: bash scripts/eks/tools.sh      then: aws configure   (or aws sso login), and check: aws sts get-caller-identity
set -u
export PATH=$HOME/.local/bin:$PATH; mkdir -p ~/.local/bin; D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
have() { command -v "$1" >/dev/null && echo "[PASS] $1: $(command -v "$1")"; }
command -v aws >/dev/null || { curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o "$D/aws.zip" && python3 -c "import zipfile,sys; zipfile.ZipFile('$D/aws.zip').extractall('$D')" && chmod -R u+x "$D/aws" && "$D/aws/install" -i ~/.local/aws-cli -b ~/.local/bin >/dev/null; }
command -v eksctl >/dev/null || curl -fsSL https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz | tar xz -C ~/.local/bin eksctl
command -v kubectl >/dev/null || { v=$(curl -fsSL https://dl.k8s.io/release/stable.txt) && curl -fsSL -o ~/.local/bin/kubectl "https://dl.k8s.io/release/$v/bin/linux/amd64/kubectl" && chmod +x ~/.local/bin/kubectl; }
command -v helm >/dev/null || { curl -fsSL https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz | tar -xz -C "$D" linux-amd64/helm && mv "$D/linux-amd64/helm" ~/.local/bin/helm; }
rc=0; for t in aws eksctl kubectl helm; do have $t || { echo "[FAIL] $t missing"; rc=1; }; done
command -v docker >/dev/null && have docker || echo "[WARN] docker missing: only needed on the machine that pushes images to ECR"
aws --version 2>/dev/null; eksctl version 2>/dev/null
exit $rc
