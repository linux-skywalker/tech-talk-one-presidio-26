#!/usr/bin/env bash
# The 3 single runs reported in results-kueue-4070.md (one run per arm; every number is labelled single).
cd "$(dirname "$0")/../../.."
for r in "s1 plain" "s1 kueue" "s2 kueue"; do
  set -- $r; bash scripts/demo/kueue/run.sh $1 $2 1 > logs/kueue/run_$1_$2_1.log 2>&1; echo "DONE $1 $2 exit=$?"
done
echo SWEEP-COMPLETE
