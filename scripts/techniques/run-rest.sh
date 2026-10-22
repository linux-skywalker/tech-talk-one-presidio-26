#!/usr/bin/env bash
# Remaining extra tests after the fault-test fix.
cd "$(dirname "$0")/../.."
for s in ts4 mps2; do bash scripts/techniques/run-extra.sh fault $s > logs/techniques/out-fault-$s.log 2>&1; echo "DONE fault $s exit=$?"; done
for s in mps2 ts4; do bash scripts/techniques/run-extra.sh memtest $s > logs/techniques/out-memtest-$s.log 2>&1; echo "DONE memtest $s exit=$?"; done
echo ALL-DONE
