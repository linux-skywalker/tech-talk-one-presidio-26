# DRA on one RTX 4070

The full tables are in `results-kueue-4070.md` (sections "Phase 2" and "More DRA tests"). Raw data: `logs/dra/`, manifests: `k8s/kueue/dra-*.yaml`.
Environment: Kubernetes v1.36.5+k3s1 (DRA stable since v1.35, `resource.k8s.io/v1` served), NVIDIA DRA driver chart 0.5.1 with the GPU Operator device plugin disabled, feature gates `TimeSlicingSettings` and `MPSSupport` enabled for the sharing tests.
Measured (single runs unless stated): the driver published the RTX 4070 as device `gpu-0` (GeForce, Ada Lovelace, 12282Mi; `logs/dra/resourceslice-rtx4070.yaml`), so it is NOT rejected as a consumer card; a pod with a ResourceClaimTemplate got the GPU; a second exclusive claim stayed Pending; one shared claim worked for two pods; a memory CEL selector accepted `>=10Gi` and rejected `>=20Gi`; time slicing and MPS can be set in the claim (each needed a driver feature gate); two training jobs took 61 s with a shared claim against 62 s with the device plugin (n=1 each), so no speed difference.
What the device plugin cannot express and DRA can (from these tests): choosing a device by attribute (memory, product name), sharing one claim between pods with the sharing mode set per claim.
Combined DRA + Kueue test (3 runs each): see `results-kueue.md`, section "Combined test". Consumable memory shares: `logs/dra/consumable-probe.txt`.
NOT DONE: pod startup time comparison against `nvidia.com/gpu: 1`.
