#!/usr/bin/env bash
# Metric 4 of 6, traditional way: what is tied to this host. Live: host facts, hard-coded paths, size of what must be rebuilt or copied.
# usage: bash scripts/demo/trad/4-moving.sh        (about 30 seconds)
source "$(dirname "$0")/../common.sh"
step 4 "Moving (traditional)"
problem "The setup lives on this host: driver, Python environment, paths, caches. A new host or cloud means redoing it and fixing what differs."
echo "${B}What this host provides (must match on the new host)${R}"
say "  OS/kernel:      $(. /etc/os-release; echo "$PRETTY_NAME"), $(uname -r)"
say "  NVIDIA driver:  $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)  (GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader))"
say "  Python in env:  $(.venv-trad/bin/python --version 2>&1)   torch $(.venv-trad/bin/python -c 'import torch;print(torch.__version__, "CUDA", torch.version.cuda)' 2>/dev/null)"
say "  vLLM:           $(.venv-trad/bin/python -c 'import vllm;print(vllm.__version__)' 2>/dev/null)"
echo "${B}What has to be rebuilt or copied${R}"
say "  Python environment: $(du -sh .venv-trad | cut -f1), $(wc -l < scripts/requirements-trad.lock) pinned packages (not portable: built for this OS, driver and Python)"
say "  Model cache:        $(du -shL ~/.cache/huggingface 2>/dev/null | cut -f1) in ~/.cache/huggingface"
say "  Training outputs:   $(du -sh outputs 2>/dev/null | cut -f1) in outputs/"
echo "${B}Host-specific references in our scripts${R}"
show grep -nE 'venv-trad|\.cache/huggingface|localhost|outputs/|/home/' scripts/serve.sh scripts/ask.sh scripts/train.py scripts/loadtest.sh
N=$(grep -cE 'venv-trad|\.cache/huggingface|localhost|outputs/|/home/' scripts/serve.sh scripts/ask.sh scripts/train.py scripts/loadtest.sh | awk -F: '{s+=$2} END{print s}')
note "Honest read: the scripts themselves are mostly relative paths and localhost. The real tie is the $(du -sh .venv-trad | cut -f1) environment and its driver/CUDA pairing."
echo "${B}Scoreboard: moving, traditional${R}"
echo "  host facts that must match:  OS, driver (this torch build is CUDA 13.0, which needs a recent driver), Python version, the pinned packages"
echo "  host-specific lines in scripts: $N"
echo "  to move: rebuild the environment ($(wc -l < scripts/requirements-trad.lock) packages), copy the model cache, re-check paths"
result "Moving" "tied to this host: $(du -sh .venv-trad | cut -f1) environment not portable, $N host-specific script lines, redo setup per host"
