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

## When is the license required?

| Scenario | Tag `windows-server-*-dc` on metal boot disk? |
|----------|-----------------------------------------------|
| C3 metal pool + OpenShift Virtualization + **Linux** guests | **No** |
| Windows guests with BYOL / eval ISO only (guest EULA in pipeline) | **No** for this GCP host tag (licensing doc does not replace Microsoft guest licensing) |
| Windows guests under **Google PAYG** on that metal node | **Yes** — opt in per metal worker (or per licensed machine pool) |

OpenShift Virtualization does not need this tag to expose KVM or to import Windows boot sources. The tag is a **GCP billing/compliance** control for PAYG Windows on bare metal.

---

## Ways to tag the metal worker boot disk

### Provision-time (new machine pool)

**QE (Machine API, not day-2 gcloud):** [gcp-machine-api-disk-licenses-qe.md](gcp-machine-api-disk-licenses-qe.md) — tests [openshift/api#2980](https://github.com/openshift/api/pull/2980), [machine-api-provider-gcp#184](https://github.com/openshift/machine-api-provider-gcp/pull/184), [machine-api-operator#1553](https://github.com/openshift/machine-api-operator/pull/1553), [cluster-api-actuator-pkg#492](https://github.com/openshift/cluster-api-actuator-pkg/pull/492) with expected `gcloud` output.

When creating a **new** C3 metal machine pool for Windows on GCP PAYG, declare the license on the **boot disk** in `GCPMachineProviderSpec` so the disk is tagged at first provision (no stop/drain cycle). Use **`hyperdisk-balanced`** for the boot disk — `pd-standard` / `pd-ssd` cannot attach to C3 metal.

Example `providerSpec.value` fragment (adjust image, network, subnet, zone, and service account to your cluster):

```yaml
apiVersion: machine.openshift.io/v1beta1
kind: GCPMachineProviderSpec
machineType: c3-standard-192-metal
onHostMaintenance: Terminate
region: us-central1
zone: us-central1-a
projectID: xxxx-gcp-xxxx
disks:
  - autoDelete: true
    boot: true
    image: projects/rhcos-cloud/global/images/<rhcos-image>
    sizeGb: 200
    type: hyperdisk-balanced
    licenses:
      - projects/windows-cloud/global/licenses/windows-server-2025-dc
networkInterfaces:
  - network: xxxx-xxxx-network
    subnetwork: xxxx-osd-xxxx-worker-subnet
```

After the Machine comes up, confirm on GCE (instance name is the Machine name, not the cluster display name):

```bash
NODE=xxxx-xxxx-virt-worker-a-xxxx
gcloud compute instances describe "$NODE" \
  --zone=us-central1-a --project=xxxx-gcp-xxxx \
  --format='yaml(disks[].boot,disks[].licenses,disks[].type)'
```

**Expected:** boot disk `type: hyperdisk-balanced`; `licenses` includes RHCOS marketplace **and** `windows-server-2025-dc`. GCE may also attach `projects/vm-options/global/licenses/enable-vmx` on metal workers; that is for nested virtualization on the host, not Windows PAYG.

**Pool design:** Keep at least one **untagged** metal worker if you need Linux-only or non-PAYG workloads — PAYG is per node, not per guest VM.

### Day-2 attach (existing worker)

Use the procedure below (steps 1–8) on a worker that was already provisioned **without** the Windows license. Requires cordon, drain, **stop** the GCE instance, then `gcloud compute disks update --append-licenses=...`.

---

## Procedure (day-2 attach validation)

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

---

## End-to-end verification (host → network → guest)

Use this after day-2 attach (or provision-time tagging on a payload that supports `licenses`). Confirms PAYG at **three levels**: GCP boot-disk tag, Private Google Access / KMS reachability, and **KMS-level guest activation** (SNAT active + `slmgr` approval).

**E2e runbook (trial golden image → recreate guest → PAYG):** [osd-gcp-virtualization-e2e.md §6.1.2–6.1.3](osd-gcp-virtualization-e2e.md#612-recreate-windows-vm-for-payg-golden-image-still-valid)

### Env (reuse from e2e Step 0 or set now)

```bash
export GCP_PROJECT=<project-id>
export GCP_REGION=<region>          # e.g. us-central1
export GCP_ZONE=<zone>              # e.g. us-central1-a
export WORKER_SUBNET=<worker-subnet>  # e.g. ${CLUSTER_NAME}-worker-subnet
export NODE=<metal-worker-gce-name>   # usually matches Machine / node name
export WIN_PAYG_LICENSE_URL="https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc"
```

List metal nodes if needed:

```bash
gcloud compute instances list --project="$GCP_PROJECT" \
  --filter="machineType:c3-standard-192-metal OR machineType:c3-highcpu-192-metal"
```

### 1. Host / node boot disk tag (GCP)

```bash
gcloud compute instances describe "$NODE" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
  --format='yaml(disks[].boot,disks[].licenses,disks[].type)'
```

**Pass:**

- Boot disk `type` includes `hyperdisk-balanced` (metal)
- `licenses` includes RHCOS marketplace **and**  
  `https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc`  
  (or your chosen `windows-server-*-dc` URL)
- Metal may also show `projects/vm-options/global/licenses/enable-vmx` — nested virt on the host, **not** Windows PAYG

**Fail:** only RH marketplace license → tag not applied (re-run day-2 stop + append, or provision-time on a supported payload).

### 2. Network — Private Google Access and KMS reachability

#### 2a. Private Google Access on the worker subnet

```bash
gcloud compute networks subnets describe "$WORKER_SUBNET" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --format='value(privateIpGoogleAccess)'
```

**Pass:** `True`

If `False`:

```bash
gcloud compute networks subnets update "$WORKER_SUBNET" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --enable-private-ip-google-access
```

OSD often already has Cloud NAT (`*-nat-worker`) for SNAT; PGA is still required for private Google API paths used by activation.

#### 2b. KMS endpoint connectivity (from metal host)

Google’s Windows KMS host is **`kms.windows.googlecloud.com`** (TCP **1688**), IP **`35.190.247.13`**.  
Do **not** use `kms.windows.google.com` — that name does not exist (NXDOMAIN).

From a debug shell **on the tagged metal node** (ICMP `ping` is often blocked — use `nc` / `curl`):

```bash
oc debug node/"$NODE" -- chroot /host bash -c \
  'command -v nc >/dev/null && nc -zv -w 5 kms.windows.googlecloud.com 1688 || \
   curl -v --connect-timeout 5 telnet://kms.windows.googlecloud.com:1688'
# IP fallback if DNS odd:
# nc -zv -w 5 35.190.247.13 1688
```

**Pass:** connection succeeds / port open.  
**Fail:** timeout / refused → fix PGA, Cloud NAT / egress firewall, or DNS before guest activation. Prefer also testing from a **pod** (CoreDNS) — that is the path Windows guests use.

---

### 3. KMS-level verification (SNAT active + activation approval)

This is the pass/fail for **Google PAYG**: guest activation traffic must leave via the **tagged metal host** (SNAT), reach Google KMS, and Windows must report **approved / activated**.

#### 3a. Confirm SNAT is active

Guest VMs use KubeVirt **masquerade**. Outbound packets are SNAT’d to the metal node’s primary NIC, then egress via **Cloud NAT** (OSD: typically `*-nat-worker`) and/or Private Google Access.

**1 — Metal host primary NIC IP** (activation source identity GCP associates with the license tag):

```bash
HOST_IP=$(gcloud compute instances describe "$NODE" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
  --format='value(networkInterfaces[0].networkIP)')
echo "metal primary NIC: $HOST_IP"
```

**2 — Cloud NAT exists and is enabled for the worker network/router:**

```bash
# discover router(s) in the region (OSD often: <cluster>-nat-router or similar)
gcloud compute routers list --project="$GCP_PROJECT" --regions="$GCP_REGION" \
  --format='table(name,region,network)'

# set after list, e.g. NAT_ROUTER=<cluster>-cloud-router
export NAT_ROUTER=<nat-router-name>

gcloud compute routers nats list --router="$NAT_ROUTER" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --format='yaml(name,natIpAllocateOption,sourceSubnetworkIpRangesToNat,enableEndpointIndependentMapping)'
```

**Pass:** at least one NAT whose source ranges cover the **worker subnet** (or `ALL_SUBNETWORKS_ALL_IP_RANGES` / `LIST_OF_SUBNETWORKS` including `$WORKER_SUBNET`).

**3 — Guest interface is masquerade (required for node SNAT):**

```bash
oc get vmi "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" \
  -o jsonpath='{.spec.networks}{"\n"}{.spec.domain.devices.interfaces}{"\n"}'
```

**Pass:** interface `masquerade:` present (default virt networking). Bridge/SR-IOV without SNAT to the tagged host will **not** satisfy Google’s host-tagged PAYG path.

**4 — Guest is on the tagged metal node:**

```bash
oc get vmi "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" -o wide
# NODE column must equal $NODE
```

**5 — (Optional) prove guest egress hits the metal path before `slmgr`:**  
From an Admin PowerShell **inside the Windows guest**:

```powershell
Test-NetConnection kms.windows.googlecloud.com -Port 1688
```

**Pass:** `TcpTestSucceeded : True`.  
If this fails while §2b on the metal host succeeds → guest overlay / NetworkPolicy / DNS issue, not host PGA.

There is no separate OpenShift CR to “enable SNAT” for PAYG — masquerade + Cloud NAT (and PGA for Google paths) **is** SNAT active.

#### 3b. Confirm activation approval (`slmgr`)

1. Windows guest **Running** on tagged metal (e2e Phase 6 — `$WINDOWS_VM_NAME` / `$WINDOWS_PROJECT`).
2. Console as **Administrator** (Mac: Console tab **Paste** / **Send key**; or `virtctl vnc --proxy-only` + TigerVNC on the **printed** port — e2e Phase 6.4).
3. **Edition must match host PAYG tag.** Host `windows-server-2025-dc` → guest needs **Datacenter** (not Standard Eval Core). Prefer a Datacenter golden ISO up front.

```powershell
DISM /online /Get-CurrentEdition
DISM /online /Get-TargetEditions
```

- `ServerStandardEvalCor` → try `Set-Edition:ServerDatacenterCor` with DC GVLK `D764K-2NDRG-47T6Q-P8T8W-YP6DF`.  
  **DISM Error 1168** (failed applying edition settings / missing license EULA files) → **rebuild** from Windows Server 2025 **Datacenter** media. Do not use `ServerTurbineCor` (Azure).
- Bare `slmgr /ipk` on Eval often returns **`0xC004F069`** — convert with DISM first.
- Use `cscript //nologo C:\Windows\System32\slmgr.vbs …` so results stay in the console (GUI `slmgr` only pops dialogs).

4. Activate against Google KMS (`kms.windows.googlecloud.com` / `35.190.247.13:1688` — **not** `kms.windows.google.com`):

```powershell
cscript //nologo C:\Windows\System32\slmgr.vbs /skms 35.190.247.13:1688
cscript //nologo C:\Windows\System32\slmgr.vbs /ato
cscript //nologo C:\Windows\System32\slmgr.vbs /dli
```

**Pass (activation approval):** `/ato` succeeds; `/dli` → **License Status: Licensed** (not `TIMEBASED_EVAL` / Initial grace).

**Fail examples:**

| Symptom | Likely cause |
|---------|----------------|
| Cannot connect to KMS / `0xC004F074` / `0x80072EE2` | PGA, NAT, firewall, or DNS (§2 / §3a) |
| `0xC004F069` on `/ipk` | Still Evaluation — DISM `Set-Edition` required |
| DISM **Error 1168** on `Set-Edition` | Standard Eval Core media cannot transmogrify — rebuild Datacenter ISO |
| Activation fails; host **untagged** | Day-2 / provision-time license missing (§1) |
| Guest not on tagged metal | Reschedule / node selector — VMI must land on `$NODE` |
| Edition Standard vs host `*-dc` | Mismatch — Datacenter guest or Standard host license URL |

5. Confirm license **state** (approval persisted) — see `/dli` table below.

**Pass criteria to record:**

| Field (in `/dli` output) | Expect |
|--------------------------|--------|
| License Status | **Licensed** (not Notification / Unlicensed / Initial grace) |
| Description / channel | Volume / KMS client (Google PAYG path) — not `TIMEBASED_EVAL` |
| Partial Product Key / KMS info | Present after successful `/ato` |
| Remaining Windows rearm count | Informational only |

Also useful:

```powershell
cscript //nologo C:\Windows\System32\slmgr.vbs /xpr
```

**Pass:** shows the machine is permanently activated, or activated until a future date via KMS (not stuck in eval/grace with activation errors).

**Record for QE:** screenshot or copy of `/ato` success + `/dli` License Status = Licensed, plus `$NODE`, host license URL, `HOST_IP`, and `Get-CurrentEdition`.

### Verification checklist

| Level | Check | Pass criteria |
|-------|--------|----------------|
| Host | `gcloud … disks[].licenses` | Includes `windows-server-2025-dc` (+ RHCOS) |
| Network | `privateIpGoogleAccess` | `True` |
| Network | `kms.windows.googlecloud.com:1688` from metal | Reachable (§2b) |
| KMS / SNAT | Cloud NAT covers worker subnet | NAT listed on `$NAT_ROUTER` |
| KMS / SNAT | VMI `masquerade` + on `$NODE` | Guest SNAT to tagged metal |
| KMS / guest | `Test-NetConnection … -Port 1688` | `TcpTestSucceeded : True` |
| KMS / guest | `slmgr /ato` | **Product activated successfully** (KMS approval) |
| KMS / guest | `slmgr /dlv` | **License Status: Licensed** |

### Optional: automate host + subnet checks

```bash
# Requires: GCP_PROJECT GCP_ZONE GCP_REGION WORKER_SUBNET WIN_PAYG_LICENSE_URL
# Optional: NODE (single) — otherwise all c3-*-metal instances in the project

check_one() {
  local n="$1"
  echo "=== $n ==="
  local licenses
  licenses=$(gcloud compute instances describe "$n" \
    --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
    --format='value(disks[0].licenses)' 2>/dev/null) || { echo "FAIL describe"; return 1; }
  if echo "$licenses" | grep -qF "$WIN_PAYG_LICENSE_URL"; then
    echo "PASS host license"
  else
    echo "FAIL host license missing"
    echo "  got: $licenses"
  fi
}

pga=$(gcloud compute networks subnets describe "$WORKER_SUBNET" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --format='value(privateIpGoogleAccess)')
[[ "$pga" == "True" ]] && echo "PASS PGA=$pga" || echo "FAIL PGA=$pga (want True)"

if [[ -n "${NODE:-}" ]]; then
  check_one "$NODE"
else
  gcloud compute instances list --project="$GCP_PROJECT" \
    --filter="machineType:c3-standard-192-metal OR machineType:c3-highcpu-192-metal" \
    --format='value(name)' | while read -r n; do
      [[ -n "$n" ]] && check_one "$n"
    done
fi
# Guest slmgr /ato remains manual (console / RDP).
```

---

## Off-ramp (PAYG until the disk is destroyed)

| Path | Who | Notes |
|---|---|---|
| Start the VM again | Customer (`gcloud instances start`) | Keeps tagged disk; keep paying |
| Leave stopped; let `srep-worker-healthcheck` remediate | SRE | MHC can delete the Machine; new RHCOS disk, no Windows license |
| `gcloud compute instances delete` if `disks[].autoDelete=true` | Customer (CCS) | Destroys boot disk; Machine controller should create a new untagged worker. Confirm the **new** disk has only RH marketplace. Orphaned tagged disks still bill. |
| OCM scale machine pool | Customer | May delete the **untagged** metal worker. Do not use unless you can target the instance. |

Do not leave the instance stopped with no plan: either start it (keep tag) or delete/replace it (stop billing).

---
