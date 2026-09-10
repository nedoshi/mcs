# GCP on-demand Windows licensing on OSD bare metal

Validation of Google's PAYGO Windows model on C3 metal workers: license tag on the RHCOS boot disk, stop-required attach, Private Google Access, opt-in vs cluster-wide tagging, and whether the tag can be removed.

**Date:** 2026-08-27  
**Cluster:** `xxxx-osd-xxxx` (OSD on GCP, CCS, WIF)  
**Project:** `xxxx-gcp-xxxx`  
**Region / zone:** `us-central1` / `us-central1-a`  
**OCP:** 4.21.x (`kubelet v1.34.2`)  
**OpenShift Virtualization:** 4.21.16 (installed; not required for the license-tag tests)

GCE instance names are the OSD infra ID prefix `xxxx-xxxx-*`, **not** the cluster display name.

---

## Environment under test

| Role | GCE instance | Machine type | IP |
|---|---|---|---|
| Metal worker (tagged) | `xxxx-xxxx-worker-a-xxxx` | `c3-standard-192-metal` | 10.x.x.2 |
| Metal worker (control / untagged) | `xxxx-xxxx-worker-a-yyyy` | `c3-standard-192-metal` | 10.x.x.3 |
| Infra | `xxxx-xxxx-infra-a-xxxx`, `xxxx-xxxx-infra-a-yyyy` | `n2-highmem-4` | 10.x.x.4/5 |
| Masters | `xxxx-xxxx-master-0/1/2` | `n2-standard-8` | 10.x.x.3–5 |

**Boot disk (before test), tagged node:**

```yaml
licenses:
- https://www.googleapis.com/compute/v1/projects/redhat-marketplace-public/global/licenses/cloud-marketplace-xxxx
```

RHCOS marketplace license only. Guest OS features include `UEFI_COMPATIBLE`, `GVNIC`, SEV-related flags. Status: `RUNNING`.

**Worker subnet:** `xxxx-osd-xxxx-worker-subnet`  
Terraform does **not** set `private_ip_google_access`. Cloud NAT `xxxx-osd-xxxx-nat-worker` was already present.

**OSD MachineHealthCheck:** `srep-worker-healthcheck` — 4 expected (2 infra + 2 metal), `maxUnhealthy: 3`. One NotReady worker **will** be remediated. `srep-metal-worker-healthcheck` had `EXPECTEDMACHINES: 0` (idle). Do not `oc delete machine` (SRE webhook). Beat MHC timeout (~5–8 min NotReady) if you stop a node and intend to keep it.

**License used:**

```
https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc
```

License code from API: `7142647615590922601`.

---

## Procedure

Filter `name~xxxx-osd-xxxx` returns nothing. List the project and match `c3-standard-192-metal`.

### 1. Inventory

```bash
gcloud compute instances list --project=xxxx-gcp-xxxx

NODE=xxxx-xxxx-worker-a-xxxx
gcloud compute instances describe $NODE \
  --zone=us-central1-a --project=xxxx-gcp-xxxx \
  --format='yaml(status,disks[].source,disks[].boot,disks[].licenses,disks[].guestOsFeatures)'
```

**Expected:** two C3 metal workers `RUNNING`; boot disk name equals instance name; licenses = RH marketplace only.

### 2. Append license while RUNNING (negative)

```bash
gcloud compute disks update xxxx-xxxx-worker-a-xxxx \
  --zone=us-central1-a \
  --project=xxxx-gcp-xxxx \
  --append-licenses=https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc
```

**Expected / actual:** HTTP 400

```
Licenses cannot be updated for a disk attached to a running instance.
The disk is attached to instance xxxx-xxxx-worker-a-xxxx which is RUNNING.
Please momentarily stop the instance or detach the disk before updating the licenses.
```

**Result:** PASS. Attach requires stop (or detach). No extra IAM beyond `compute.disks.update`.

### 3. Check MHC before stopping

```bash
oc get machinehealthcheck -A
oc get machine -n openshift-machine-api -o wide | grep xxxx
```

**Actual:**

```
srep-worker-healthcheck           3              4                  4
srep-metal-worker-healthcheck     3              0                  0
xxxx-xxxx-worker-a-xxxx   Running   c3-standard-192-metal   ...   RUNNING
```

