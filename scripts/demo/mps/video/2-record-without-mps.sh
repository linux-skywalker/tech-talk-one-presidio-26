#!/usr/bin/env bash
# Take 1: without MPS (plain time slicing: every pod can use all the GPU memory).
bash "$(dirname "$0")/run-memtest.sh"
