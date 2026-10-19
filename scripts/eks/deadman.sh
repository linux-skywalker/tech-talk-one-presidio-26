#!/usr/bin/env bash
# OPTIONAL safety net against a forgotten cluster: deletes the EKS cluster after N hours, no questions asked.
# usage: REGION=us-east-1 nohup bash scripts/eks/deadman.sh 5 > logs/eks_deadman.log 2>&1 &     (cancel with: pkill -f 'eks/[d]eadman.sh')
# It will delete the cluster even in the middle of a demo, so pick N with margin. Does not replace checking the AWS billing page.
: "${REGION:?set REGION}"; H=${1:?hours}
echo "$(date +%T) cluster ${CLUSTER:-gpu-talk} will be deleted in $H hours"
sleep $(( H * 3600 ))
echo "$(date +%T) deleting"
FORCE=1 bash "$(dirname "$0")/session.sh" teardown
