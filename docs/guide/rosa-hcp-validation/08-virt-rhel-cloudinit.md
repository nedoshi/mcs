# UC-07 — RHEL VMs via OpenShift Virtualization and cloud-init

**Provenance:** [ROSA Technical Solutions.pdf](../../ROSA%20Technical%20Solutions.pdf) — Scenario 7.

## Summary

Provision **KubeVirt VirtualMachine** workloads (two RHEL VMs) using Terraform `kubernetes_manifest`, with **cloud-init** `userData` to install nginx and serve HTML—no Ansible.

## Why this matters

- Lift-and-shift legacy RHEL apps beside containers on ROSA.
- Validates **HyperConverged Cluster Operator (HCO)**, golden images, and data volumes.
- Pairs with ING-05 for routable VM ingress over VPN.

## Architecture

```
 [Terraform kubernetes_manifest]
            |
            v
 [OpenShift Virtualization / KubeVirt]
            |
 [Bare metal MachinePool m5zn.metal]
            |
    +-------+-------+
    |               |
 [RHEL VM 1]     [RHEL VM 2]
 cloud-init nginx
```

## Prerequisites

- **Bare metal** workers with **IMDSv2** (`--ec2-metadata-http-tokens=required` on pool).
- OpenShift Virtualization installed and `KubeVirt`/`HCO` healthy.
- Namespace (e.g. `marketing-apps`) and RHEL golden image datasource (PDF uses `rhel10` in `openshift-virtualization-os-images`).

```bash
oc get csv -n openshift-cnv
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.node\\.kubernetes\\.io/instance-type}{"\n"}{end}' | grep metal
```

If metal or CNV missing → **BLOCKED**.

## Steps

1. Apply VM manifest pattern from PDF (`vms.tf` / `kubernetes_manifest` with `count = 2`), including:
   - `kubevirt.io/v1` VirtualMachine
   - Boot volume from golden image PVC
   - `cloudInitNoCloud.userData` bash: `dnf install nginx`, index.html

2. Wait for VMI running:

   ```bash
   oc get vm,vmi -n marketing-apps
   ```

3. Access console or service/route to VM (lab-specific); or `virtctl console` from workstation with virtctl installed.

4. Verify nginx inside guest (via console or guest IP if routed):

   - HTML contains `Hello from RHEL VM`

## Expected output

- VMs `Running` / VMI phase `Running`
- Nginx serving custom index after cloud-init completes

## Success criteria

```bash
oc get vmi -n marketing-apps -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}' | grep -q Running
```

Document guest-level nginx check in notes when network path exists.

## Failure signals

- VM pending → insufficient metal capacity, missing storage class `gp3-csi`.
- Cloud-init failed → `oc describe vmi`, cloud-init logs in guest.
- Wrong image name → adjust datasource to cluster’s RHEL image.

## References

- [ROSA_Network_Troubleshooting_Guide.md — Virtualization](../../network-troubleshooting/ROSA/ROSA_Network_Troubleshooting_Guide.md)
- PDF footnote: *Running Virtual Machine on ROSA HCP Tutorial*
