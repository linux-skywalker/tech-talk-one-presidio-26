# Rehearsal (2026-10-16), RUNBOOK commands replayed after the platform setup (K1 to K5 not replayed: sudo, would need a teardown)

| Step | Result |
|---|---|
| Traditional: train, SIGKILL at step 316, resume from checkpoint-300 | Passed. Resume ran 441 s of training to finish. |
| Traditional: serve + ask base and tuned | Passed, 65 s to ready, no failures (flags already known) |
| K8s: fresh PVC, apply Job to first training step | 128 s (cold: includes model download, image already local) |
| K8s: delete training pod | Job resumed from checkpoint-125 in 62 s, no human action |
| K8s: Job completes | 13 min |
| K8s: apply Deployment to first answer | 109 s |
| K8s: delete serve pod to answering | 107 s |
| K8s: second Job while vLLM holds GPU | Pending (Insufficient nvidia.com/gpu) |
| K8s: enable time slicing | 10 s to both running, 10/10 inference requests answered, 71% util, 6.1 GB at that moment |

## Runbook bugs found and fixed
- Rerunning on old outputs resumes from the final checkpoint and finishes in 2 s. Added a "Reset between takes" section.
- The sharing demo needs time slicing turned back off before the next take. Added to the reset section.
## Gotchas for the operator
- `kubectl logs job/train` picks one pod; during a retry use `kubectl logs -l app=train --tail=20`.
- Commands with unmatched globs abort the whole line in zsh.
