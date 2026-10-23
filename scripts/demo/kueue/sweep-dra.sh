#!/usr/bin/env bash
# The 6-job workload on DRA + Kueue (capacity-based quota in GiB of GPU memory), 3 runs. Needs the DRA driver installed (consumable shares) and the Kueue config from scripts/techniques notes.
cd "$(dirname "$0")/../../.."
for rep in 1 2 3; do
  bash scripts/demo/kueue/run.sh s5 dra-kueue $rep > logs/kueue/run_s5_dra-kueue_$rep.log 2>&1; echo "DONE s5 dra-kueue $rep exit=$?"
done
echo SWEEP-COMPLETE
