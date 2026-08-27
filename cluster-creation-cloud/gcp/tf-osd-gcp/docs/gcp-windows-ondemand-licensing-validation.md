# GCP on-demand Windows licensing on OSD bare metal

Validation of Google's PAYGO Windows model on C3 metal workers: license tag on the RHCOS boot disk, stop-required attach, Private Google Access, opt-in vs cluster-wide tagging, and whether the tag can be removed.

**Date:** 2026-08-27  
**Cluster:** `nd-osd-virt-demo` (OSD on GCP, CCS, WIF)  
**Project:** `it-cloud-gcp-mobb-amer`  
**Region / zone:** `us-central1` / `us-central1-a`  
**OCP:** 4.21.x (`kubelet v1.34.2`)  
**OpenShift Virtualization:** 4.21.16 (installed; not required for the license-tag tests)

GCE instance names are the OSD infra ID prefix `j6d4h2w8i5c5e9h-62cn4-*`, **not** the cluster display name.

---

## Environment under test

| Role | GCE instance | Machine type | IP |
|---|---|---|---|
| Metal worker (tagged) | `j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c` | `c3-standard-192-metal` | 10.0.32.2 |
| Metal worker (control / untagged) | `j6d4h2w8i5c5e9h-62cn4-worker-a-v2sm2` | `c3-standard-192-metal` | 10.0.32.3 |
| Infra | `…-infra-a-bb66s`, `…-infra-a-lvb9s` | `n2-highmem-4` | 10.0.32.4/5 |
| Masters | `…-master-0/1/2` | `n2-standard-8` | 10.0.0.3–5 |

**Boot disk (before test), tagged node:**

```yaml
licenses:
- https://www.googleapis.com/compute/v1/projects/redhat-marketplace-public/global/licenses/cloud-marketplace-109c18bd150550bf-df1ebeb69c0ba664
```

RHCOS marketplace license only. Guest OS features include `UEFI_COMPATIBLE`, `GVNIC`, SEV-related flags. Status: `RUNNING`.

**Worker subnet:** `nd-osd-virt-demo-worker-subnet`  
Terraform does **not** set `private_ip_google_access`. Cloud NAT `nd-osd-virt-demo-nat-worker` was already present.

**OSD MachineHealthCheck:** `srep-worker-healthcheck` — 4 expected (2 infra + 2 metal), `maxUnhealthy: 3`. One NotReady worker **will** be remediated. `srep-metal-worker-healthcheck` had `EXPECTEDMACHINES: 0` (idle). Do not `oc delete machine` (SRE webhook). Beat MHC timeout (~5–8 min NotReady) if you stop a node and intend to keep it.

**License used:**

```
https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc
```

License code from API: `7142647615590922601`.

---

## Procedure

Filter `name~nd-osd-virt-demo` returns nothing. List the project and match `c3-standard-192-metal`.

### 1. Inventory

```bash
gcloud compute instances list --project=it-cloud-gcp-mobb-amer

NODE=j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c
gcloud compute instances describe $NODE \
  --zone=us-central1-a --project=it-cloud-gcp-mobb-amer \
  --format='yaml(status,disks[].source,disks[].boot,disks[].licenses,disks[].guestOsFeatures)'
```

**Expected:** two C3 metal workers `RUNNING`; boot disk name equals instance name; licenses = RH marketplace only.

### 2. Append license while RUNNING (negative)

```bash
gcloud compute disks update j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c \
  --zone=us-central1-a \
  --project=it-cloud-gcp-mobb-amer \
  --append-licenses=https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc
```

**Expected / actual:** HTTP 400

```
Licenses cannot be updated for a disk attached to a running instance.
The disk is attached to instance j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c which is RUNNING.
Please momentarily stop the instance or detach the disk before updating the licenses.
```

**Result:** PASS. Attach requires stop (or detach). No extra IAM beyond `compute.disks.update`.

### 3. Check MHC before stopping

```bash
oc get machinehealthcheck -A
oc get machine -n openshift-machine-api -o wide | grep hkx9c
```

**Actual:**

```
srep-worker-healthcheck           3              4                  4
srep-metal-worker-healthcheck     3              0                  0
j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c   Running   c3-standard-192-metal   ...   RUNNING
```

Do **not** patch `srep-*`. Drain, stop, tag, start within the MHC NotReady window.

### 4. Day-2 attach (opt-in on one metal node)

This starts Windows PAYG for the **entire** 192-vCPU node.

