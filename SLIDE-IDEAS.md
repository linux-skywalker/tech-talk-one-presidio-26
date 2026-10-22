# Slide ideas: slides 7 and 8 (for the presenters to draft)

The deck covers slides 1 to 6 (the crisis: SPEND, COST, HOARD, UTILIZE, CONSEQUENCE; 5% average GPU use, Cast AI 2026, against a 65% benchmark). These are ideas only, not final text.

## Slide 7: Why Kubernetes solves it
Map each cause on slide 5 to a fix:
- Provisioned for peak, billed 24/7 -> pods request GPUs and release them; scheduling fills the card.
- No sharing between teams -> time slicing, MPS and MIG through the NVIDIA device plugin (time slicing measured on the RTX 4070; MPS and MIG are theory; the 4070 has no MIG).
- Kubernetes cannot see GPUs -> NVIDIA GPU Operator: device plugin, node labels, DCGM metrics (ran it).
- Manual setup, slow deployment cycles -> declarative manifests, self-healing, the same files on any cluster.
- Leverage: engineers already know these tools; apply them to the GPU data center.

## Slide 8: How we quantify it: six metrics
One line each, in video order:
1. Sharing: GPU busy %, cards needed.
2. Failures: seconds to recover, out of the box.
3. Watching: live view of the GPU.
4. Moving: changed lines between hosts (WSL2 vs native Ubuntu: 0 of 4 manifests).
5. Setting up: repeatable, leverage of known tools (no speed claim).
6. Growing: theory.

Rules: cited studies only for data center numbers; never mix 4070 numbers with them; optimistic tone.
