# Slide "Run GPUs like the rest of your software": claim vs evidence

Status: Proven (measured on WSL2), Partial, Not proven.

| Row | Slide says | Status | Evidence we have | What is missing or contradicts |
|---|---|---|---|---|
| Setting up | By hand on every machine vs set once, applied everywhere | Not proven | Manifests and images are reusable | First-time setup was slower on Kubernetes (about 30 min vs about 20 min) and needed 3 WSL2 workarounds. Only one machine tested. Needs the H100 run or a second machine. |
| Watching | Check a terminal vs live dashboards | Partial | DCGM exporter runs and serves live GPU metrics (GPU_UTIL, FB_USED, TEMP, POWER) at port 9400 | No Prometheus or Grafana dashboard built. We have the data source, not the dashboard. |
| Sharing | One job blocks the GPU vs jobs share it | Proven, with a limit | Second pod Pending ("Insufficient nvidia.com/gpu"); after time slicing both ran, 10/10 inference requests answered during training, no OOM | No memory isolation: peak 11.9 of 12.3 GB. MIG (real isolation) is not possible on an RTX 4070 and cannot run on WSL2. In the traditional path nothing "blocks" the GPU, jobs just compete or OOM, so word the left side carefully. |
| Failures | Someone gets a message vs it restarts itself | Proven | Training: pod deleted, Job resumed from checkpoint in 62 to 98 s. Serving: pod deleted, answering again in 103 to 107 s. Traditional: killed training stayed dead until a human reran it | Recovery is about 1 to 2 min, not instant. Resume needs checkpoints, which we wrote into the script. |
| Growing | Rebuild a machine vs add a machine | Not proven | Nothing | Single node only. Would need a second node joined to the cluster. |
| Moving | Rewrite for each cloud vs same setup runs anywhere | Not proven | Same manifests and images carry over in principle | WSL2 needed workarounds that a "same setup" claim hides. Registry is local. Needs the H100 VM run. |

## Safe wording until the gaps are closed
- Say "restarts itself" and "jobs share it" with the numbers above.
- Say "live GPU metrics are available" for Watching, not "live dashboards", unless a dashboard is built.
- Do not show "Set once, applied everywhere", "Add a machine" or "Same setup runs anywhere" as results. Present them as the goal, or as what the H100 run will test.
- Do not say MIG. It is unsupported on this GPU and on WSL2 (`nvidia-smi mig -lgip`: "No MIG-supported devices found").

## Cheapest ways to close gaps
1. Watching: install Prometheus and Grafana, import the NVIDIA DCGM dashboard (about 15 min, optional, heavier install).
2. Moving and Setting up: run the H100 checklist and record which workarounds vanish.
3. Growing: join a second node (needs a second machine or VM).
