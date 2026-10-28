#!/usr/bin/env bash
# usage: log_step.sh <path-label> <step description> -- <command...>
# Appends wall-clock seconds for a step to logs/steps.csv
label="$1"; desc="$2"; shift 3
start=$(date +%s)
"$@"; rc=$?
end=$(date +%s)
echo "$label,\"$desc\",$((end-start)),$rc" >> "$(dirname "$0")/../logs/steps.csv"
exit $rc
