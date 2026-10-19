#!/usr/bin/env bash
# Imports k8s/dashboards/nvidia-dcgm-12239.json into Grafana (NodePort 30300, admin/admin) bound to the Prometheus datasource.
jq -n --slurpfile d "$(dirname "$0")/../k8s/dashboards/nvidia-dcgm-12239.json" \
  '{dashboard:($d[0]|del(.id)), overwrite:true, folderId:0, inputs:[{name:"DS_PROMETHEUS",type:"datasource",pluginId:"prometheus",value:"prometheus"}]}' \
 | curl -s -u admin:admin -H 'Content-Type: application/json' -X POST localhost:30300/api/dashboards/import -d @- | jq -c '{title:.title, url:.importedUrl, error:.message}'
