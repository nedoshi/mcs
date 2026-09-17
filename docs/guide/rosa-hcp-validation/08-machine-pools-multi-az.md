# TC-07 — Machine pools and multi-AZ

**Provenance:** Inferred from repo (`tf-rosa/examples/multi-az.tfvars.example`, `rosa create machinepool` in AI/inferentia docs).

**Source:** [Google Doc A](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) · [Google Doc B](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit)

## Summary

Validates additional **machine pools** across availability zones, including optional autoscaling bounds, without compromising cluster operator health.

## Why this matters

- Production ROSA HCP uses tiered pools (infra, GPU, memory-optimized).
- Multi-AZ failure domains are required for SLA and upgrade surge capacity.
- QE catches Machine API / HostedCluster node pool sync bugs.

## Architecture

```
 MachinePool "default"     MachinePool "gpu" (optional)
   AZ-a  AZ-b  AZ-c           AZ-a only
     \    |    /                  |
      worker nodes ───────────────┘
              │
      openshift-machine-api (HCP)
```

## Prerequisites

- TC-02 or TC-03 cluster `ready`.
- Subnets in ≥3 AZs (multi-AZ) or ≥2 for minimum HA.
- Quota for extra instance types.

## Steps

1. List pools:

   ```bash
   rosa list machinepools --cluster="${CLUSTER_NAME}"
   oc get machinepool -n openshift-machine-api
   ```

2. Add a pool (example 2× `m5.large` in one AZ):

   ```bash
   rosa create machinepool --cluster="${CLUSTER_NAME}" \
     --name="workload" \
     --replicas=2 \
     --instance-type="m5.large" \
     --subnet-id="subnet-aaa"
   ```

3. Wait for machines:

   ```bash
   watch -n 20 'oc get machines,machinesets -n openshift-machine-api'
   ```

4. (Optional) Enable autoscaling on default pool via Terraform or OCM API—mirror `multi-az.tfvars.example` `min_replicas` / `max_replicas`.

5. Schedule test workload with topology spread:

   ```bash
   oc create deployment spread-test --image=registry.redhat.io/ubi9/httpd-24 --replicas=6
   oc get pods -o wide -l app=spread-test
   ```

## Expected output

- New machines transition to `Running`; nodes join `Ready`.
- Pods distribute across zones when constraints allow.

## Success criteria

```bash
oc get machinepool workload -n openshift-machine-api -o json | jq -e '.status.readyReplicas >= 2'
ZONES=$(oc get nodes -o json | jq -r '[.items[].metadata.labels["topology.kubernetes.io/zone"]] | unique | length')
test "${ZONES}" -ge 2
```

## Failure signals

- Machines `Failed` → `oc describe machine <name>`, check subnet capacity and IAM.
- Pool stuck at 0 replicas → insufficient subnet IP space or invalid instance type in AZ.
- Cluster autoscaler not scaling → missing `ClusterAutoscaler` or max replicas = min.