```bash
oc adm cordon j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c
oc adm drain j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c \
  --ignore-daemonsets --delete-emptydir-data --force --grace-period=60

gcloud compute instances stop j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c \
  --zone=us-central1-a --project=it-cloud-gcp-mobb-amer

gcloud compute disks update j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c \
  --zone=us-central1-a --project=it-cloud-gcp-mobb-amer \
  --append-licenses=https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc

gcloud compute disks describe j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c \
  --zone=us-central1-a --project=it-cloud-gcp-mobb-amer \
  --format='yaml(licenses)'

gcloud compute instances start j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c \
  --zone=us-central1-a --project=it-cloud-gcp-mobb-amer
```

**Expected / actual licenses after append:**

```yaml
licenses:
- https://www.googleapis.com/compute/v1/projects/redhat-marketplace-public/global/licenses/cloud-marketplace-109c18bd150550bf-df1ebeb69c0ba664
- https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc
```

Instance came back on the **same** NIC: `10.0.32.2`.

**Result:** PASS. Tag is additive on the existing RHCOS boot disk. No new image required.

### 5. Uncordon, opt-in control, PGA

```bash
oc adm uncordon j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c
oc get node j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c
oc get machine j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c -n openshift-machine-api -o wide

gcloud compute disks describe j6d4h2w8i5c5e9h-62cn4-worker-a-v2sm2 \
  --zone=us-central1-a --project=it-cloud-gcp-mobb-amer --format='yaml(licenses)'

gcloud compute networks subnets describe nd-osd-virt-demo-worker-subnet \
  --region=us-central1 --project=it-cloud-gcp-mobb-amer \
  --format='value(privateIpGoogleAccess)'
```

**Node immediately after start:** `NotReady` (kubelet not up yet). Machine still `Running` / `RUNNING`, **same name**, original age — not replaced.

**`v2sm2` licenses:** RH marketplace only. Opt-in holds.

**PGA:** `False` (Terraform default). Enable:

```bash
gcloud compute networks subnets update nd-osd-virt-demo-worker-subnet \
  --region=us-central1 --project=it-cloud-gcp-mobb-amer \
  --enable-private-ip-google-access
```

**Expected:** subnet update succeeds. SNAT was already provided by `nat-worker`.

Wait for kubelet:

```bash
oc get node j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c -w
```

**Actual:** `Ready` within ~2–3 minutes. Events show `Rebooted` with a new boot id. MHC `CURRENTHEALTHY: 4/4`.

Tag still present after reboot (disk-scoped, not instance-scoped).

### 6. Remove license while RUNNING

```bash
gcloud compute disks update j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c \
  --zone=us-central1-a --project=it-cloud-gcp-mobb-amer \
  --remove-licenses=https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc
```

**Actual:** HTTP 400 — **not** the “instance is RUNNING” error:

```
License windows-server-2025-dc with license code 7142647615590922601 was not included
in the set of licenses provided, but it is not removable or replaceable.
It must continue to be included in the set of licenses provided.
```

### 7. Remove license while STOPPED

```bash
oc adm cordon j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c
oc adm drain j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c \
  --ignore-daemonsets --delete-emptydir-data --force --grace-period=60

gcloud compute instances stop j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c \
  --zone=us-central1-a --project=it-cloud-gcp-mobb-amer

gcloud compute disks update j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c \
  --zone=us-central1-a --project=it-cloud-gcp-mobb-amer \
  --remove-licenses=https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc
```

**Actual:** same HTTP 400, sticky-license text. Instance was `TERMINATED`.

**Result:** FAIL vs the written model. `windows-server-2025-dc` cannot be stripped from that disk in any power state.

### 8. OSD cannot delete the Machine

```bash
oc delete machine j6d4h2w8i5c5e9h-62cn4-worker-a-hkx9c -n openshift-machine-api
```

**Actual:**

```
Error from server (Forbidden): admission webhook "regular-user-validation.managed.openshift.io"
denied the request: Prevented from accessing Red Hat managed resources.
```

Customers cannot Machine-replace via `oc` to drop the license.

### Off-ramp (PAYG until the disk is destroyed)

| Path | Who | Notes |
|---|---|---|
| Start the VM again | Customer (`gcloud instances start`) | Keeps tagged disk; keep paying |
| Leave stopped; let `srep-worker-healthcheck` remediate | SRE | MHC can delete the Machine; new RHCOS disk, no Windows license |
| `gcloud compute instances delete` if `disks[].autoDelete=true` | Customer (CCS) | Destroys boot disk; Machine controller should create a new untagged worker. Confirm the **new** disk has only RH marketplace. Orphaned tagged disks still bill. |
| OCM scale machine pool | Customer | May delete the **untagged** metal worker. Do not use unless you can target the instance. |

