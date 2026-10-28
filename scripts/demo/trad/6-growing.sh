#!/usr/bin/env bash
# Metric 6 of 6, traditional way: add a second machine. Shows what it takes, using this machine's own measured setup time. Nothing is installed.
# usage: bash scripts/demo/trad/6-growing.sh        (about 10 seconds)
source "$(dirname "$0")/../common.sh"
step 6 "Growing (traditional)"
problem "A second machine means doing the whole setup again by hand, copying the adapter, and building your own way to send traffic to both."
T=$(cat logs/demo_trad_setup_seconds.txt 2>/dev/null)
echo "${B}Checklist for machine 2${R}"
for s in "install the NVIDIA driver and check CUDA" "create the Python environment ($(wc -l < scripts/requirements-trad.lock) pinned packages)" "copy or download the model cache ($(du -shL ~/.cache/huggingface 2>/dev/null | cut -f1))" "copy the adapter files" "start vLLM with the same flags and ports" "put a load balancer in front, and keep its list of servers up to date" "set up monitoring for the new host again"; do say "  [ ] $s"; done
echo "${B}Load balancer you would write yourself (sketch, not run)${R}"
cat <<'NGINX'
  upstream llm { server host1:8000; server host2:8000; }   # edit and reload for every machine added or lost
  server { listen 80; location / { proxy_pass http://llm; } }
NGINX
if [ -n "$T" ]; then
  echo "${B}Scoreboard: growing, traditional${R}"
  echo "  measured setup on this machine (warm cache): ${T} s"
  for n in 2 4 8; do echo "  $n machines, one at a time by hand: about $((T*n)) s of hands-on setup"; done
  note "That arithmetic multiplies one measured setup; it is not a measured multi-machine run."
else note "Run scripts/demo/trad/5-setting-up.sh first to get this machine's measured setup time."; fi
result "Growing" "each machine repeats the full setup by hand (${T:-?} s measured once here) plus a hand-built load balancer; not measured with a second machine"
