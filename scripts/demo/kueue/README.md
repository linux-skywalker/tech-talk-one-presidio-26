# Kueue demo: 5 minute script (single RTX 4070)

Runs take 4 to 5 minutes each live, so show trimmed recordings of `run.sh` output or the saved summaries in `logs/kueue/*/summary.txt`. Everything below is a single run; say so on screen.

| Time | On screen | Say |
|---|---|---|
| 0:00 | `k8s/kueue/queues.yaml` | Two teams, one cohort, a quota of 8 GPU units on one 12 GB card. A unit is about 1.5 GB: a convention we chose, not isolation. |
| 0:45 | `bash scripts/demo/kueue/run.sh s1 plain 1`, trimmed | Today's setup: training jobs start first, the inference server crash-loops (4 restarts) and answers at 208 s. |
| 1:45 | `bash scripts/demo/kueue/run.sh s1 kueue 1`, trimmed | Same workloads through Kueue: server answers at 56 s, one training job waits 110 s. Average GPU busy 89% vs 76%. |
| 2:45 | `bash scripts/demo/kueue/run.sh s4 kueue-nopreempt 1` then `s4 kueue 1` | Inference arrives while batch work runs. Without preemption it waits (206 s). With preemption one training job is re-queued and inference answers at 87 s. |
| 3:45 | `kubectl get resourceslice -o yaml` (saved in `logs/dra/`) | Next step in Kubernetes: DRA. The NVIDIA driver published the RTX 4070 as a device, and a claim can ask by attribute (memory) or set time slicing. |
| 4:30 | `results-kueue-4070.md` claims table | What we can say: admission and priority kept inference up in these runs. What we cannot: averages, latency wins, fairness under a flood, MIG, other GPUs. |
