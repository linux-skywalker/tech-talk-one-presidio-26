#!/usr/bin/env bash
# Take 1 of the before/after video: the 6-job workload with NO queue. Run number 9 keeps it apart from the measured runs 1 to 3.
cd "$(dirname "$0")/../../../.." && bash scripts/demo/kueue/run.sh s5 plain 9 2>&1 | stdbuf -oL sed -E -f scripts/demo/kueue/video/run-labels.sed
