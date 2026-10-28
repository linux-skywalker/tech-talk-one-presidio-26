#!/usr/bin/env bash
# Take 2 of the before/after video: the same 6-job workload through Kueue. Run number 9 keeps it apart from the measured runs 1 to 3.
cd "$(dirname "$0")/../../../.." && bash scripts/demo/kueue/run.sh s5 kueue 9 2>&1 | stdbuf -oL sed -E -f scripts/demo/kueue/video/run-labels.sed