Do **not** patch `srep-*`. Drain, stop, tag, start within the MHC NotReady window.

### 4. Day-2 attach (opt-in on one metal node)

This starts Windows PAYG for the **entire** 192-vCPU node.

```bash
oc adm cordon xxxx-xxxx-worker-a-xxxx
oc adm drain xxxx-xxxx-worker-a-xxxx \
  --ignore-daemonsets --delete-emptydir-data --force --grace-period=60

gcloud compute instances stop xxxx-xxxx-worker-a-xxxx \
  --zone=us-central1-a --project=xxxx-gcp-xxxx

gcloud compute disks update xxxx-xxxx-worker-a-xxxx \
  --zone=us-central1-a --project=xxxx-gcp-xxxx \
  --append-licenses=https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc

gcloud compute disks describe xxxx-xxxx-worker-a-xxxx \
  --zone=us-central1-a --project=xxxx-gcp-xxxx \
  --format='yaml(licenses)'

gcloud compute instances start xxxx-xxxx-worker-a-xxxx \
  --zone=us-central1-a --project=xxxx-gcp-xxxx
```

**Expected / actual licenses after append:**

```yaml
licenses:
- https://www.googleapis.com/compute/v1/projects/redhat-marketplace-public/global/licenses/cloud-marketplace-xxxx
- https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc
```

Instance came back on the **same** NIC: `10.x.x.2`.

**Result:** PASS. Tag is additive on the existing RHCOS boot disk. No new image required.

### 5. Uncordon, opt-in control, PGA

```bash
oc adm uncordon xxxx-xxxx-worker-a-xxxx
oc get node xxxx-xxxx-worker-a-xxxx
oc get machine xxxx-xxxx-worker-a-xxxx -n openshift-machine-api -o wide

gcloud compute disks describe xxxx-xxxx-worker-a-yyyy \
  --zone=us-central1-a --project=xxxx-gcp-xxxx --format='yaml(licenses)'

gcloud compute networks subnets describe xxxx-osd-xxxx-worker-subnet \
  --region=us-central1 --project=xxxx-gcp-xxxx \
  --format='value(privateIpGoogleAccess)'
```

**Node immediately after start:** `NotReady` (kubelet not up yet). Machine still `Running` / `RUNNING`, **same name**, original age — not replaced.

**`yyyy` licenses:** RH marketplace only. Opt-in holds.

**PGA:** `False` (Terraform default). Enable:

```bash
gcloud compute networks subnets update xxxx-osd-xxxx-worker-subnet \
  --region=us-central1 --project=xxxx-gcp-xxxx \
  --enable-private-ip-google-access
```

**Expected:** subnet update succeeds. SNAT was already provided by `nat-worker`.

Wait for kubelet:

```bash
oc get node xxxx-xxxx-worker-a-xxxx -w
```

**Actual:** `Ready` within ~2–3 minutes. Events show `Rebooted` with a new boot id. MHC `CURRENTHEALTHY: 4/4`.

Tag still present after reboot (disk-scoped, not instance-scoped).

### 6. Remove license while RUNNING

```bash
gcloud compute disks update xxxx-xxxx-worker-a-xxxx \
  --zone=us-central1-a --project=xxxx-gcp-xxxx \
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
oc adm cordon xxxx-xxxx-worker-a-xxxx
oc adm drain xxxx-xxxx-worker-a-xxxx \
  --ignore-daemonsets --delete-emptydir-data --force --grace-period=60

gcloud compute instances stop xxxx-xxxx-worker-a-xxxx \
  --zone=us-central1-a --project=xxxx-gcp-xxxx

gcloud compute disks update xxxx-xxxx-worker-a-xxxx \
  --zone=us-central1-a --project=xxxx-gcp-xxxx \
  --remove-licenses=https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc
```

**Actual:** same HTTP 400, sticky-license text. Instance was `TERMINATED`.

**Result:** FAIL vs the written model. `windows-server-2025-dc` cannot be stripped from that disk in any power state.

### 8. OSD cannot delete the Machine

```bash
oc delete machine xxxx-xxxx-worker-a-xxxx -n openshift-machine-api
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
