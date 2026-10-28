#!/usr/bin/env bash
# Take 1: without DRA (device plugin: every pod asks for "1 GPU", nobody checks the memory).
bash "$(dirname "$0")/run-asks.sh" plugin
