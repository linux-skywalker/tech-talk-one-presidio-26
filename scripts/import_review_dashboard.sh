#!/usr/bin/env bash
# Creates Grafana's built-in TestData source (uid testdata, used for the static measured-results panels) and imports k8s/dashboards/project-review.json.
# usage: bash scripts/import_review_dashboard.sh [dashboard.json]      (default project-review.json; GRAFANA=localhost:30300, login admin:admin)
cd "$(dirname "$0")/.." || exit 1
G=${GRAFANA:-localhost:30300}; AUTH=admin:admin
curl -s -u $AUTH $G/api/datasources/uid/testdata | jq -e '.uid' >/dev/null 2>&1 || \
  curl -s -u $AUTH -H 'Content-Type: application/json' -X POST $G/api/datasources -d '{"name":"TestData","type":"grafana-testdata-datasource","uid":"testdata","access":"proxy"}' | jq -c '{datasource:.message}'
jq '{dashboard:(.|del(.id)), overwrite:true, folderId:0}' "${1:-k8s/dashboards/project-review.json}" \
 | curl -s -u $AUTH -H 'Content-Type: application/json' -X POST $G/api/dashboards/db -d @- | jq -c '{status, url, error:.message}'
