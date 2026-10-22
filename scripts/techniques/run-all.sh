#!/usr/bin/env bash
# Everything for the sharing techniques after the baseline (run-sharing.sh none).
cd "$(dirname "$0")/../.."
for s in ts2 ts4 mps2; do bash scripts/techniques/run-sharing.sh $s > logs/techniques/out-$s.log 2>&1; echo "DONE sharing $s exit=$?"; done
bash scripts/techniques/run-extra.sh oom ts4 > logs/techniques/out-oom.log 2>&1; echo "DONE oom exit=$?"
for s in ts4 mps2; do bash scripts/techniques/run-extra.sh fault $s > logs/techniques/out-fault-$s.log 2>&1; echo "DONE fault $s exit=$?"; done
for s in mps2 ts4; do bash scripts/techniques/run-extra.sh memtest $s > logs/techniques/out-memtest-$s.log 2>&1; echo "DONE memtest $s exit=$?"; done
echo ALL-DONE
