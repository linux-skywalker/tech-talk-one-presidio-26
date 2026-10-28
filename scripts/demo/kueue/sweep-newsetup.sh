#!/usr/bin/env bash
# No-queue arm of the 6-job workload, 3 more runs on the new setup (kernel 7.0.0-38, driver 595.99.02), run ids 11 to 13. Kept apart from the measured runs 1 to 3 (kernel 6.17, driver 590.48.01).
cd "$(dirname "$0")/../../.."
for rep in 11 12 13; do
  bash scripts/demo/kueue/run.sh s5 plain $rep > logs/kueue/run_s5_plain_$rep.log 2>&1; echo "DONE s5 plain $rep exit=$?"
  sleep 20
done
echo SWEEP-COMPLETE
