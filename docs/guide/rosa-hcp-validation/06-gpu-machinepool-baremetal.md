# UC-05 — GPU worker machine pool on bare metal ROSA

**Provenance:** [ROSA Technical Solutions.pdf](../../ROSA%20Technical%20Solutions.pdf) — Scenario 5.

## Summary

Add a **GPU** MachinePool (e.g. `g4dn.xlarge`) on a cluster whose primary workers use **bare metal**, isolate with **taints**, install **NVIDIA GPU Operator**, and schedule a GPU pod.

## Why this matters

- ML inference/training bursts without converting the whole cluster to GPU nodes.
- Validates taints/tolerations and `nvidia.com/gpu` resource limits on ROSA.
- OpenShift AI / CUDA samples depend on this node layout.

## Architecture

```
 [ROSA Cluster]
      |
 +----+----+
 |         |
 [MP: baremetal]     [MP: gpu-pool]
 m5zn.metal          g4dn.xlarge
 standard/VMs        taint: nvidia.com/gpu
      |                    |
 [Virt / apps]        [GPU workload]
```

## Prerequisites

- **Bare metal profile** — see [01-prerequisites.md](01-prerequisites.md). If only VM workers exist → **BLOCKED**.
- ROSA CLI admin; cluster name set.

```bash
export CLUSTER_NAME=my-rosa-cluster
```

## Steps

1. Create GPU machine pool (PDF):

   ```bash
   rosa create machinepool \
     --cluster="${CLUSTER_NAME}" \
     --name=gpu-pool \
     --instance-type=g4dn.xlarge \
     --replicas=1 \
     --labels="node.kubernetes.io/workload-type=gpu" \
     --taints="nvidia.com/gpu=present:NoSchedule"
   ```

2. Wait for node Ready:

   ```bash
   oc get nodes -l node.kubernetes.io/workload-type=gpu
   ```

3. Install **NVIDIA GPU Operator** from OperatorHub (console or `Subscription`).

4. Deploy GPU test pod (PDF):

   ```yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: gpu-inference-job
     namespace: my-app
   spec:
     nodeSelector:
       node.kubernetes.io/instance-type: g4dn.xlarge
     tolerations:
       - key: nvidia.com/gpu
         operator: Exists
         effect: NoSchedule
     containers:
       - name: cuda-vector-add
         image: nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda10.2
         resources:
           limits:
             nvidia.com/gpu: "1"
   ```

5. Check logs:

   ```bash
   oc logs -n my-app gpu-inference-job
   ```

## Expected output

- GPU node `Ready`
- GPU Operator pods healthy in operator namespace
- CUDA sample completes vector add successfully in logs

## Success criteria

```bash
oc get node -l node.kubernetes.io/instance-type=g4dn.xlarge -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' | grep -q True
oc logs -n my-app gpu-inference-job 2>&1 | grep -iE 'Test PASSED|Completed'
```

## Failure signals

- No GPU node → quota, instance availability, or wrong cluster type.
- `Insufficient nvidia.com/gpu` → operator not installed or driver not loaded.
- **BLOCKED** (not FAIL) when bare metal prerequisite missing.
