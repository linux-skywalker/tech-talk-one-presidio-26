#!/usr/bin/env bash
# Take 2: the same two pods under MPS (each pod gets its own memory limit).
bash "$(dirname "$0")/run-memtest.sh"
