#!/usr/bin/env bash
# Take 2: with DRA (every pod asks for the GPU memory it needs, in GiB).
bash "$(dirname "$0")/run-asks.sh" dra
