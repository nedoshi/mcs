# QE: GCP boot disk licenses via Machine API (provision-time)

Checklist to validate **provision-time** licensing: `licenses` on the boot disk in `GCPMachineProviderSpec` are applied when the Machine API **creates** the GCE instance, **without** `gcloud compute disks update --append-licenses`.

Day-2 attach (stop + gcloud) is documented in [gcp-windows-ondemand-licensing-validation.md](gcp-windows-ondemand-licensing-validation.md). This doc is for **OCPSTRAT-3624** / Machine API QE only.

---

## What we are testing (GitHub PRs)

| PR | Repo | What it adds |
|----|------|----------------|
| [#2980](https://github.com/openshift/api/pull/2980) | openshift/api | `Licenses []string` on `GCPDisk` in the Machine API schema |
| [#184](https://github.com/openshift/machine-api-provider-gcp/pull/184) | machine-api-provider-gcp | Reconciler passes `disk.Licenses` → GCP `AttachedDiskInitializeParams.Licenses` at instance create |
| [#1553](https://github.com/openshift/machine-api-operator/pull/1553) | machine-api-operator | Admission webhook validates GCP disk license URLs (full URI or short self-link) |
| [#492](https://github.com/openshift/cluster-api-actuator-pkg/pull/492) | cluster-api-actuator-pkg | E2E that provisions a MachineSet with a license on the boot disk (uses `enable-vmx` in CI) |

**Pass criteria for un-holding those PRs:** On a cluster running a **payload/build that includes the stack above**, a new metal worker provisions successfully and `gcloud compute instances describe` shows the declared license(s) on the **boot disk** immediately — with **no** day-2 `--append-licenses` between create and verify.

**Known risk ([#184](https://github.com/openshift/machine-api-provider-gcp/pull/184)):** GCP docs may treat create-time `AttachedDiskInitializeParams.Licenses` as restricted; if Test A fails, the provider may need a `disks.insert` + attach workaround.

---

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| OpenShift **payload** (or nightly) containing [#2980](https://github.com/openshift/api/pull/2980) + [#184](https://github.com/openshift/machine-api-provider-gcp/pull/184) + [#1553](https://github.com/openshift/machine-api-operator/pull/1553) | Released OCP without these changes will not implement provision-time passthrough |
| GCP cluster (OSD CCS or self-managed) | Permission to create a **test** MachineSet (1 replica) |
| C3 **metal** machine type + **`hyperdisk-balanced`** boot disk | `pd-standard` / `pd-ssd` cannot attach to C3 metal |
| `oc`, `gcloud`, cluster admin | |
| Quota for one extra metal node in your zone | Test B enables Windows PAYG billing for the whole node |

### Step 0 — environment

```bash
export GCP_PROJECT="my-gcp-project"
export GCP_REGION="us-central1"
export GCP_ZONE="us-central1-a"
export MS_NAMESPACE="openshift-machine-api"
export TEST_MS_NAME="qe-gcp-disk-licenses"
```

License URLs (webhook accepts full URL or short form):

```bash
export LICENSE_ENABLE_VMX="projects/vm-options/global/licenses/enable-vmx"
export LICENSE_WIN_PAYG="projects/windows-cloud/global/licenses/windows-server-2025-dc"
export LICENSE_WIN_PAYG_URL="https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc"
```

---

## Test A — API smoke (recommended first)

**Goal:** Prove GCP accepts user-specified licenses at **instance create** via the Machine reconciler. Same intent as [cluster-api-actuator-pkg#492](https://github.com/openshift/cluster-api-actuator-pkg/pull/492); does **not** turn on Windows PAYG billing.

1. Export a template from an existing **working** worker `MachineSet` (metal or non-metal — use **metal** if Test B will follow on the same template):

   ```bash
   oc get machineset -n "$MS_NAMESPACE" -o name
   # pick a metal pool, e.g. machineset.machine.openshift.io/openshift-machine-api/<name>
   oc get machineset <source-ms> -n "$MS_NAMESPACE" -o yaml > /tmp/ms-source.yaml
   ```

2. Edit a copy: new `metadata.name` (`$TEST_MS_NAME`), unique `machine.openshift.io/cluster-api-machineset` label if present, **`spec.replicas: 1`**, boot disk `type: hyperdisk-balanced` (metal), add under the **boot** disk:

   ```yaml
   licenses:
     - projects/vm-options/global/licenses/enable-vmx
   ```

3. Apply and wait:

   ```bash
   oc apply -f /tmp/ms-qe.yaml
   oc get machine -n "$MS_NAMESPACE" -l machine.openshift.io/cluster-api-machineset="$TEST_MS_NAME" -w
   ```

   **Expected (OpenShift):**

   ```text
   NAME                          PHASE
   <infra-id>-<test-ms>-xxxxx    Running
   ```

   ```bash
   NODE=$(oc get machine -n "$MS_NAMESPACE" -l machine.openshift.io/cluster-api-machineset="$TEST_MS_NAME" -o jsonpath='{.items[0].status.nodeRef.name}')
   oc get node "$NODE"
   ```

   **Expected:**

   ```text
   NAME                          STATUS
   <same-as-machine-name>        Ready
   ```

4. Verify on GCE (**do not** run `gcloud compute disks update --append-licenses` before this):

   ```bash
   MACHINE=$(oc get machine -n "$MS_NAMESPACE" -l machine.openshift.io/cluster-api-machineset="$TEST_MS_NAME" -o jsonpath='{.items[0].metadata.name}')
   gcloud compute instances describe "$MACHINE" \
     --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
     --format='yaml(disks[].boot,disks[].type,disks[].licenses)'
   ```

   **Expected (pass):**

   ```yaml
   disks:
   - boot: true
     licenses:
     - https://www.googleapis.com/compute/v1/projects/rhcos-cloud/...   # RHCOS marketplace (exact URL varies)
     - https://www.googleapis.com/compute/v1/projects/vm-options/global/licenses/enable-vmx
     type: https://www.googleapis.com/compute/v1/projects/.../diskTypes/hyperdisk-balanced
   ```

   **Fail examples:**

   - `Machine` phase **Failed**; machine-api / GCP provider logs mention license or `AttachedDiskInitializeParams`
   - Instance **Running** but boot disk `licenses` has **no** `enable-vmx` (and you did not use gcloud append)

---

## Test B — Windows PAYG at provision-time

**Goal:** Prove [#184](https://github.com/openshift/machine-api-provider-gcp/pull/184) applies **`windows-server-2025-dc`** on the metal worker **boot disk** at create (product validation for OSD virt + PAYG).

Use a **dedicated** test MachineSet (`replicas: 1`). This starts **Google PAYG Windows** for the **entire** metal instance.

On the boot disk (with `type: hyperdisk-balanced`):

```yaml
licenses:
  - projects/windows-cloud/global/licenses/windows-server-2025-dc
```

Or use `"$LICENSE_WIN_PAYG_URL"`.

Repeat apply / wait / verify as in Test A.

**Expected (pass):**

```yaml
disks:
- boot: true
  licenses:
  - .../redhat-marketplace-public/.../cloud-marketplace-...
  - .../windows-cloud/global/licenses/windows-server-2025-dc
  type: .../hyperdisk-balanced
```

GCE may also add `projects/vm-options/global/licenses/enable-vmx` on metal; that is nested virt on the host, not Windows PAYG.

**Expected (OpenShift):** Same as Test A — `Machine` **Running**, node **Ready**.

**Fail:** Boot disk shows marketplace only, or Machine never reaches **Running**, without using day-2 gcloud.

---

## Negative check (webhook — [#1553](https://github.com/openshift/machine-api-operator/pull/1553))

Apply a MachineSet whose boot disk includes an invalid license string (bad project or path).

**Expected:** Admission webhook **rejects** create/update with a field error on `providerSpec.value.disks[n].licenses`.

---

## Cleanup

```bash
oc scale machineset "$TEST_MS_NAME" -n "$MS_NAMESPACE" --replicas=0
# or delete the MachineSet per cluster policy (OSD may restrict direct Machine delete)
```

Confirm the GCE VM is gone when `autoDelete: true`. If a boot disk with Windows PAYG remains, see off-ramp notes in [gcp-windows-ondemand-licensing-validation.md](gcp-windows-ondemand-licensing-validation.md) (sticky license).

---

## Report on the PRs (copy/paste template)

Post on [#2980](https://github.com/openshift/api/pull/2980) / [#184](https://github.com/openshift/machine-api-provider-gcp/pull/184) (or the `/hold` thread):

```text
Payload/build: <image or nightly id>
Cluster: <osd|ipi>, GCP project/zone: <project> / <zone>

Test A (enable-vmx, provision-time): PASS | FAIL
  Machine: Running, node Ready: yes | no
  gcloud boot disk licenses include enable-vmx without day-2 append: yes | no

Test B (windows-server-2025-dc, metal): PASS | FAIL | not run
  gcloud boot disk licenses include windows-server-2025-dc without day-2 append: yes | no

If FAIL, attach: machine-api-gcp operator log excerpt, Machine .status, GCP API error text.
```

**Example pass one-liner:**

> Payload `4.xx.x-xx`: Test A PASS — `enable-vmx` on boot disk via MachineSet only ([#184](https://github.com/openshift/machine-api-provider-gcp/pull/184)). Test B PASS — `windows-server-2025-dc` present on `c3-*-metal` boot disk after provision; no `gcloud append-licenses`.

---

## Related runbook

Optional Windows PAYG for virt testers (day-2 + YAML shape): [osd-gcp-virtualization-e2e.md](osd-gcp-virtualization-e2e.md) Phase 6.1.
