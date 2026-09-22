# OSD CCS findings: GCP Machine API provision-time disk licenses (Test A/B)

**Date:** 2026-09-18  
**Related docs:**
- [gcp-machine-api-disk-licenses-qe.md](gcp-machine-api-disk-licenses-qe.md) — intended Test A/B procedure
- [gcp-windows-ondemand-licensing-validation.md](gcp-windows-ondemand-licensing-validation.md) — day-2 attach

---

## Environment

| Item | Value |
|------|--------|
| Product | OSD CCS on GCP |
| Cluster | `nddemo` (infra ID `nddemo-zwqfn`) |
| GCP project / zone | `it-cloud-gcp-mobb-amer` / `us-central1-a` |
| Metal pool | Hive-managed `virt-worker` → MachineSet `nddemo-zwqfn-virt-worker-a` |
| Machine type | `c3-standard-192-metal` |
| Boot disk type | `hyperdisk-balanced` |
| Access | CCS / cluster-admin (not SRE backplane) |

---

## What we attempted

Per the QE doc and engineering’s CI providerSpec sample:

1. Exported Hive metal MachineSet → `/tmp/ms-source.yaml`
2. Built `/tmp/ms-qe.yaml`:
   - New name: `qe-gcp-disk-licenses`
   - Stripped `hive.openshift.io/*`, `uid`, `resourceVersion`, `status`, etc.
   - Updated `machine.openshift.io/cluster-api-machineset` on selector + template labels
   - `replicas: 1`
   - Boot disk `licenses:` (Test A: `enable-vmx`; Test B shape from eng: `windows-server-2025-dc`)
3. `oc apply -f /tmp/ms-qe.yaml`

Engineering sample (CI/IPI, for shape comparison only):

- Project: `openshift-gce-devel-ci-2`
- Machine type: `c3-highcpu-192-metal`
- License: `projects/windows-cloud/global/licenses/windows-server-2025-dc`
- Disk: `hyperdisk-balanced`

That shape is understood; OSD values (VPC, SA, image, zone) were adapted. Creating the MachineSet on OSD still failed.

---

## Results

### A. MachineSet create/update — BLOCKED (OSD managed admission)

```text
admission webhook "regular-user-validation.managed.openshift.io" denied the request:
Prevented from accessing Red Hat managed resources.
```

Observed for:

- Patching the **existing** Hive MachineSet (`nddemo-zwqfn-virt-worker-a`, `hive.openshift.io/managed: true`)
- **Creating** a new MachineSet (`qe-gcp-disk-licenses`) with Hive ownership removed

**Conclusion:** On OSD CCS, MachineSets in `openshift-machine-api` are not writable by CCS users for this QE. Pools are OCM/Hive-owned. The CI/IPI path (`oc apply` MachineSet) is not reproducible here with CCS credentials.

### B. `licenses` field — not present on this payload

When applying providerSpec with `disks[].licenses`:

```text
Warning: providerSpec.value: Unsupported value: "licenses": Unknown field (licenses) will be ignored
```

**Conclusion:** This cluster’s `GCPMachineProviderSpec` OpenAPI does **not** include [openshift/api#2980](https://github.com/openshift/api/pull/2980) (or equivalent). Even if MachineSet create were allowed, the field would be dropped and provision-time passthrough ([machine-api-provider-gcp#184](https://github.com/openshift/machine-api-provider-gcp/pull/184)) cannot be validated.

### C. Day-2 Windows PAYG — viable on OSD

Per [gcp-windows-ondemand-licensing-validation.md](gcp-windows-ondemand-licensing-validation.md):

- Append while instance **RUNNING** → expected failure (disk attached to running VM)
- Cordon/drain → **stop** → `gcloud compute disks update --append-licenses=.../windows-server-2025-dc` → start → uncordon → works
- Remove license → sticky (not removable) — consistent with prior validation

This validates **GCP PAYG tagging on the metal boot disk**, not Machine API provision-time.

---

## Mapping to QE tests

| Test | Intent | Executable on this OSD CCS? |
|------|--------|------------------------------|
| **Test A** | Provision-time `enable-vmx` via MachineSet | **No** — admission + unknown `licenses` |
| **Test B** | Provision-time `windows-server-2025-dc` via MachineSet | **No** — same |
| **Day-2** | Append `windows-server-2025-dc` after stop | **Yes** |

Engineering’s sample spec matches **Test B shape** and is appropriate for **CI/IPI** (writable MachineSets + API with `licenses`). It does not unblock OSD CCS.

---

## Asks for engineering

1. Confirm intended QE venue for #2980 / #184 / #1553:
   - CI/IPI / self-managed GCP, and/or
   - SRE/backplane on OSD with a payload that includes the licenses API
2. Do **not** gate OSD product readiness on “CCS admin can `oc apply` MachineSet with `licenses`” — blocked by managed admission today.
3. For OSD virt + Windows PAYG: treat **day-2** (and later OCM/Hive exposure of licenses, if planned) as the supported path until provision-time is wired through the managed control plane.

---

## Status summary

| Item | Status |
|------|--------|
| Provision-time Machine API QE (Test A/B) on this OSD | **BLOCKED** — cannot create MachineSets; `licenses` unknown on payload |
| Day-2 PAYG attach | **AVAILABLE** — continue validation / attach gcloud license evidence |
| Next | Day-2 verify complete + evidence, unless elevated access + build with known `licenses` field is provided |

---

## Artifacts (local)

- `/tmp/ms-source.yaml` — export of Hive metal MachineSet
- `/tmp/ms-qe.yaml` — cleaned new MachineSet attempt (`qe-gcp-disk-licenses`)

Attach on request: full webhook error, `oc get clusterversion`, MAO / machine-api-provider-gcp image digests.
