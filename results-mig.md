# MIG on the RTX 4070: NOT SUPPORTED

Raw output: `logs/techniques/mig-probe.txt` (single probe, 2026-10-23).
```
$ nvidia-smi --query-gpu=name,compute_cap,driver_version,mig.mode.current,mig.mode.pending --format=csv
NVIDIA GeForce RTX 4070, 8.9, 590.48.01, [N/A], [N/A]
$ nvidia-smi mig -lgip
No MIG-supported devices found.        (exit 6)
$ nvidia-smi -i 0 -mig 1
Unable to enable MIG Mode for GPU 00000000:01:00.0: Insufficient Permissions    (exit 4, no root)
$ sudo -n nvidia-smi -i 0 -mig 1
sudo: a password is required
```
What this shows: the GPU reports MIG mode `[N/A]` and the driver lists no MIG-capable device, so MIG is not supported on this card (GeForce, compute capability 8.9). The attempt to enable MIG stopped at a permission error because this session has no root; the support finding rests on `mig -lgip` and the `[N/A]` mode, not on that error. Nothing else was measured and MIG was not simulated.
