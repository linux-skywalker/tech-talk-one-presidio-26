#!/usr/bin/env bash
# The 6-job workload (scenario s5): inference server already running, then 3 jobs per team of mixed sizes. 3 runs per arm.
# Arms with the device plugin and time slicing x8: plain (no queue, baseline A) and kueue.
cd "$(dirname "$0")/../../.."
for rep in 1 2 3; do for arm in plain kueue; do
  bash scripts/demo/kueue/run.sh s5 $arm $rep > logs/kueue/run_s5_${arm}_$rep.log 2>&1; echo "DONE s5 $arm $rep exit=$?"
done; done
echo SWEEP-COMPLETE
