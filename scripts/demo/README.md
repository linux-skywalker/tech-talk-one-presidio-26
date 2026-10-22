# Demo scripts

Run each pair side by side for the recording. Every script prints live data while it runs and ends with a scoreboard and one RESULT line.

| # | Metric | Traditional | Kubernetes + NVIDIA | Takes |
|---|---|---|---|---|
| 0 | Setup tour | `0-tour.sh` (code only, nothing runs) | | 1 min |
| 1 | Sharing | `trad/1-sharing.sh` | `kube/1-sharing.sh` (`SHARE_N=3` for fewer models) | 2 / 8 min |
| 2 | Failures | `trad/2-failures.sh` | `kube/2-failures.sh` | 4 / 5 min |
| 3 | Watching | `trad/3-watching.sh` | `kube/3-watching.sh` | 2 / 3 min |
| 4 | Moving | `trad/4-moving.sh` | `kube/4-moving.sh` | 0.5 min |
| 5 | Setting up (from scratch) | `trad/5-setting-up.sh` | `kube/5-setting-up.sh` (reinstalls the GPU Operator) | 4 / 5 min |
| 6 | Growing | `trad/6-growing.sh` | `kube/6-growing.sh` (Multipass VMs; CPU replicas, not GPU) | 0.1 / 8 min |

Notes
- Only one of the two paths may use the GPU at a time. Every script checks that the GPU is idle first.
- `all-in-one`: `trad.sh` and `kube.sh` run the whole sequence once (older, shorter versions of the same steps).
- Numbers are single runs on one RTX 4070 (native Ubuntu). Things marked "measured earlier" are printed from `results-ubuntu-4070.md`, not re-run.
- Growing needs `~/.k3s-node-token`, `~/multipass-images/` (Ubuntu cloud image, k3s binary, llama.cpp image tar, GGUF model) and Multipass. See `vm-grow.sh`.

Video decisions (user)
- Growing is told mostly as theory in the Remotion video. The live Growing scripts (`trad/6-growing.sh`, `kube/6-growing.sh`) stay as an optional short clip and as proof that nodes join; label it CPU replicas, by design.
- Sharing also covers MIG as theory in Remotion (three ways to share: time slicing, MPS, MIG), from `MIG-THEORY.md`. MIG was not run: the RTX 4070 has no MIG.
