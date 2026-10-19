# Project instructions for Claude Code

This repo is a proof of concept for the tech talk "Beyond kubectl apply: Elevating GPU Workflows with NVIDIA on Kubernetes". It was started in another Claude Code session on WSL2; you are probably continuing on a different machine with no memory of it.

FIRST: read `CONTINUE-ON-UBUNTU.md` (full context, task list, demo plan, decisions, open items), then `SUMMARY.md`, `results.md`, `RUNBOOK.md`, `SLIDE-EVIDENCE.md`.

Standing rules from the user:
- Be concise, make decisions yourself, keep moving. Do not use em dashes in anything you write.
- Work phase by phase; after each phase give a brief summary and wait for the go-ahead.
- Ask before system-wide installs, before changing system or Windows/WSL settings, and before deleting anything outside this folder. You cannot run sudo (needs a password): give the user the exact command to run, then verify the result yourself.
- Be honest. Report real measured numbers, say plainly when something is uncertain, unsupported or failed, and never claim the GPU Operator installed the driver or toolkit unless it actually did. Do not hide problems, they are demo material.
- Keep terminal output clean and commands copy-paste-able: the final run is screen-recorded.
- Commit and push to a branch for this machine (for example `ubuntu-4070`), never mix numbers from different machines in one table. Add the commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Pronouns: use they/them for anyone whose pronouns are not stated.

Shell gotchas that already cost time: zsh aborts a whole line on an unmatched glob; `pkill -f` can match its own shell line (check with `pgrep -af` first); always put a liveness check in wait loops.
