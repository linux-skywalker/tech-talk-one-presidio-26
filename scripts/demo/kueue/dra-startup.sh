#!/usr/bin/env bash
# Pod startup time: create to container started, and create to finished (nvidia-smi -L), 3 pods one after another.
# usage: dra-startup.sh plugin|dra  (dra needs the DRA driver installed and k8s/kueue/dra-startup.yaml claim template applied)
cd "$(dirname "$0")/../../.."
mode=$1
for i in 1 2 3; do
  n=st-$mode-$i
  if [ $mode = plugin ]; then
    kubectl apply -f - >/dev/null <<Y
apiVersion: v1
kind: Pod
metadata: {name: $n}
spec:
  restartPolicy: Never
  runtimeClassName: nvidia
  containers:
  - {name: c, image: "localhost:5000/gpu-train:v1", command: ["nvidia-smi","-L"], resources: {limits: {nvidia.com/gpu: 1}}}
Y
  else
    kubectl apply -f - >/dev/null <<Y
apiVersion: v1
kind: Pod
metadata: {name: $n}
spec:
  restartPolicy: Never
  containers:
  - {name: c, image: "localhost:5000/gpu-train:v1", command: ["nvidia-smi","-L"], resources: {claims: [{name: g}]}}
  resourceClaims: [{name: g, resourceClaimTemplateName: one-gpu-startup}]
Y
  fi
  for t in $(seq 1 120); do ph=$(kubectl get pod $n -o jsonpath='{.status.phase}'); [ "$ph" = Succeeded ] || [ "$ph" = Failed ] && break; sleep 1; done
  kubectl get pod $n -o json | python3 -c "
import sys,json,datetime as d
p=json.load(sys.stdin); f=lambda x:d.datetime.fromisoformat(x.replace('Z','+00:00'))
c=f(p['metadata']['creationTimestamp']); s=p['status']['containerStatuses'][0]['state']['terminated']
print('$mode',$i,p['status']['phase'],'created_to_started_s=%d'%(f(s['startedAt'])-c).total_seconds(),'created_to_finished_s=%d'%(f(s['finishedAt'])-c).total_seconds())"
  kubectl logs $n | head -1
  kubectl delete pod $n --now >/dev/null 2>&1; sleep 3
done