Do not leave the instance stopped with no plan: either start it (keep tag) or delete/replace it (stop billing).

---

## Findings (for the report)

### What matches Google's model

1. **License lives on the RHCOS boot disk.** Append `windows-server-2025-dc` next to the existing Red Hat marketplace license. No new worker image.
2. **Attach is blocked while the instance is RUNNING** (HTTP 400, explicit message). Day-2 attach works after `instances stop`.
3. **No special IAM** beyond `compute.disks.update` (same project already used for Hyperdisk).
4. **Node-based, not VM-based.** One tag = PAYG for the whole GCE VM (`c3-standard-192-metal` = 192 vCPUs), independent of how many Windows guests run on it.
5. **Opt-in is mandatory.** Tagging one of two metal workers left `v2sm2` on RH-only. Default-tagging every metal node would bill HPC/DB/BYOL customers.
6. **Metering is disk-scoped.** Tag survives kubelet reboot / GCE start. Same instance name and IP (`10.0.32.2`).
7. **PGA was not on by default** in this Terraform VPC. It was `False` until explicitly enabled. Cloud NAT was already on the worker subnet (SNAT). Google's "reach License Manager / KMS via PGA" is a real gap if we don't set `private_ip_google_access` on worker subnets.

### What does not match the written model

1. **The tag is not removable.** `--remove-licenses` fails with *not removable or replaceable* both while RUNNING and while TERMINATED. "Customers could theoretically remove the license tag by stopping the node" is **false** for `windows-server-2025-dc`.
2. **PAYG is one-way for the life of that boot disk.** Off-ramp is destroy VM+disk (new Machine), not `disks update`.
3. **OSD customers cannot `oc delete machine`.** SRE webhook `regular-user-validation.managed.openshift.io`. Any product "replace the Machine to drop Windows" must go through OCM/SRE MHC or customer-side `gcloud instances delete` (CCS), not the kube Machine API as cluster-admin.
4. **Stopping a worker races MHC.** `srep-worker-healthcheck` will remediate one NotReady worker. Fast stop/tag/start (~few minutes) survived; a slow drain or a failed start loses the node (and if MHC recreates it, you get a new untagged disk — which is actually the only clean un-tag).
5. **Guardrail on tag *removal* is weak.** GCP will not let them remove it. Guardrails that matter: **detect add** (opt-in), **never tag masters/infra**, **don't default-tag metal pools**, **alert if a metal node is tagged without a customer flag**. Removal detection only fires if someone destroys/recreates the node (license disappears with the disk).
6. **Over-commit / live-migration lock** were not tested. CNV will not pin Windows VMs to the tagged node unless we add nodeSelector/affinity. That is product policy, not a GCP API control.

### Not tested

- Windows guest KMS activation (`slmgr /dlv`). `win*` DataSources exist but were **not** imported (only Linux golden-image snapshots). Needs a Windows image, pin to `hkx9c`.
- Live-migrate a licensed guest onto an untagged metal node.
- Cloud Billing SKU lag (hours). Engineering proof is the `licenses[]` array; commercial proof is the Windows Server SKU on this project.
- Separate Windows vs non-Windows machine pools (single compute pool here).
- `restricted.googleapis.com` / PSC path to KMS (this cluster is public API + NAT + PGA, not PSC).

### Product implications

- Opt-in UI/API must be explicit. Accidental append cannot be undone on that disk.
- Document: stop node → append → start; **cannot un-append**.
- OSD runbook for "turn off Windows PAYG": scale/replace via OCM or let MHC recreate; or CCS `instances delete` with `autoDelete` on the boot disk. Not `--remove-licenses`.
- Enable PGA on worker subnets in the installer/Terraform if Google requires License Manager over PGA.
- Do not apply the tag to every C3 metal pool. Split Windows vs non-Windows metal pools if both exist.
- If we ship automation, default **off**; confirm billing impact (full node, 192 vCPU class here).

### Cost note

`windows-server-2025-dc` on `c3-standard-192-metal` bills Windows for **192 vCPUs** until that boot disk is deleted, including while the VM is stopped (disk still exists). Confirm with Cloud Billing; do not assume stop pauses Windows PAYG.
