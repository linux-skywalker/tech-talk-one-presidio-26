#!/usr/bin/env bash
# Copies gpu-train:v1 and gpu-serve:v1 from the local registry (localhost:5000) to ECR. Run at home BEFORE starting the paid cluster.
# usage: REGION=us-east-1 scripts/eks_push_images.sh    (needs aws cli configured, docker access, local registry running)
set -euo pipefail
: "${REGION:?set REGION}"
ACC=$(aws sts get-caller-identity --query Account --output text)
REG=$ACC.dkr.ecr.$REGION.amazonaws.com
for n in gpu-train gpu-serve; do
  aws ecr describe-repositories --region "$REGION" --repository-names $n >/dev/null 2>&1 || aws ecr create-repository --region "$REGION" --repository-name $n >/dev/null
done
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REG"
for n in gpu-train gpu-serve; do
  t0=$(date +%s)
  docker pull localhost:5000/$n:v1
  docker tag localhost:5000/$n:v1 $REG/$n:v1
  docker push $REG/$n:v1
  echo "$n pushed in $(( $(date +%s) - t0 ))s"
done
echo "ACCOUNT_ID=$ACC REGION=$REGION"
