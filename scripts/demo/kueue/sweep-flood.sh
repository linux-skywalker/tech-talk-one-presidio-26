#!/usr/bin/env bash
# Scenario 3 (team A floods the queue, team B submits two jobs later): one single run per arm.
cd "$(dirname "$0")/../../.."
for r in "s3 plain" "s3 kueue"; do
  set -- $r; bash scripts/demo/kueue/run.sh $1 $2 1 > logs/kueue/run_$1_$2_1.log 2>&1; echo "DONE $1 $2 exit=$?"
done
echo SWEEP-COMPLETE
