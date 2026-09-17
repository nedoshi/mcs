# OSD on GCP: End-to-End Linux and Windows VM Provisioning

Guide for provisioning Linux and Windows virtual machines on an **existing** OpenShift Dedicated (OSD) cluster on GCP using OpenShift Virtualization.

**Start here:** complete **[Step 0 — Set environment variables](#step-0--set-environment-variables)**, then run each phase in order (copy-paste commands).

**Audience:** Cluster already installed (CCS, WIF or service account). Default workers are **N2** (e.g. `n2-standard-4`). You want Linux + Windows guests.

This runbook is **self-contained** — no git repository or companion files. In **Step 0**, replace every placeholder (e.g. `my-cluster`, not `<cluster-name>`) before pasting commands.

---

## Step 0 — Set environment variables

Edit the **Required** values once, then `source` this block (or paste into your shell). Later sections assume these exports — copy-paste commands as written.

```bash
# === Required: your cluster / GCP (use real values — no angle brackets) ===
export CLUSTER_NAME=my-cluster
export GCP_PROJECT=my-gcp-project-id
export GCP_REGION=us-central1              # e.g. us-central1
export GCP_ZONE=us-central1-a              # same zone as metal worker
export WORKER_SUBNET="${CLUSTER_NAME}-worker-subnet"

# === Metal pool + test VM names (defaults work for this guide) ===
export METAL_POOL_ID=worker-virt
export LINUX_PROJECT=linux-vms
export LINUX_DV_NAME=linux-demo-disk
export LINUX_VM_NAME=linux-demo
export WINDOWS_PROJECT=windows-vms
export WINDOWS_VM_NAME=win-demo

# === Boot sources (Tekton / cluster defaults — change only if you alter pipeline params) ===
export WIN_BOOTSOURCE_DV=win2k22
export WIN_BOOTSOURCE_NAMESPACE=openshift-virtualization-os-images
export LINUX_DATASOURCE=centos-stream9

# Where the Windows DataSource is Ready after Phase 4 (hub pipeline often uses default)
export WIN_DS_NAMESPACE=default
# If 4.2.7 shows Ready only in openshift-virtualization-os-images, use instead:
# export WIN_DS_NAMESPACE=openshift-virtualization-os-images

# === Storage + SSH paths ===
export HYPERDISK_SC=hyperdisk-virt-sc
export VIRT_POOL_NAME="${CLUSTER_NAME}-virt-pool"
export STORAGE_POOL_PATH="projects/${GCP_PROJECT}/zones/${GCP_ZONE}/storagePools/${VIRT_POOL_NAME}"
export SSH_KEY="${SSH_KEY:-/tmp/virt-linux}"

# Phase 4.2.3: paste Eval Center ISO URL before starting the Windows pipeline
export WIN_IMAGE_DOWNLOAD_URL=''

# === After oc login (refresh if cluster version changes) ===
oc login https://api.my-cluster.example:6443 --token=sha256~...
gcloud config set project "$GCP_PROJECT"

export PIPELINE_VERSION="v$(oc get clusterversion version -o jsonpath='{.status.desired.version}' | cut -d. -f1-2).0"
export CLUSTER_ID="$(ocm list clusters --no-headers --columns id,name \
  | awk -v n="$CLUSTER_NAME" '$2==n {print $1}')"
```

**Expected output:**

```text
# oc whoami
system:admin

# gcloud config set project ...
Updated property [core/project].

# test -n "$CLUSTER_ID" && echo "CLUSTER_ID=$CLUSTER_ID"
CLUSTER_ID=<openshift-cluster-id>
```

> **Convention:** **Expected output** blocks use placeholders (`<metal-worker-node-name>`, `<linux-vm-name>`, …). Commands use `$LINUX_VM_NAME`, `$WIN_BOOTSOURCE_DV`, etc. from Step 0. Run **`oc get` with one resource type per command** (e.g. `oc get vm` then `oc get dv` — not `oc get vm,dv`).

---

## Architecture overview

```
┌─────────────────────────────────────────────────────────────────┐
│  OSD cluster (your GCP project)                                 │
│                                                                 │
│  Masters / Infra (N2)          Workers (N2) — NO KVM            │
│  ┌──────────────┐              ┌──────────────┐                 │
│  │ n2-standard-8│              │ n2-standard-4│  ← cannot run   │
│  │ n2-highmem-4 │              │ (×2 default) │    guest VMs    │
│  └──────────────┘              └──────────────┘                 │
│                                                                 │
│  Workers (C3 metal) — REQUIRED for VMs                          │
│  ┌──────────────────────────────────────────┐                   │
│  │ c3-standard-192-metal (KVM, 192 vCPU)    │  ← KubeVirt pods  │
│  └──────────────────────────────────────────┘                   │
│                                                                 │
│  VM disk storage (guest PVCs on metal nodes)                    │
│  • hyperdisk-virt-sc — REQUIRED on C3 metal (Hyperdisk only)    │
│  • standard-csi / ssd-csi — pd-standard/pd-ssd; CANNOT attach   │
│    to c3-standard-192-metal                                     │
└─────────────────────────────────────────────────────────────────┘
```

| Component | N2 workers | C3 metal workers |
|-----------|------------|------------------|
| Run OpenShift workloads | Yes | Yes (expensive) |
| `devices.kubevirt.io/kvm` | `0` | `1k` |
| Run KubeVirt guest VMs | **No** | **Yes** |
| Attach `standard-csi` / `ssd-csi` disks | Yes | **No** |
| Attach `hyperdisk-virt-sc` disks | No | **Yes** (pool same zone) |

**Bottom line:** You need (1) a **`c3-standard-192-metal`** machine pool and (2) a **Hyperdisk Balanced storage pool** + **`hyperdisk-virt-sc`** StorageClass in the **same zone** before any guest VM can run.

---

## Critical: C3 metal requires Hyperdisk for VM disks

GCP bare metal (`c3-standard-192-metal`) accepts **only Hyperdisk** volumes for attached disks — not `pd-standard` (`standard-csi`) or `pd-ssd` (`ssd-csi`). Create the Hyperdisk pool and **`hyperdisk-virt-sc`** StorageClass in Phase 3 before guest VM disks.

---

## Prerequisites checklist

Complete **Step 0** before Phase 1. Confirm tools and GCP quota:

**Expected output:**

```text
# oc whoami
system:admin

# gcloud config set project ...
Updated property [core/project].
```

> **Convention:** Blocks labeled **Expected output** show representative success output. Cluster names, node names, and ages will differ on your cluster.

### Tools

| Tool | Purpose |
|------|---------|
| `oc` | Cluster admin |
| `virtctl` | SSH / VNC — Console → Virtualization → virtctl |
| `gcloud` | Hyperdisk pool, Windows license |
| `ocm` | Add machine pool |
| `python3` + PyYAML | Phase 6.3 Windows VM CLI (`pip install pyyaml`) |

### GCP

- [ ] `c3-standard-192-metal` available in `GCP_ZONE`
- [ ] Quota for 1+ metal instance + Hyperdisk pool (**min 10 TiB**)
- [ ] `compute.googleapis.com` enabled

---

## Phase 1 — Add a C3 metal machine pool

N2-only clusters cannot run VMs.

### OCM CLI

```bash
ocm create machinepool --cluster "$CLUSTER_ID" \
  --id "$METAL_POOL_ID" \
  --replicas 1 \
  --instance-type c3-standard-192-metal \
  --multi-availability-zone=false
```

**Expected output:**

```text
# export CLUSTER_ID=...
# (no output if single match)

# ocm create machinepool ...
{
<<<<<<< Updated upstream
  "id": "worker-virt",
=======
  "id": "<metal-pool-id>",
>>>>>>> Stashed changes
  "instance_type": "c3-standard-192-metal",
  "replicas": 1,
  ...
}
```

### Red Hat console

Cluster → **Machine pools** → **Add machine pool** → `c3-standard-192-metal`, 1 replica, zone matching `$GCP_ZONE`.

### Verify (10–20 min)

```bash
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.devices\.kubevirt\.io/kvm}{"\n"}{end}' | grep 1k

gcloud compute instances list --project="$GCP_PROJECT" \
  --filter="machineType:c3-standard-192-metal"
```

**Expected output:**

```text
# oc get nodes ... | grep 1k
<<<<<<< Updated upstream
nddemo-wq4kd-virt-worker-a-6277p    1k

# gcloud compute instances list ...
NAME                                        ZONE           MACHINE_TYPE              STATUS
nddemo-wq4kd-virt-worker-a-6277p            us-central1-a  c3-standard-192-metal     RUNNING
=======
<metal-worker-node-name>    1k

# gcloud compute instances list ...
NAME                                        ZONE           MACHINE_TYPE              STATUS
<metal-worker-node-name>            ${GCP_ZONE}  c3-standard-192-metal     RUNNING
>>>>>>> Stashed changes
```

**Pass:** At least one node with KVM `1k`; metal instance `RUNNING` in `GCP_ZONE`.

---

## Phase 2 — Install OpenShift Virtualization

Follow Red Hat’s procedure for your cluster version (console or CLI):

- [OSD 4 — Installing Virtualization](https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/virtualization/installing)
- [OCP 4.21 — Installing Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/virtualization/installing) (replace **4.21** with your minor if different)

**CLI (same objects as the official doc):** subscribe in `openshift-cnv`, wait for the operator CSV **Succeeded**, then create `HyperConverged`:

```bash
oc apply -f - <<'OPERATOR_EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cnv
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubevirt-hyperconverged-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
    - openshift-cnv
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: hco-operatorhub
  namespace: openshift-cnv
spec:
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  name: kubevirt-hyperconverged
  channel: "stable"
  installPlanApproval: Automatic
OPERATOR_EOF

oc get csv -n openshift-cnv -w   # wait until hyperconverged CSV PHASE=Succeeded, then Ctrl+C

oc apply -f - <<'HCO_EOF'
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec: {}
HCO_EOF
```

Wait until HCO reports **Available** (see Verify below). For extra waits, StorageProfile patches, or 4.21 VolumeSnapshotClass setup, use the Red Hat installing guide linked under [Official references](#official-references-phases-2-and-3).

**Expected output (abbreviated):**

```text
Installing OpenShift Virtualization...
hyperconvergedcluster.kubevirt.io/kubevirt-hyperconverged created
...
OpenShift Virtualization installation complete.
```

**Expected output (abbreviated):**

```text
Installing OpenShift Virtualization...
hyperconvergedcluster.kubevirt.io/kubevirt-hyperconverged created
...
OpenShift Virtualization installation complete.
```

Verify:

```bash
oc get hco -n openshift-cnv kubevirt-hyperconverged \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}{"\n"}'
```

**Expected output:**

```text
True
```

```bash
oc get csv -n openshift-cnv | grep -E 'NAME|hyperconverged'
```

```text
NAME                                        DISPLAY                           VERSION   REPLACES   PHASE
<<<<<<< Updated upstream
kubevirt-hyperconverged-operator.v4.21.17    OpenShift Virtualization          4.21.17              Succeeded
=======
<virt-operator-csv-name>    OpenShift Virtualization          <virt-version>              Succeeded
>>>>>>> Stashed changes
```

**Pass:** HCO `Available=True`; virt operator CSV `Succeeded`.

---

## Phase 3 — Hyperdisk storage (required for VM disks on metal)

Do this **before** creating any guest VM (Phase 5 and Phase 4 Windows pipeline).

### 3.1 Create Hyperdisk Balanced storage pool in GCP

Pool must be in the **same zone** as the metal worker (`GCP_ZONE`). GCP minimum capacity is **10 TiB (10240 GiB)**.

```bash
gcloud compute storage-pools create "$VIRT_POOL_NAME" \
  --zone="$GCP_ZONE" \
  --project="$GCP_PROJECT" \
  --storage-pool-type=hyperdisk-balanced \
  --provisioned-capacity=10TB \
  --provisioned-iops=10000 \
  --provisioned-throughput=1024 \
  --capacity-provisioning-type=advanced \
  --performance-provisioning-type=advanced
```

**Expected output:**

```text
<<<<<<< Updated upstream
Created [https://www.googleapis.com/compute/v1/projects/it-cloud-gcp-mobb-amer/zones/us-central1-a/storagePools/nddemo-virt-pool].
=======
Created [https://www.googleapis.com/compute/v1/projects/${GCP_PROJECT}/zones/${GCP_ZONE}/storagePools/${CLUSTER_NAME}-virt-pool].
>>>>>>> Stashed changes
```

> **Note:** `gcloud` uses `--provisioned-capacity` (e.g. `10TB`), not `--pool-provisioned-capacity-gb`. Terraform uses `pool_provisioned_capacity_gb = 10240` for the same 10 TiB minimum.

Verify:

```bash
<<<<<<< Updated upstream
gcloud compute storage-pools describe ${CLUSTER_NAME}-virt-pool \
=======
gcloud compute storage-pools describe "$VIRT_POOL_NAME" \
>>>>>>> Stashed changes
  --zone="$GCP_ZONE" \
  --project="$GCP_PROJECT" \
  --format='yaml(name,zone,state,poolProvisionedCapacityGb,poolProvisionedIops,poolProvisionedThroughput)'
```

**Expected output:**

```text
<<<<<<< Updated upstream
name: nddemo-virt-pool
=======
name: ${CLUSTER_NAME}-virt-pool
>>>>>>> Stashed changes
poolProvisionedCapacityGb: '10240'
poolProvisionedIops: '10000'
poolProvisionedThroughput: '1024'
state: READY
<<<<<<< Updated upstream
zone: https://www.googleapis.com/compute/v1/projects/it-cloud-gcp-mobb-amer/zones/us-central1-a
=======
zone: https://www.googleapis.com/compute/v1/projects/${GCP_PROJECT}/zones/${GCP_ZONE}
>>>>>>> Stashed changes
```

**Pass:** `state: READY`; capacity ≥ 10240 GiB; zone matches `GCP_ZONE`.

**Cost note:** You provision 10 TiB of pool capacity even if VMs use less. Tune IOPS/throughput only if needed.

### 3.2 Create OpenShift StorageClass `hyperdisk-virt-sc`

Uses `$STORAGE_POOL_PATH` and `$HYPERDISK_SC` from Step 0. Procedure aligns with [Storage configuration for OpenShift Virtualization on Google Cloud (KCS 7139046)](https://access.redhat.com/articles/7139046) and [OCP Storage — hyperdisk-balanced disks](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/storage/persistent-storage-csi-gcp-pd).

**Do not** set fixed `provisioned-iops-on-create` on the StorageClass (breaks small pipeline / EFI PVCs).

```bash
oc apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${HYPERDISK_SC}
  annotations:
    description: "Hyperdisk Balanced for OpenShift Virtualization VM disk images"
    storageclass.kubernetes.io/is-default-class: "true"
    storageclass.kubevirt.io/is-default-virt-class: "true"
provisioner: pd.csi.storage.gke.io
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: hyperdisk-balanced
  storage-pools: ${STORAGE_POOL_PATH}
EOF

oc annotate storageclass standard-csi storageclass.kubernetes.io/is-default-class- --overwrite 2>/dev/null || true
oc get storageclass "${HYPERDISK_SC}"
```

**Expected output:**

```text
Creating StorageClass hyperdisk-virt-sc for OpenShift Virtualization VM disks...
Storage pool: projects/.../storagePools/${CLUSTER_NAME}-virt-pool
storageclass.storage.k8s.io/hyperdisk-virt-sc created
Removed default annotation from standard-csi.

StorageClass hyperdisk-virt-sc created and set as default.
```

**Expected output:**

```text
Creating StorageClass hyperdisk-virt-sc for OpenShift Virtualization VM disks...
Storage pool: projects/.../storagePools/nddemo-virt-pool
storageclass.storage.k8s.io/hyperdisk-virt-sc created
Removed default annotation from standard-csi.

StorageClass hyperdisk-virt-sc created and set as default.
```

Verify:

```bash
<<<<<<< Updated upstream
oc get storageclass hyperdisk-virt-sc
oc get storageclass hyperdisk-virt-sc -o jsonpath='{.provisioner}{"\n"}{.parameters.type}{"\n"}{.parameters.storage-pools}{"\n"}'
=======
oc get storageclass "$HYPERDISK_SC"
oc get storageclass "$HYPERDISK_SC" -o jsonpath='{.provisioner}{"\n"}{.parameters.type}{"\n"}{.parameters.storage-pools}{"\n"}'
>>>>>>> Stashed changes
```

**Expected output:**

```text
<<<<<<< Updated upstream
# oc get storageclass hyperdisk-virt-sc
=======
# oc get storageclass "$HYPERDISK_SC"
>>>>>>> Stashed changes
NAME                PROVISIONER            RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
hyperdisk-virt-sc   pd.csi.storage.gke.io  Delete          WaitForFirstConsumer   true

# jsonpath
pd.csi.storage.gke.io
hyperdisk-balanced
<<<<<<< Updated upstream
projects/it-cloud-gcp-mobb-amer/zones/us-central1-a/storagePools/nddemo-virt-pool
=======
projects/${GCP_PROJECT}/zones/${GCP_ZONE}/storagePools/${CLUSTER_NAME}-virt-pool
>>>>>>> Stashed changes
```

**Pass:** Provisioner `pd.csi.storage.gke.io`; **no** `provisioned-iops-on-create` in parameters (IOPS must be size-driven).

<<<<<<< Updated upstream
Patch StorageProfile (install script may do this; confirm):
=======
Patch StorageProfile (confirm after create; see [OSD Virtualization — storage profiles](https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/virtualization/storage)):
>>>>>>> Stashed changes

```bash
oc patch storageprofile "${HYPERDISK_SC}" --type=merge -p \
  '{"spec":{"claimPropertySets":[{"accessModes":["ReadWriteOnce"],"volumeMode":"Filesystem"}]}}'
```

**Expected output:**
<<<<<<< Updated upstream

```text
storageprofile.cdi.kubevirt.io/hyperdisk-virt-sc patched
```

**Do not set fixed IOPS on the StorageClass.** Hyperdisk IOPS limits depend on volume size (4 Gi → max **2000** IOPS; 6 Gi+ → min **3000**). Fixed `provisioned-iops-on-create` breaks:

- **~9 GiB** pipeline ISO PVCs (`modify-windows-iso-file` stuck **Pending**)
- **4 GiB** KubeVirt EFI `persistent-state-*` PVCs (installer VM `windows-efi-*` stuck **Starting**)

The install script omits IOPS/throughput params so the GCE CSI driver uses size-appropriate defaults. StorageClass `parameters` are **immutable** — recreate to fix a bad SC:

```bash
oc annotate storageclass hyperdisk-virt-sc storageclass.kubernetes.io/is-default-class- --overwrite
oc delete storageclass hyperdisk-virt-sc
./scripts/install-hyperdisk-storageclass.sh
```

**Expected output:**

```text
storageclass.storage.k8s.io/hyperdisk-virt-sc annotated
storageclass.storage.k8s.io "hyperdisk-virt-sc" deleted
storageclass.storage.k8s.io/hyperdisk-virt-sc created
```

**Sanity test (9 Gi):** `hyperdisk-virt-sc` uses `WaitForFirstConsumer` — a bare PVC stays **Pending** until a pod mounts it. That is normal, not an IOPS failure:

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hyperdisk-iops-test
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: hyperdisk-virt-sc
  resources:
    requests:
      storage: 9Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: hyperdisk-iops-test-pod
  namespace: default
spec:
  restartPolicy: Never
  containers:
    - name: test
      image: registry.redhat.io/ubi9/ubi-minimal:latest
      command: ["sh", "-c", "sleep 10"]
      volumeMounts:
        - name: disk
          mountPath: /data
  volumes:
    - name: disk
      persistentVolumeClaim:
        claimName: hyperdisk-iops-test
EOF
oc get pvc hyperdisk-iops-test -n default -w   # Bound once pod schedules
oc delete pod hyperdisk-iops-test-pod pvc hyperdisk-iops-test -n default
```

**Expected output:**

```text
# Immediately after apply (no pod yet) — NORMAL, not a failure:
NAME                  STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
hyperdisk-iops-test   Pending                                      hyperdisk-virt-sc

# After pod schedules (~10–30s):
hyperdisk-iops-test   Bound     pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   9Gi   RWO   hyperdisk-virt-sc

# oc delete ...
pod "hyperdisk-iops-test-pod" deleted
persistentvolumeclaim "hyperdisk-iops-test" deleted
```

**Pass:** PVC reaches `Bound` only after the test pod exists; `ProvisioningSucceeded` in `oc describe pvc` events.

### 3.3 Terraform alternative (new clusters)
=======
>>>>>>> Stashed changes

```text
storageprofile.cdi.kubevirt.io/hyperdisk-virt-sc patched
```

**Note:** Do not add fixed `provisioned-iops-on-create` to the StorageClass parameters.

**Sanity test (9 Gi):** `hyperdisk-virt-sc` uses `WaitForFirstConsumer` — a bare PVC stays **Pending** until a pod mounts it. That is normal, not an IOPS failure:

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hyperdisk-iops-test
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: hyperdisk-virt-sc
  resources:
    requests:
      storage: 9Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: hyperdisk-iops-test-pod
  namespace: default
spec:
  restartPolicy: Never
  containers:
    - name: test
      image: registry.redhat.io/ubi9/ubi-minimal:latest
      command: ["sh", "-c", "sleep 10"]
      volumeMounts:
        - name: disk
          mountPath: /data
  volumes:
    - name: disk
      persistentVolumeClaim:
        claimName: hyperdisk-iops-test
EOF
oc get pvc hyperdisk-iops-test -n default -w   # Bound once pod schedules
oc delete pod hyperdisk-iops-test-pod pvc hyperdisk-iops-test -n default
```

**Expected output:**

```text
# Immediately after apply (no pod yet) — NORMAL, not a failure:
NAME                  STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
<hyperdisk-test-pvc>   Pending                                      hyperdisk-virt-sc

# After pod schedules (~10–30s):
<hyperdisk-test-pvc>   Bound     pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   9Gi   RWO   hyperdisk-virt-sc

# oc delete ...
pod "<hyperdisk-test-pod>" deleted
persistentvolumeclaim "<hyperdisk-test-pvc>" deleted
```

**Pass:** PVC reaches `Bound` only after the test pod exists; `ProvisioningSucceeded` in `oc describe pvc` events.


### Storage quick reference

| StorageClass | GCE disk type | Works on N2? | Works on C3 metal for **guest VM** disks? |
|--------------|---------------|--------------|----------------------------------------|
| `standard-csi` | pd-standard | Yes (OSD pods) | **No** |
| `ssd-csi` | pd-ssd | Yes (OSD pods) | **No** |
| `hyperdisk-virt-sc` | hyperdisk-balanced | No | **Yes** |

---

## Phase 4 — Golden images (boot sources)

### Linux — auto-imported (for DataSource reference only)

```bash
oc get datasource centos-stream9 -n openshift-virtualization-os-images \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
```

**Expected output:**

```text
True
```

**Do not** clone from this DataSource via snapshot onto metal without Hyperdisk — use the registry import in Phase 5 instead.

### Windows — NOT auto-imported

```bash
<<<<<<< Updated upstream
oc get datasource win2k22 -n openshift-virtualization-os-images \
=======
oc get datasource "$WIN_BOOTSOURCE_DV" -n openshift-virtualization-os-images \
>>>>>>> Stashed changes
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{" "}{.status.conditions[?(@.type=="Ready")].message}{"\n"}'
```

**Expected output (before Phase 4 pipeline):**

```text
False PVC not found
```

**Expected output (after Phase 4 pipeline succeeds):**

```text
True
```

#### 4.1 Install OpenShift Pipelines

```bash
oc create namespace openshift-pipelines

oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-pipelines
  namespace: openshift-pipelines
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator-rh
  namespace: openshift-pipelines
spec:
  channel: latest
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

oc get csv -n openshift-pipelines -w
```

**Expected output:**

```text
# oc create namespace ...
namespace/openshift-pipelines created

# oc apply ...
operatorgroup.openshift-pipelines created
subscription.openshift-pipelines-operator-rh created

# oc get csv ... (wait until):
NAME                                       DISPLAY                        VERSION   PHASE
<<<<<<< Updated upstream
openshift-pipelines-operator-rh.v1.14.5    Red Hat OpenShift Pipelines    1.14.5    Succeeded
=======
<pipelines-operator-csv-name>    Red Hat OpenShift Pipelines    <pipelines-version>    Succeeded
>>>>>>> Stashed changes
```

**Pass:** Pipelines CSV `PHASE=Succeeded`.

#### 4.2 Windows Server 2022 boot-source pipeline

The `windows-efi-installer` Tekton pipeline downloads a Microsoft ISO, runs an unattended install inside a temporary VM, sysprep-generalizes the disk, and publishes the **`win2k22`** boot source in `openshift-virtualization-os-images`. Expect **30–60 minutes**.

**Prerequisites (in addition to Phase 1 metal + Phase 3 Hyperdisk):**

- OpenShift Pipelines CSV **Succeeded** (section 4.1)
- A **C3 metal** worker with KVM (the installer VM cannot run on N2)
- On C3 metal, pipeline temp disks must use **Hyperdisk** — set `hyperdisk-virt-sc` as the default StorageClass before starting (revert afterward if you prefer):

```bash
oc patch storageclass hyperdisk-virt-sc --type merge -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
oc patch storageclass standard-csi --type merge -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true
oc get storageclass
```

**Expected output:**

```text
# oc get storageclass
NAME                PROVISIONER                 ...   DEFAULT
hyperdisk-virt-sc   pd.csi.storage.gke.io       ...   true
standard-csi        pd.csi.storage.gke.io       ...   false
```

##### 4.2.1 Wait for Pipelines operator

```bash
oc get csv -n openshift-pipelines \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase | grep -i pipelines

# Wait until PHASE = Succeeded (Ctrl+C when ready)
oc get csv -n openshift-pipelines -w
```

**Expected output:**

```text
NAME                                       PHASE
<<<<<<< Updated upstream
openshift-pipelines-operator-rh.v1.14.5    Succeeded
=======
<pipelines-operator-csv-name>    Succeeded
>>>>>>> Stashed changes
```

##### 4.2.2 Grant SCC to the pipeline ServiceAccount

The `modify-windows-iso-file` task must run as UID/GID **107**:

```bash
oc adm policy add-scc-to-user anyuid -z pipeline -n default
```

**Expected output:**

```text
clusterrole.rbac.authorization.k8s.io/system:openshift:scc:anyuid added: "pipeline"
```

##### 4.2.3 Obtain the Windows Server 2022 ISO URL

1. Open https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
2. Register / sign in, continue to download
3. Select **English (United States)** — **64-bit** ISO
4. **Right-click** the Download button → **Copy link address** (do not click through; the URL expires in ~24 h)

```bash
# Paste the copied URL (must be en-US x64)
<<<<<<< Updated upstream
export WIN_IMAGE_DOWNLOAD_URL='https://go.microsoft.com/fwlink/?linkid=...'
=======
export WIN_IMAGE_DOWNLOAD_URL='https://go.microsoft.com/fwlink/?linkid=...'  # overwrites Step 0 placeholder
>>>>>>> Stashed changes
test -n "$WIN_IMAGE_DOWNLOAD_URL" && echo "ISO URL set (${#WIN_IMAGE_DOWNLOAD_URL} chars)"
```

**Expected output:**

```text
ISO URL set (142 chars)
```

##### 4.2.4 Match pipeline version to cluster

<<<<<<< Updated upstream
Hub resolver version should match your OpenShift **major.minor** (e.g. cluster `4.18.12` → `v4.18.0`):

```bash
export PIPELINE_VERSION="v$(oc get clusterversion version -o jsonpath='{.status.desired.version}' | cut -d. -f1-2).0"
=======
Uses `$PIPELINE_VERSION` from Step 0 (must match OpenShift **major.minor**):

```bash
>>>>>>> Stashed changes
echo "Using pipeline version: $PIPELINE_VERSION"
```

**Expected output:**

```text
<<<<<<< Updated upstream
Using pipeline version: v4.21.0
```

If the PipelineRun fails with “pipeline not found”, check [ArtifactHub windows-efi-installer](https://artifacthub.io/packages/tekton-pipeline/redhat-pipelines/windows-efi-installer) for the exact `v4.x.y` tag installed on your cluster.

##### 4.2.5 Start the PipelineRun

Run in **`default`** (Tekton creates the `pipeline` ServiceAccount there). Parameters target the cluster-wide `win2k22` DataSource:
=======
Using pipeline version: v<major>.<minor>.0
```

Hub pipeline tag must match cluster OpenShift **major.minor** — see [ArtifactHub windows-efi-installer](https://artifacthub.io/packages/tekton-pipeline/redhat-pipelines/windows-efi-installer).

##### 4.2.5 Start the PipelineRun

Confirm the ISO URL is set, then create the PipelineRun:

```bash
test -n "$WIN_IMAGE_DOWNLOAD_URL" || { echo "Set WIN_IMAGE_DOWNLOAD_URL (Step 0 / 4.2.3)"; exit 1; }
```

Run in **`default`** (Tekton creates the `pipeline` ServiceAccount there). Parameters target the `$WIN_BOOTSOURCE_DV` DataSource:
>>>>>>> Stashed changes

| Parameter | Value |
|-----------|-------|
| `preferenceName` | `windows.2k22.virtio` |
| `autounattendConfigMapName` | `windows2k22-autounattend` (shipped with the pipeline) |
<<<<<<< Updated upstream
| `baseDvName` / `isoDVName` | `win2k22` |
| `baseDvNamespace` | `openshift-virtualization-os-images` |
=======
| `baseDvName` / `isoDvName` | `$WIN_BOOTSOURCE_DV` |
| `baseDvNamespace` | `$WIN_BOOTSOURCE_NAMESPACE` |
>>>>>>> Stashed changes
| `acceptEula` | `"true"` — you accept Microsoft’s license for this install |

```bash
oc create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: windows2k22-installer-run-
  namespace: default
spec:
  params:
    - name: winImageDownloadURL
      value: "${WIN_IMAGE_DOWNLOAD_URL}"
    - name: acceptEula
      value: "true"
    - name: preferenceName
      value: windows.2k22.virtio
    - name: autounattendConfigMapName
      value: windows2k22-autounattend
    - name: baseDvName
<<<<<<< Updated upstream
      value: win2k22
    - name: baseDvNamespace
      value: openshift-virtualization-os-images
    - name: isoDVName
      value: win2k22
=======
      value: ${WIN_BOOTSOURCE_DV}
    - name: baseDvNamespace
      value: ${WIN_BOOTSOURCE_NAMESPACE}
    - name: isoDVName
      value: ${WIN_BOOTSOURCE_DV}
>>>>>>> Stashed changes
  pipelineRef:
    resolver: hub
    params:
      - name: catalog
        value: redhat-pipelines
      - name: type
        value: artifact
      - name: kind
        value: pipeline
      - name: name
        value: windows-efi-installer
      - name: version
        value: ${PIPELINE_VERSION}
  taskRunSpecs:
    - pipelineTaskName: modify-windows-iso-file
      timeout: 2h0m0s
      podTemplate:
        securityContext:
          fsGroup: 107
          runAsUser: 107
  timeouts:
    pipeline: 4h0m0s
EOF
```

**Expected output:**

```text
<<<<<<< Updated upstream
pipelinerun.tekton.dev/windows2k22-installer-run-xxxxx created
```

> **Note:** `modify-windows-iso-file` defaults to a **1h** per-task timeout. On Hyperdisk/metal, guestfish extract/repack of the ~5 GiB ISO often exceeds that — you will see `TaskRunTimeout` even though the task was still working. The `timeout: 2h0m0s` override above fixes this; bump to `3h0m0s` if it times out again.
=======
pipelinerun.tekton.dev/<pipelinerun-name> created
```

> **Note:** The PipelineRun above sets `timeout: 2h0m0s` on `modify-windows-iso-file` and `timeouts.pipeline: 4h0m0s` for Hyperdisk/metal runtimes.
>>>>>>> Stashed changes

##### 4.2.5a What the pipeline deletes (and what it keeps)

The `finally` block **always** runs after success or failure:

| Task | Deleted | Purpose |
|------|---------|---------|
| `delete-imported-iso` | ISO DataVolume/PVC (`win2k22-xxxxx`) | Temp download — not needed after install |
| `cleanup-vm` | Installer VM (`windows-efi-xxxxx`) | Temp VM that ran Windows Setup |
| `delete-vm-rootdisk` | Installer scratch root disk | Source disk after clone to golden image |

**This is normal.** You do **not** run guest VMs from the ISO or the installer VM.

**What you keep:** the **`win2k22`** golden-image DataVolume + DataSource (cloned installed disk). That is what Phase 6 clones for `win-demo`.

##### 4.2.5b Run only ONE pipeline at a time

Every run uses the same names (`win2k22`, `win2k22-*`, `windows-efi-*`). A second PipelineRun while one is running or after one succeeded will **overwrite or corrupt** the first run's golden image.

| Do | Don't |
|----|-------|
| Wait for `pipelinerun ... Succeeded` | Start a second pipeline "just in case" |
| Let `wait-for-vmi-status` finish (20–40 min) | Cancel a healthy run because ISO was deleted |
| Proceed to Phase 6 after boot source Ready | Re-run the pipeline after success |

<<<<<<< Updated upstream
If you already started a second run by mistake:

```bash
# Only cancel the NEWER run if the older one already Succeeded and you haven't lost the golden image
oc get pipelinerun -n default --sort-by=.metadata.creationTimestamp

# Cancel the in-progress duplicate (replace name):
oc cancel pipelinerun windows2k22-installer-run-NEWER -n default
# or:
oc delete pipelinerun windows2k22-installer-run-NEWER -n default
```

If the second run already replaced `win2k22` with a `blank` DataVolume, the first golden image is gone — let the **current** run finish; do not start a third.
=======
>>>>>>> Stashed changes

##### 4.2.6 Monitor progress

```bash
<<<<<<< Updated upstream
# Refresh every 2 minutes (or use -w for live stream)
watch -n 120 'date; oc get pipelinerun,taskrun -n default; echo; oc get vmi,vm -n default; echo; oc get datasource win2k22 -n default -o custom-columns=NS:metadata.namespace,READY:.status.conditions[?(@.type==\"Ready\")].status,MSG:.status.conditions[?(@.type==\"Ready\")].message; oc get datasource win2k22 -n openshift-virtualization-os-images -o custom-columns=NS:metadata.namespace,READY:.status.conditions[?(@.type==\"Ready\")].status,MSG:.status.conditions[?(@.type==\"Ready\")].message'

# Or live stream:
oc get pipelinerun,taskrun -n default -w

# Temporary installer resources (default namespace)
oc get dv,pvc,vm,vmi -n default | grep -E 'win2k22|windows-efi'

# Golden image DV (final artifact — check BOTH namespaces; see 4.2.7)
oc get dv win2k22 -n default -o wide
oc get dv win2k22 -n openshift-virtualization-os-images -o wide 2>/dev/null || true
=======
# Refresh every 2 minutes (one resource type per oc get)
watch -n 120 'date; oc get pipelinerun -n default; oc get taskrun -n default; echo; oc get vmi -n default; oc get vm -n default'

# Boot source Ready (run separately):
oc get datasource "$WIN_BOOTSOURCE_DV" -n default   -o custom-columns=NS:.metadata.namespace,READY:.status.conditions[?(@.type=="Ready")].status 2>/dev/null || true
oc get datasource "$WIN_BOOTSOURCE_DV" -n openshift-virtualization-os-images   -o custom-columns=NS:.metadata.namespace,READY:.status.conditions[?(@.type=="Ready")].status 2>/dev/null || true

# Or live stream (one type per command):
oc get pipelinerun -n default -w

# Temporary installer resources (default namespace)
oc get dv -n default | grep -E "$WIN_BOOTSOURCE_DV|windows-efi"
oc get pvc -n default | grep -E "$WIN_BOOTSOURCE_DV|windows-efi"
oc get vm -n default | grep -E "$WIN_BOOTSOURCE_DV|windows-efi"
oc get vmi -n default | grep -E "$WIN_BOOTSOURCE_DV|windows-efi"

# Golden image DV (final artifact — check BOTH namespaces; see 4.2.7)
oc get dv "$WIN_BOOTSOURCE_DV" -n default -o wide
oc get dv "$WIN_BOOTSOURCE_DV" -n openshift-virtualization-os-images -o wide 2>/dev/null || true
>>>>>>> Stashed changes
```

**Expected output — task progression:**

```text
# Early (~5–15 min): ISO import + modify
NAME                                                    SUCCEEDED   REASON      STARTTIME   COMPLETIONTIME
<<<<<<< Updated upstream
windows2k22-installer-run-xxxxx-import-win-iso          True        Succeeded   5m          4m
windows2k22-installer-run-xxxxx-modify-windows-iso-file Unknown     Running     4m

# Mid (~20–50 min): installer VM running Windows setup
windows2k22-installer-run-xxxxx-create-vm               True        Succeeded   25m         25m
windows2k22-installer-run-xxxxx-wait-for-vmi-status     Unknown     Running     25m

# oc get vmi -n default
NAME              AGE   PHASE     IP            NODE                               READY
windows-efi-xxxxx 30m   Running   10.128.x.x    nddemo-wq4kd-virt-worker-a-6277p   True

# Late (~45–90 min): installer shuts down, cleanup deletes ISO/VM, golden image remains
windows2k22-installer-run-xxxxx-wait-for-vmi-status     True        Succeeded   55m         50m
windows2k22-installer-run-xxxxx-create-datasource-root-disk True     Succeeded   50m         48m
windows2k22-installer-run-xxxxx-delete-imported-iso     True        Succeeded   48m         48m
windows2k22-installer-run-xxxxx                         True        Succeeded   55m         48m

# oc get dv win2k22 -n default   (pipeline may place golden image here even if baseDvNamespace was set)
NAME      PHASE       PROGRESS   RESTARTS   AGE
win2k22   Succeeded   100.0%                48m
=======
<pipelinerun-name>-import-win-iso          True        Succeeded   5m          4m
<pipelinerun-name>-modify-windows-iso-file Unknown     Running     4m

# Mid (~20–50 min): installer VM running Windows setup
<pipelinerun-name>-create-vm               True        Succeeded   25m         25m
<pipelinerun-name>-wait-for-vmi-status     Unknown     Running     25m

# oc get vmi -n default
NAME              AGE   PHASE     IP            NODE                               READY
<installer-vmi-name> 30m   Running   <guest-ip>    <metal-worker-node-name>   True

# Late (~45–90 min): installer shuts down, cleanup deletes ISO/VM, golden image remains
<pipelinerun-name>-wait-for-vmi-status     True        Succeeded   55m         50m
<pipelinerun-name>-create-datasource-root-disk True     Succeeded   50m         48m
<pipelinerun-name>-delete-imported-iso     True        Succeeded   48m         48m
<pipelinerun-name>                         True        Succeeded   55m         48m

# oc get dv <windows-bootsource-dv> -n default   (pipeline may place golden image here even if baseDvNamespace was set)
NAME      PHASE       PROGRESS   RESTARTS   AGE
<windows-bootsource-dv>   Succeeded   100.0%                48m
>>>>>>> Stashed changes

# Installer VM gone after cleanup — expected:
# oc get vm -n default
No resources found
```

**Healthy progression:** `import-win-iso` → `modify-windows-iso-file` → `windows-efi-*` installer VM **Running** on metal → VM shuts down after sysprep → `create-datasource-root-disk` → **finally** deletes ISO + installer VM → `win2k22` golden DV **Succeeded**.

**Installer VM healthy (mid-run):**

```text
# oc get vmi -n default
NAME              PHASE       NODE                               READY
<<<<<<< Updated upstream
windows-efi-xxxxx Scheduled   nddemo-wq4kd-virt-worker-a-6277p   False

# oc get pvc -n default | grep -E 'persistent-state|win2k22'
persistent-state-for-windows-efi-xxxxx   Bound   ...   4Gi    hyperdisk-virt-sc
win2k22                                  Bound   ...   22Gi   hyperdisk-virt-sc
```

**Bad signs (not normal):**

```text
# modify-windows-iso-file Pending 60+ min → PVC/IOPS issue
modify-windows-iso-file   Unknown   Pending   60m

# windows-efi-* Starting 10+ min + virt-launcher Pending → EFI state PVC failed
virt-launcher-windows-efi-xxxxx   0/3   Pending   0   10m
```

If a task fails, inspect logs:

```bash
PR=$(oc get pipelinerun -n default --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
oc describe pipelinerun "$PR" -n default

# Logs from the most recent failed/slow task
TR=$(oc get taskrun -n default -l "tekton.dev/pipelineRun=$PR" \
  --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
oc logs "taskrun/$TR" -n default --all-containers --tail=100
```

**Expected output (failed run):**

```text
# oc describe pipelinerun ...
Status:
  Conditions:
    Message:  Tasks Completed: 4 (Failed: 1, Cancelled 0), Skipped: 4
    Reason:   Failed
    Status:   False
```
=======
<installer-vmi-name> Scheduled   <metal-worker-node-name>   False

# oc get pvc -n default | grep -E 'persistent-state|<windows-bootsource-dv>'
persistent-state-for-<installer-vmi-name>   Bound   ...   4Gi    hyperdisk-virt-sc
<windows-bootsource-dv>                                  Bound   ...   22Gi   hyperdisk-virt-sc
```

>>>>>>> Stashed changes

##### 4.2.7 Verify boot source (check both namespaces)

Even when `baseDvNamespace=openshift-virtualization-os-images` is set on the PipelineRun, the hub pipeline (4.21.x) often publishes the golden image in **`default`**. Check both before Phase 6.

```bash
oc get pipelinerun -n default \
  -o custom-columns=NAME:.metadata.name,SUCCEEDED:.status.conditions[0].status,REASON:.status.conditions[0].reason

# Golden image DV — usable vs destroyed
<<<<<<< Updated upstream
oc get dv win2k22 -n default -o jsonpath='ns=default phase={.status.phase} source={.spec.source}{"\n"}'
oc get dv win2k22 -n openshift-virtualization-os-images -o jsonpath='ns=os-images phase={.status.phase} source={.spec.source}{"\n"}' 2>/dev/null || echo 'ns=os-images (not found)'

# DataSource Ready in both namespaces
oc get datasource win2k22 -n default \
  -o jsonpath='default: Ready={.status.conditions[?(@.type=="Ready")].status} msg={.status.conditions[?(@.type=="Ready")].message}{"\n"}'
oc get datasource win2k22 -n openshift-virtualization-os-images \
=======
oc get dv "$WIN_BOOTSOURCE_DV" -n default -o jsonpath='ns=default phase={.status.phase} source={.spec.source}{"\n"}'
oc get dv "$WIN_BOOTSOURCE_DV" -n openshift-virtualization-os-images -o jsonpath='ns=os-images phase={.status.phase} source={.spec.source}{"\n"}' 2>/dev/null || echo 'ns=os-images (not found)'

# DataSource Ready in both namespaces
oc get datasource "$WIN_BOOTSOURCE_DV" -n default \
  -o jsonpath='default: Ready={.status.conditions[?(@.type=="Ready")].status} msg={.status.conditions[?(@.type=="Ready")].message}{"\n"}'
oc get datasource "$WIN_BOOTSOURCE_DV" -n openshift-virtualization-os-images \
>>>>>>> Stashed changes
  -o jsonpath='os-images: Ready={.status.conditions[?(@.type=="Ready")].status} msg={.status.conditions[?(@.type=="Ready")].message}{"\n"}'
```

**Expected output — usable golden image (proceed to Phase 6):**

```text
# oc get pipelinerun ...
NAME                              SUCCEEDED   REASON
<<<<<<< Updated upstream
windows2k22-installer-run-xxxxx   True        Succeeded

# Golden DV — must be Succeeded with PVC clone source, NOT blank:
ns=default phase=Succeeded source={"pvc":{"name":"win2k22","namespace":"default"}}
=======
<pipelinerun-name>   True        Succeeded

# Golden DV — must be Succeeded with PVC clone source, NOT blank:
ns=default phase=Succeeded source={"pvc":{"name":"<windows-bootsource-dv>","namespace":"default"}}
>>>>>>> Stashed changes

default: Ready=True msg=
os-images: Ready=False msg=PVC not found
```

Use `DATA_SOURCE_NAMESPACE=default` in Phase 6 when the Ready DataSource is in `default`.

<<<<<<< Updated upstream
**Expected output — golden image destroyed (re-run pipeline once, do not overlap runs):**

```text
ns=default phase=PendingPopulation source={"blank":{}}
default: Ready=False msg=Import DataVolume phase PendingPopulation
```

A second PipelineRun overwrote `win2k22` with a blank installer root disk. Delete partial artifacts (4.2.8), run **one** new PipelineRun, wait for `Succeeded`.
=======
>>>>>>> Stashed changes

**Expected output — both namespaces (ideal, less common on 4.21 hub pipeline):**

```text
ns=os-images phase=Succeeded source={"pvc":{...}}
os-images: Ready=True msg=
```

Use `DATA_SOURCE_NAMESPACE=openshift-virtualization-os-images` in Phase 6.

<<<<<<< Updated upstream
**Pass:** PipelineRun `Succeeded`; `win2k22` DataVolume **Succeeded** (not `blank` source); DataSource **Ready=True** in at least one namespace.

Console: **Virtualization → Bootable volumes** — **Windows Server 2022** may appear under the namespace where the DataSource is Ready.

##### 4.2.8 Cleanup failed or duplicate pipeline run

**Only use this when a run Failed**, or to remove artifacts from a **duplicate** run after canceling it. **Do not** delete `win2k22` after a **Succeeded** pipeline — that is your boot source.

```bash
# Cancel/delete the failed or duplicate run (replace name):
oc cancel pipelinerun windows2k22-installer-run-NEWER -n default
oc delete pipelinerun windows2k22-installer-run-NEWER -n default --ignore-not-found

oc delete vm,vmi -n default -l kubevirt.io=vm --ignore-not-found
# delete stuck installer VM by name if needed:
# oc delete vm windows-efi-xxxxx -n default

# list and delete leftover pipeline PVCs/DVs (ISO imports win2k22-xxxxx, NOT golden win2k22 if Succeeded)
oc get pvc,dv -n default
oc delete dv win2k22-rhx88 -n default --ignore-not-found   # example ISO DV name
oc delete pvc win2k22-rhx88 -n default --ignore-not-found

# Only delete win2k22 itself if verify (4.2.7) shows source=blank / pipeline never succeeded:
# oc delete dv win2k22 -n default
# oc delete pvc win2k22 -n default
```

**Expected output:**

```text
pipelinerun.tekton.dev "windows2k22-installer-run-xxxxx" deleted
virtualmachine.kubevirt.io "windows-efi-xxxxx" deleted
```

(Optional) Restore previous default StorageClass:

```bash
oc patch storageclass standard-csi --type merge -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
oc patch storageclass hyperdisk-virt-sc --type merge -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

**Expected output:**

```text
storageclass.storage.k8s.io/standard-csi patched
storageclass.storage.k8s.io/hyperdisk-virt-sc patched
```

**Console alternative:** **Help → Quick Starts → Creating a Windows boot source** walks the same flow in the UI.

Common failures on GCP metal:

| Symptom | Fix |
|---------|-----|
| `pd-standard disk type cannot be used by c3-standard-192-metal` | Set `hyperdisk-virt-sc` as default SC (top of 4.2) |
| `guestfish: ... Permissions denied` in `modify-windows-iso-file` | Re-apply `anyuid` SCC (4.2.2) and `taskRunSpecs` with `runAsUser: 107` |
| ISO download HTTP error | URL expired — generate a new link from Eval Center |
| `acceptEula` / pipeline exits immediately | Set `acceptEula: "true"` |
| `modify-windows-iso-file` **Pending** then **TaskRunTimeout** | Usually **PVC never bound**, not slow guestfish. `oc describe pvc -n default` → `provisioned IOPS is too high` — recreate `hyperdisk-virt-sc` **without** fixed IOPS (Phase 3) |
| `windows-efi-*` VM stuck **Starting** / virt-launcher **Pending** | KubeVirt EFI state PVC is **4 Gi** — fails with fixed 3000+ IOPS. Same SC fix; delete stuck VM/PVC and re-run pipeline |
| `modify-windows-iso-file` **TaskRunTimeout** while **Running** | Guestfish still working — add `timeout: 2h0m0s` under `taskRunSpecs`; set `timeouts.pipeline: 4h0m0s` |
| Pipeline **Succeeded** but ISO / installer VM **deleted** | Expected — golden image is `win2k22` DV; verify 4.2.7 |
| Second pipeline overwrote `win2k22` with `source=blank` | Cancel duplicate run; let current run finish or re-run once (4.2.5b) |
| `Source PVC win2k22 not available` on VM | DataSource not Ready or wrong `DATA_SOURCE_NAMESPACE` — use `default` if pipeline put boot source there (4.2.7) |
| VM **Stopped** — `insufficient permissions in clone source namespace default` | Phase **6.0** — RBAC + Halted→Always toggle (patch `Always` alone is not enough) |
=======
**Pass:** PipelineRun `Succeeded`; `<windows-bootsource-dv>` DataVolume **Succeeded** with PVC source; DataSource **Ready=True** in at least one namespace.

Console: **Virtualization → Bootable volumes** — **Windows Server 2022** may appear under the namespace where the DataSource is Ready.
>>>>>>> Stashed changes

#### 4.3 (Optional) Private Google Access

```bash
gcloud compute networks subnets update "$WORKER_SUBNET" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --enable-private-ip-google-access
```

**Expected output:**

```text
<<<<<<< Updated upstream
Updated [https://www.googleapis.com/compute/v1/projects/it-cloud-gcp-mobb-amer/regions/us-central1/subnetworks/nddemo-worker-subnet].
=======
Updated [https://www.googleapis.com/compute/v1/projects/${GCP_PROJECT}/regions/${GCP_REGION}/subnetworks/${WORKER_SUBNET}].
>>>>>>> Stashed changes
```

---

## Phase 5 — Linux VM (reliable workflow)

**Pattern:** (1) import disk with Hyperdisk + registry + immediate bind, (2) attach existing PVC to VM.

### 5.1 Namespace and SSH key

```bash
oc new-project "$LINUX_PROJECT"

ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -q
export SSH_PUBKEY=$(cat "${SSH_KEY}.pub")
```

**Expected output:**

```text
# oc new-project <linux-project>
Now using project "<linux-project>" on server "https://api.<cluster-domain>:6443".

# ssh-keygen (no output on success)
```

**Expected output:**

```text
# oc new-project linux-vms
Now using project "linux-vms" on server "https://api.nddemo.o4do.p2.openshiftapps.com:6443".

# ssh-keygen (no output on success)
```

### 5.2 Import disk (DataVolume)

```bash
oc apply -f - <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ${LINUX_DV_NAME}
  namespace: ${LINUX_PROJECT}
  annotations:
    cdi.kubevirt.io/storage.bind.immediate.requested: "true"
spec:
  source:
    registry:
      url: docker://quay.io/containerdisks/centos-stream:9
      pullMethod: node
  storage:
    storageClassName: ${HYPERDISK_SC}
    resources:
      requests:
        storage: 32Gi
EOF
```

Watch until **Succeeded** (15–25 min first time):

```bash
oc get dv "$LINUX_DV_NAME" -n "$LINUX_PROJECT" -w
```

**Expected output (progression):**

```text
NAME              PHASE             PROGRESS   RESTARTS   AGE
<linux-dv-name>   Pending                                  10s
<linux-dv-name>   ImportScheduled   N/A                   30s
<linux-dv-name>   ImportInProgress  12.5%                 5m
<linux-dv-name>   Succeeded         100.0%                18m
```

**Expected output (progression):**

```text
NAME              PHASE             PROGRESS   RESTARTS   AGE
linux-demo-disk   Pending                                  10s
linux-demo-disk   ImportScheduled   N/A                   30s
linux-demo-disk   ImportInProgress  12.5%                 5m
linux-demo-disk   Succeeded         100.0%                18m
```

```bash
<<<<<<< Updated upstream
oc get dv linux-demo-disk -n linux-vms -o jsonpath='{.status.phase}{"\n"}'
oc get pvc linux-demo-disk -n linux-vms
```

**Expected output:**

```text
Succeeded

NAME              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
linux-demo-disk   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   32Gi       RWO            hyperdisk-virt-sc
=======
oc get dv "$LINUX_DV_NAME" -n "$LINUX_PROJECT" -o jsonpath='{.status.phase}{"\n"}'
oc get pvc "$LINUX_DV_NAME" -n "$LINUX_PROJECT"
>>>>>>> Stashed changes
```

**Expected output:**

```text
Succeeded

NAME              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
<linux-dv-name>   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   32Gi       RWO            hyperdisk-virt-sc
```

**Expected output (healthy importer):**

```text
NAME                              READY   STATUS    RESTARTS   AGE
importer-linux-demo-disk-xxxxx    1/1     Running   0          8m
```

### 5.3 Create VM (uses existing PVC)

```bash
oc apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${LINUX_VM_NAME}
  namespace: ${LINUX_PROJECT}
spec:
  runStrategy: Always
  template:
    metadata:
      labels:
        kubevirt.io/domain: ${LINUX_VM_NAME}
    spec:
      domain:
        cpu: {cores: 1, sockets: 1, threads: 1}
        memory: {guest: 2Gi}
        devices:
          disks:
          - {name: rootdisk, disk: {bus: virtio}, bootOrder: 1}
          - {name: cloudinitdisk, disk: {bus: virtio}}
          interfaces:
          - {name: default, masquerade: {}, model: virtio}
        machine: {type: pc-q35-rhel9.6.0}
      networks:
      - {name: default, pod: {}}
      volumes:
      - name: rootdisk
        persistentVolumeClaim:
          claimName: ${LINUX_DV_NAME}
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            user: centos
            ssh_authorized_keys:
              - "${SSH_PUBKEY}"
EOF
```

**Expected output:**

```text
<<<<<<< Updated upstream
virtualmachine.kubevirt.io/linux-demo created
=======
virtualmachine.kubevirt.io/<linux-vm-name> created
>>>>>>> Stashed changes
```

Watch (2–5 min after DV Succeeded):

```bash
<<<<<<< Updated upstream
oc get vm linux-demo -n linux-vms -w
oc get vmi linux-demo -n linux-vms -o wide
=======
oc get vm "$LINUX_VM_NAME" -n "$LINUX_PROJECT" -w
oc get vmi "$LINUX_VM_NAME" -n "$LINUX_PROJECT" -o wide
>>>>>>> Stashed changes
```

**Expected output:**

```text
# oc get vm ...
NAME         AGE   STATUS    READY
<<<<<<< Updated upstream
linux-demo   2m    Running   True

# oc get vmi ... -o wide
NAME         AGE   PHASE     IP            NODE                               READY
linux-demo   2m    Running   10.128.x.x    nddemo-wq4kd-virt-worker-a-6277p   True
=======
<linux-vm-name>   2m    Running   True

# oc get vmi ... -o wide
NAME         AGE   PHASE     IP            NODE                               READY
<linux-vm-name>   2m    Running   <guest-ip>    <metal-worker-node-name>   True
>>>>>>> Stashed changes
```

**Pass:** `NODE` is the metal worker (`*-virt-*` or `c3-standard-192-metal`); `READY=True`.

### 5.4 SSH test

```bash
virtctl ssh "centos@vmi/${LINUX_VM_NAME}" -n "$LINUX_PROJECT" \
  -i "$SSH_KEY" \
  --local-ssh-opts="-o StrictHostKeyChecking=accept-new" \
  --command "hostname"
```

**Expected output:**

```text
<<<<<<< Updated upstream
linux-demo
```

**Pass:** prints guest hostname (e.g. `linux-demo`).
=======
<linux-vm-name>
```

**Pass:** prints guest hostname (matches `<linux-vm-name>`).
>>>>>>> Stashed changes

---

## Phase 6 — Windows VM

<<<<<<< Updated upstream
**Prerequisites:** Phase 4 pipeline **Succeeded**; `win2k22` DataSource **Ready=True**; `hyperdisk-virt-sc` exists.

Confirm boot source namespace before applying the template (see 4.2.7):

```bash
export WIN_DS_NAMESPACE=default
# or, if os-images namespace is Ready:
# export WIN_DS_NAMESPACE=openshift-virtualization-os-images

oc get datasource win2k22 -n "$WIN_DS_NAMESPACE" \
=======
**Prerequisites:** Phase 4 pipeline **Succeeded**; `$WIN_BOOTSOURCE_DV` DataSource **Ready=True**; `$HYPERDISK_SC` exists.

Confirm boot source (namespace from Step 0 `$WIN_DS_NAMESPACE`; see 4.2.7):

```bash
oc get datasource "$WIN_BOOTSOURCE_DV" -n "$WIN_DS_NAMESPACE" \
>>>>>>> Stashed changes
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}'
```

**Expected output:**

```text
Ready=True
```

<<<<<<< Updated upstream
If `Ready=False`, do not create the VM — finish or re-run Phase 4 first.

### 6.0 Cross-namespace clone RBAC (read before creating the VM)

The boot-source pipeline (4.21 hub) often publishes `win2k22` in namespace **`default`**, while the guest VM is created in **`windows-vms`**. CDI must clone the golden PVC across namespaces. **Grant this RBAC before creating `win-demo`** — if the VM is created first, it stays **Stopped** with a stale `Failure` condition even after RBAC is fixed.
=======
Proceed only when the command prints `Ready=True`.

### 6.0 Cross-namespace clone RBAC (read before creating the VM)

The boot-source pipeline (4.21 hub) often publishes `$WIN_BOOTSOURCE_DV` in namespace **`default`**, while the guest VM is created in **`$WINDOWS_PROJECT`**. CDI must clone the golden PVC across namespaces. **Run section 6.0.1 before creating `$WINDOWS_VM_NAME`** when `WIN_DS_NAMESPACE=default`.
>>>>>>> Stashed changes

#### 6.0.1 Grant clone permission (when `WIN_DS_NAMESPACE=default`)

```bash
oc adm policy add-role-to-user cdi.kubevirt.io:clone-sourcer \
<<<<<<< Updated upstream
  system:serviceaccount:windows-vms:default \
=======
  system:serviceaccount:${WINDOWS_PROJECT}:default \
>>>>>>> Stashed changes
  -n default
```

**Expected output:**

```text
<<<<<<< Updated upstream
clusterrole.rbac.authorization.k8s.io/cdi.kubevirt.io:clone-sourcer added: "system:serviceaccount:windows-vms:default"
=======
clusterrole.rbac.authorization.k8s.io/cdi.kubevirt.io:clone-sourcer added: "system:serviceaccount:<windows-project>:default"
>>>>>>> Stashed changes
```

Verify the RoleBinding in the **source** namespace (`default`):

```bash
oc get rolebinding cdi.kubevirt.io:clone-sourcer -n default -o yaml
```

<<<<<<< Updated upstream
**Expected:** `subjects` → `ServiceAccount/default` in `windows-vms`; `roleRef.name` → `cdi.kubevirt.io:clone-sourcer`.
=======
**Expected:** `subjects` → `ServiceAccount/default` in `<windows-project>`; `roleRef.name` → `cdi.kubevirt.io:clone-sourcer`.
>>>>>>> Stashed changes

Optional permission check:

```bash
oc auth can-i create datavolumes/source \
<<<<<<< Updated upstream
  --as=system:serviceaccount:windows-vms:default \
=======
  --as=system:serviceaccount:${WINDOWS_PROJECT}:default \
>>>>>>> Stashed changes
  -n default
```

**Expected output:**

```text
yes
```
<<<<<<< Updated upstream

#### 6.0.2 Symptom — VM Stopped, no DataVolume

```bash
oc get vm win-demo -n windows-vms
oc get dv,vmi -n windows-vms
oc describe vm win-demo -n windows-vms | tail -15
```

**Expected output (broken — RBAC missing or not retried):**

```text
NAME       STATUS    READY
win-demo   Stopped   False

No resources found in windows-vms namespace.   # no DV, no VMI

Message: Error encountered while creating DataVolumes: not authorized to create DataVolume:
  User system:serviceaccount:windows-vms:default has insufficient permissions
  in clone source namespace default
Reason: FailedCreate
Type: Failure
```

`oc patch ... runStrategy: Always` alone may report **patched (no change)** and leave the VM **Stopped** — the controller does not always clear the old `Failure` condition.

#### 6.0.3 Fix — grant RBAC, then force a retry

```bash
# 1. RBAC (skip if already done)
oc adm policy add-role-to-user cdi.kubevirt.io:clone-sourcer \
  system:serviceaccount:windows-vms:default \
  -n default

# 2. Toggle runStrategy to clear stale Failure and re-trigger DV create
oc patch vm win-demo -n windows-vms --type merge -p '{"spec":{"runStrategy":"Halted"}}'
oc patch vm win-demo -n windows-vms --type merge -p '{"spec":{"runStrategy":"Always"}}'
```

**Expected output:**

```text
virtualmachine.kubevirt.io/win-demo patched
virtualmachine.kubevirt.io/win-demo patched
```

**Expected output (recovery under way):**

```bash
oc get vm,dv -n windows-vms
oc get vmi -n windows-vms
```

```text
NAME       STATUS         READY
win-demo   Provisioning   False

NAME       PHASE                               PROGRESS
win-demo   CloneFromSnapshotSourceInProgress   N/A
# or ImportInProgress / Succeeded

# oc describe vm win-demo -n windows-vms | tail -5
Normal  SuccessfulDataVolumeCreate  Created DataVolume win-demo
Normal  SuccessfulCreate            Started the virtual machine instance win-demo
```

Clone from `win2k22` takes **5–15 minutes** (60 Gi Hyperdisk). Then:

```text
win-demo   Running   True
```

#### 6.0.4 Watch progress

`oc get` accepts only one resource type per command. Use:

```bash
watch -n 30 'oc get vm,dv -n windows-vms; echo; oc get vmi,pvc -n windows-vms'
```

#### 6.0.5 If still Stopped after RBAC + toggle

Delete and recreate the VM (RBAC can stay in place):

```bash
oc delete vm win-demo -n windows-vms
# Re-run section 6.2 (console) or 6.3 (CLI) — ensure 6.0.1 RBAC exists first
```

**Alternatives (avoid cross-ns RBAC):**

- Create the guest VM in namespace **`default`** (same namespace as `win2k22`).
- Re-run the boot-source pipeline with a version that honors `baseDvNamespace=openshift-virtualization-os-images`, then use `WIN_DS_NAMESPACE=openshift-virtualization-os-images`.
=======
>>>>>>> Stashed changes

### 6.1 (Optional) GCP Windows PAYG license on metal node

**Not required** for Phases 1–5, OpenShift Virtualization install, Linux guest VMs, or creating Windows guests from the boot-source pipeline. Skip this section unless you use **Google’s pay-as-you-go (PAYG) Windows licensing** on a C3 metal worker that will run Windows guests.

When you opt in:

- The tag goes on the **metal worker RHCOS boot disk**, not on guest VM PVCs (`hyperdisk-virt-sc`).
- PAYG applies to the **entire** metal instance (all 192 vCPUs), even if only one KubeVirt pod runs Windows.
<<<<<<< Updated upstream
- The Windows license on that boot disk is **effectively permanent** on that disk; plan dedicated licensed pools or destroy/replace the worker to stop billing. See the off-ramp table in the licensing doc.
=======
- The Windows license on that boot disk is **effectively permanent** on that disk; plan dedicated licensed pools or destroy/replace the worker to stop billing (see **Off-ramp** below).
>>>>>>> Stashed changes

**How to tag:**

| Approach | When to use |
|----------|-------------|
| **Provision-time** — `licenses` on the boot disk in `GCPMachineProviderSpec` when creating a metal machine pool | New pool purpose-built for Windows on GCP PAYG (avoids stop/drain/day-2 `gcloud`) |
<<<<<<< Updated upstream
| **Day-2** — cordon, drain, stop instance, `gcloud compute disks update --append-licenses`, start | Existing metal worker; full procedure and validation results in [gcp-windows-ondemand-licensing-validation.md](gcp-windows-ondemand-licensing-validation.md) |

C3 metal boot disks must use **Hyperdisk** (`hyperdisk-balanced`), not `pd-standard` / `pd-ssd`. If you declare the license at pool create time, set boot disk `type: hyperdisk-balanced` in the provider spec (same constraint as Phase 3 for guest disks).

**Verify (either approach):**

```bash
NODE=<metal-worker-gce-name>
gcloud compute instances describe "$NODE" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
  --format='yaml(disks[].boot,disks[].licenses,disks[].type)'
```

**Expected:** boot disk `licenses` includes `windows-cloud/global/licenses/windows-server-2025-dc` (or your chosen Windows PAYG license URL) in addition to the RHCOS marketplace license.

### 6.2 Create VM from the OpenShift Console

Use the console when the boot source is Ready (4.2.7). URL: `https://console-openshift-console.apps.<cluster>.<domain>`.

#### Step 1 — Confirm boot source in the UI

1. Switch to **Administrator** perspective (gear icon → Administrator).
2. **Virtualization** → **Bootable volumes**.
3. Look for **Windows Server 2022** with status **Ready**.

**Expected:** Volume listed as Ready. If the pipeline published to `default` (4.2.7), the volume may appear under project **default** — switch namespace dropdown to **default** on the Bootable volumes page, or use the CLI path (6.3).

#### Step 2 — Create project

1. **Home** → **Projects** → **Create Project**.
2. Name: `windows-vms` → **Create**.

**Expected:** Project `windows-vms` appears in the namespace dropdown.

#### Step 2b — Cross-namespace RBAC (CLI, before creating the VM)

If `win2k22` is Ready in namespace **`default`** (4.2.7), run **6.0.1** now. Skip if boot source is in `openshift-virtualization-os-images` and the catalog shows it there.

#### Step 3 — Create VM from catalog

1. **Virtualization** → **Catalog** (or **VirtualMachines** → **Create** → **Create from template**).
2. Filter or select **Windows Server 2022** (template `windows2k22-server-medium` or similar).
3. Click **Quick create** or **Customize VirtualMachine**.

| Field | Value |
|-------|-------|
| Name | `win-demo` |
| Project / Namespace | `windows-vms` |
| Storage class | `hyperdisk-virt-sc` |
| Disk size | **60 GiB** minimum |
| Run strategy | **Always** (start after create) |

4. If the wizard offers **Boot source** / **DataSource**, select **win2k22**. If it is missing, the boot source is likely in namespace `default` — use section 6.3 CLI instead, or create from **YAML** (step 4 below).

5. Click **Create VirtualMachine**.

**Expected (VirtualMachines list):**

```text
NAME       STATUS        READY
win-demo   Provisioning  False
```

Then after 5–15 min (disk clone from `win2k22`):

```text
NAME       STATUS    READY
win-demo   Running   True
```

#### Step 4 — Enable SMM (required for Secure Boot)

The Windows template enables Secure Boot but not SMM by default. Without SMM the VM fails to start.

1. **Virtualization** → **VirtualMachines** → project `windows-vms` → **win-demo**.
2. **Actions** (⋮) → **Edit YAML**.
3. Under `spec.template.spec.domain`, add:

```yaml
features:
  smm:
    enabled: true
```

4. **Save**. If the VM already exists, it may restart once.

**Expected (Events tab or VM list):** No `SecureBoot requires SMM` errors; status moves to **Running**.

#### Step 5 — Open the guest console

1. **Virtualization** → **VirtualMachines** → `win-demo` (namespace `windows-vms`).
2. Open the **Console** tab (in-browser VNC), or **Actions** → **Open console**.

**Expected:** Windows OOBE / login screen (first boot after clone may take several minutes).

#### Step 6 — Verify node placement (optional)

On the VM details page, check **Scheduling** / **Node** — should be the metal worker (`*-virt-*`, `c3-standard-192-metal`).

**Expected:**

```text
Node: nddemo-wq4kd-virt-worker-a-6277p
```

**Console troubleshooting**

| Symptom in UI | Fix |
|---------------|-----|
| Boot source not in Catalog | `win2k22` in `default` — use 6.3 CLI or check Bootable volumes in `default` project |
| VM stuck **Provisioning** | **Events** tab → `Source PVC win2k22 not available` → finish Phase 4 |
| VM **Stopped**, no DV/VMI | **Events** → `insufficient permissions in clone source namespace default` → **6.0.1** RBAC, then **6.0.3** Halted→Always toggle |
| VM **Stopped** after RBAC fix | Stale `Failure` condition — **6.0.3** toggle `runStrategy`; do not only patch `Always` |
| `SecureBoot requires SMM` | Step 4 — edit YAML, enable SMM |
| Disk attach error on Events | Storage class not `hyperdisk-virt-sc` — edit VM storage or recreate with Hyperdisk |

### 6.3 Create VM from CLI

After boot source pipeline, create VM from template with **Hyperdisk** and **SMM**.

**Order:** `6.0.1` RBAC (if `WIN_DS_NAMESPACE=default`) → create VM → watch. If you already created the VM without RBAC, use **6.0.3**.
=======
| **Day-2** — cordon, drain, stop instance, `gcloud compute disks update --append-licenses`, start | Existing metal worker already running without the license |

C3 metal boot disks must use **Hyperdisk** (`hyperdisk-balanced`), not `pd-standard` / `pd-ssd`. If you declare the license at pool create time, set boot disk `type: hyperdisk-balanced` in the provider spec (same constraint as Phase 3 for guest disks).

#### 6.1.1 Day-2 license attach (existing metal worker)

License URL (example):
>>>>>>> Stashed changes

```bash
export WIN_PAYG_LICENSE_URL="https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc"
```

GCE **boot disk name** for OSD workers usually matches the **instance name** (node name). You cannot append licenses while the VM is **RUNNING**.

```bash
NODE=<metal-worker-gce-name>

oc adm cordon "$NODE"
oc adm drain "$NODE" \
  --ignore-daemonsets --delete-emptydir-data --force --grace-period=60

gcloud compute instances stop "$NODE" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT"

gcloud compute disks update "$NODE" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
  --append-licenses="$WIN_PAYG_LICENSE_URL"

gcloud compute instances start "$NODE" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT"

oc adm uncordon "$NODE"
```

Do not patch `srep-*` MachineHealthChecks. Complete stop → tag → start before the worker stays NotReady long enough to trigger remediation.

#### 6.1.2 Provision-time license (new metal pool)

Provision-time tagging requires the Machine API changes in [OCPSTRAT-3624](https://redhat.atlassian.net/browse/OCPSTRAT-3624) ([openshift/api#2980](https://github.com/openshift/api/pull/2980), [machine-api-provider-gcp#184](https://github.com/openshift/machine-api-provider-gcp/pull/184), [machine-api-operator#1553](https://github.com/openshift/machine-api-operator/pull/1553)). To **test** that path on a payload build (expected `gcloud describe` output, no day-2 append), see [gcp-machine-api-disk-licenses-qe.md](gcp-machine-api-disk-licenses-qe.md).

When defining a new metal machine pool, add the Windows license on the **boot disk** in `GCPMachineProviderSpec` (with `type: hyperdisk-balanced`). Example fragment — adjust image, network, subnet, and IDs to your cluster:

```yaml
machineType: c3-standard-192-metal
onHostMaintenance: Terminate
region: ${GCP_REGION}
zone: ${GCP_ZONE}
projectID: ${GCP_PROJECT}
disks:
  - autoDelete: true
    boot: true
    image: projects/rhcos-cloud/global/images/<rhcos-image>
    sizeGb: 200
    type: hyperdisk-balanced
    licenses:
      - projects/windows-cloud/global/licenses/windows-server-2025-dc
```

Keep at least one **untagged** metal worker if you also run Linux-only or non-PAYG workloads — PAYG is billed per **node**, not per guest VM.

#### 6.1.3 Off-ramp (stop PAYG billing)

| Path | Notes |
|------|--------|
| Destroy/replace the worker | New boot disk without the Windows license (confirm licenses on the new disk in GCE) |
| Dedicated licensed pool | Tag only workers that run Windows on GCP PAYG |
| Leave instance stopped | Still bills; avoid unless you are decommissioning |

**Verify (either approach):**

```bash
NODE=<metal-worker-gce-name>
gcloud compute instances describe "$NODE" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
  --format='yaml(disks[].boot,disks[].licenses,disks[].type)'
```

**Expected:** boot disk `licenses` includes `windows-cloud/global/licenses/windows-server-2025-dc` (or your chosen Windows PAYG license URL) in addition to the RHCOS marketplace license.

### 6.2 Create VM from the OpenShift Console

Use the console when the boot source is Ready (4.2.7). URL: `https://console-openshift-console.apps.<cluster>.<domain>`.

#### Step 1 — Confirm boot source in the UI

1. Switch to **Administrator** perspective (gear icon → Administrator).
2. **Virtualization** → **Bootable volumes**.
3. Look for **Windows Server 2022** with status **Ready**.

**Expected:** Volume listed as Ready. If the pipeline published to `default` (4.2.7), check project **default** on the Bootable volumes page, or use the CLI path (6.3).

#### Step 2 — Create project

1. **Home** → **Projects** → **Create Project**.
2. Name: `$WINDOWS_PROJECT` → **Create**.

**Expected:** Project `<windows-project>` appears in the namespace dropdown.

#### Step 2b — Cross-namespace RBAC (CLI, before creating the VM)

If `$WIN_BOOTSOURCE_DV` is Ready in namespace **`default`** (4.2.7), run **6.0.1** now. Skip if boot source is in `openshift-virtualization-os-images` and the catalog shows it there.

#### Step 3 — Create VM from catalog

1. **Virtualization** → **Catalog** (or **VirtualMachines** → **Create** → **Create from template**).
2. Filter or select **Windows Server 2022** (template `windows2k22-server-medium` or similar).
3. Click **Quick create** or **Customize VirtualMachine**.

| Field | Value |
|-------|-------|
| Name | `$WINDOWS_VM_NAME` |
| Project / Namespace | `$WINDOWS_PROJECT` |
| Storage class | `hyperdisk-virt-sc` |
| Disk size | **60 GiB** minimum |
| Run strategy | **Always** (start after create) |

4. If the wizard offers **Boot source** / **DataSource**, select `$WIN_BOOTSOURCE_DV`. If it is missing, the boot source is likely in namespace `default` — use section 6.3 CLI instead, or create from **YAML** (step 4 below).

5. Click **Create VirtualMachine**.

**Expected (VirtualMachines list):**

```text
NAME       STATUS        READY
<windows-vm-name>   Provisioning  False
```

Then after 5–15 min (disk clone from `$WIN_BOOTSOURCE_DV`):

```text
NAME       STATUS    READY
<windows-vm-name>   Running   True
```

#### Step 4 — Enable SMM (required for Secure Boot)

The Windows template requires **SMM** enabled for Secure Boot (Step 4 below).

1. **Virtualization** → **VirtualMachines** → project `$WINDOWS_PROJECT` → `$WINDOWS_VM_NAME`.
2. **Actions** (⋮) → **Edit YAML**.
3. Under `spec.template.spec.domain`, add:

```yaml
features:
  smm:
    enabled: true
```

4. **Save**. If the VM already exists, it may restart once.

**Expected (Events tab or VM list):** Status **Running**.

#### Step 5 — Open the guest console

1. **Virtualization** → **VirtualMachines** → `$WINDOWS_VM_NAME` (namespace `$WINDOWS_PROJECT`).
2. Open the **Console** tab (in-browser VNC), or **Actions** → **Open console**.

**Expected:** Windows OOBE / login screen (first boot after clone may take several minutes).

#### Step 6 — Verify node placement (optional)

On the VM details page, check **Scheduling** / **Node** — should be the metal worker (`*-virt-*`, `c3-standard-192-metal`).

**Expected:**

```text
Node: <metal-worker-node-name>
```

### 6.3 Create VM from CLI

After boot source pipeline, create VM from template with **Hyperdisk** and **SMM**.

**Order:** `6.0.1` RBAC (if `WIN_DS_NAMESPACE=default`) → create VM → watch.

```bash
oc new-project "$WINDOWS_PROJECT"

# Cross-namespace clone — run BEFORE oc apply if boot source is in default (section 6.0.1)
oc adm policy add-role-to-user cdi.kubevirt.io:clone-sourcer \
  system:serviceaccount:${WINDOWS_PROJECT}:default \
  -n default

# Cross-namespace clone — run BEFORE oc apply if win2k22 is in default (section 6.0.1)
oc adm policy add-role-to-user cdi.kubevirt.io:clone-sourcer \
  system:serviceaccount:windows-vms:default \
  -n default

oc process windows2k22-server-medium -n openshift \
<<<<<<< Updated upstream
  -p NAME=win-demo \
  -p DATA_SOURCE_NAME=win2k22 \
=======
  -p NAME="${WINDOWS_VM_NAME}" \
  -p DATA_SOURCE_NAME="${WIN_BOOTSOURCE_DV}" \
>>>>>>> Stashed changes
  -p DATA_SOURCE_NAMESPACE="${WIN_DS_NAMESPACE}" \
  -o yaml | python3 -c "
import os, yaml, sys
wp = os.environ['WINDOWS_PROJECT']
hsc = os.environ['HYPERDISK_SC']
docs = list(yaml.safe_load_all(sys.stdin))
for d in docs:
    if d.get('kind') == 'VirtualMachine':
        d['metadata']['namespace'] = wp
        domain = d['spec']['template']['spec']['domain']
        domain.setdefault('features', {})['smm'] = {'enabled': True}
        d['spec']['dataVolumeTemplates'][0]['spec']['storage']['storageClassName'] = hsc
        d['spec']['dataVolumeTemplates'][0]['metadata'].setdefault('annotations', {})['cdi.kubevirt.io/storage.bind.immediate.requested'] = 'true'
print(yaml.dump_all(docs))
" | oc apply -f -

oc patch vm "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" --type merge -p '{"spec":{"runStrategy":"Always"}}'
```

**Expected output:**

```text
<<<<<<< Updated upstream
# oc new-project windows-vms
Now using project "windows-vms" on server "https://api.nddemo...:6443".

# oc apply (from process pipeline)
datavolume.cdi.kubevirt.io/win-demo-rootdisk created
virtualmachine.kubevirt.io/win-demo created

# oc patch ...
virtualmachine.kubevirt.io/win-demo patched
```

```bash
oc get vm,dv -n windows-vms
oc get vmi,pvc -n windows-vms
oc get vmi win-demo -n windows-vms -o wide -w
```

If VM is **Stopped** with `FailedCreate` / clone RBAC error, see **6.0.3**.

**Expected output (healthy):**

```text
NAME       AGE   STATUS    READY
win-demo   5m    Running   True

NAME                  PHASE       PROGRESS   RESTARTS   AGE
win-demo-rootdisk     Succeeded   100.0%                8m

NAME                  STATUS   VOLUME   CAPACITY   STORAGECLASS
win-demo-rootdisk     Bound    pvc-...  60Gi       hyperdisk-virt-sc
```

### 6.4 Connect to the VM

**Console (browser):** **Virtualization** → **VirtualMachines** → `win-demo` → **Console** tab.

**virtctl VNC (local viewer):**
=======
# oc new-project <windows-project>
Now using project "<windows-project>" on server "https://api.<cluster-domain>:6443".

# oc apply (from process pipeline)
datavolume.cdi.kubevirt.io/<windows-root-dv-name> created
virtualmachine.kubevirt.io/<windows-vm-name> created

# oc patch ...
virtualmachine.kubevirt.io/<windows-vm-name> patched
```
>>>>>>> Stashed changes

```bash
oc get vm -n "$WINDOWS_PROJECT"
oc get dv -n "$WINDOWS_PROJECT"
oc get vmi -n "$WINDOWS_PROJECT"
oc get pvc -n "$WINDOWS_PROJECT"
oc get vmi "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" -o wide -w
```

<<<<<<< Updated upstream
=======

**Expected output (healthy):**

```text
NAME       AGE   STATUS    READY
<windows-vm-name>   5m    Running   True

NAME                  PHASE       PROGRESS   RESTARTS   AGE
<windows-root-dv-name>     Succeeded   100.0%                8m

NAME                  STATUS   VOLUME   CAPACITY   STORAGECLASS
<windows-root-dv-name>     Bound    pvc-...  60Gi       hyperdisk-virt-sc
```

### 6.4 Connect to the VM

**Console (browser):** **Virtualization** → **VirtualMachines** → `$WINDOWS_VM_NAME` → **Console** tab.

**virtctl VNC (local viewer):**

```bash
virtctl vnc "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT"
```

>>>>>>> Stashed changes
**Expected output:**

```text
# virtctl vnc opens a local VNC viewer window to the Windows desktop
# (or prints connection URL depending on virtctl version)
```

<<<<<<< Updated upstream
**Expected (guest):** Windows desktop or OOBE; VM **Running** / **Ready=True** in UI or `oc get vm win-demo -n windows-vms`.
=======
**Expected (guest):** Windows desktop or OOBE; VM **Running** / **Ready=True** in UI or `oc get vm <windows-vm-name> -n <windows-project>`.
>>>>>>> Stashed changes

---

## Phase 7 — Verification summary

```bash
echo "=== Metal / KVM ==="
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.devices\.kubevirt\.io/kvm}{"\n"}{end}' | grep 1k

echo "=== Hyperdisk ==="
gcloud compute storage-pools list --project="$GCP_PROJECT" --filter="zone:$GCP_ZONE"
oc get storageclass "$HYPERDISK_SC"

echo "=== Virtualization ==="
oc get hco -n openshift-cnv kubevirt-hyperconverged \
  -o jsonpath='Available={.status.conditions[?(@.type=="Available")].status}{"\n"}'

echo "=== Boot sources ==="
oc get datasource "$LINUX_DATASOURCE" -n openshift-virtualization-os-images \
  -o jsonpath="${LINUX_DATASOURCE}={.status.conditions[?(@.type==\"Ready\")].status}{\" \"}{.status.conditions[?(@.type==\"Ready\")].message}{\"\n\"}" 2>/dev/null || true
oc get datasource "$WIN_BOOTSOURCE_DV" -n "$WIN_DS_NAMESPACE" \
  -o jsonpath="${WIN_BOOTSOURCE_DV}@$WIN_DS_NAMESPACE={.status.conditions[?(@.type==\"Ready\")].status}{\" \"}{.status.conditions[?(@.type==\"Ready\")].message}{\"\n\"}"

echo "=== VMs ==="
oc get vm -A
```

**Expected output (fully working cluster):**

```text
=== Metal / KVM ===
<<<<<<< Updated upstream
nddemo-wq4kd-virt-worker-a-6277p    1k

=== Hyperdisk ===
NAME              ZONE           STATE
nddemo-virt-pool  us-central1-a  READY
=======
<metal-worker-node-name>    1k

=== Hyperdisk ===
NAME              ZONE           STATE
${CLUSTER_NAME}-virt-pool  ${GCP_ZONE}  READY
>>>>>>> Stashed changes

NAME                PROVISIONER            ...
hyperdisk-virt-sc   pd.csi.storage.gke.io  ...

=== Virtualization ===
Available=True

=== Boot sources ===
<<<<<<< Updated upstream
centos-stream9=True
win2k22=True

=== VMs ===
NAMESPACE    NAME         AGE   STATUS    READY
linux-vms    linux-demo   1h    Running   True
windows-vms  win-demo     30m   Running   True
=======
<linux-datasource-name>=True
<windows-bootsource-dv>=True

=== VMs ===
NAMESPACE    NAME         AGE   STATUS    READY
<linux-project>    <linux-vm-name>   1h    Running   True
<windows-project>  <windows-vm-name>     30m   Running   True
>>>>>>> Stashed changes
```

---

## Decision tree

```
OSD cluster (2× N2 workers)
  │
  ├─► Phase 1: Add c3-standard-192-metal pool (same zone as Hyperdisk)
  │
  ├─► Phase 2: Install OpenShift Virtualization
  │
  ├─► Phase 3: Create Hyperdisk pool + hyperdisk-virt-sc  ◄── REQUIRED
  │
  ├─► Linux VM
  │     ├─► Phase 5.2: DV import (registry + hyperdisk-virt-sc) → Succeeded
  │     └─► Phase 5.3: VM + PVC → Running → virtctl ssh
  │
  └─► Windows VM
        ├─► Phase 4: Boot source pipeline → win2k22 Ready (often in default ns)
<<<<<<< Updated upstream
        ├─► Phase 4.2.7: Verify golden DV Succeeded (not blank); do not re-run pipeline
=======
        ├─► Phase 4.2.7: Verify golden DV Succeeded; DataSource Ready
>>>>>>> Stashed changes
        ├─► Phase 6.0: Cross-ns RBAC if win2k22 in default (before creating VM)
        ├─► Phase 6: Console Catalog or CLI template + hyperdisk-virt-sc + SMM → Console / virtctl vnc
        └─► Optional: Phase 6.1 metal boot-disk license
```

---

## Cleanup

```bash
oc delete namespace "$LINUX_PROJECT" "$WINDOWS_PROJECT" --wait=false
oc delete vm "$WINDOWS_VM_NAME" -n default --ignore-not-found

# Optional: remove Hyperdisk pool (destructive — deletes pool capacity billing)
# gcloud compute storage-pools delete "$VIRT_POOL_NAME" \
#   --zone=$GCP_ZONE --project=$GCP_PROJECT
```

**Expected output:**
<<<<<<< Updated upstream

```text
namespace "linux-vms" deleted
namespace "windows-vms" deleted
```

---

## Quick reference: common errors

| Error | Fix |
|-------|-----|
| `Insufficient devices.kubevirt.io/kvm` | Phase 1 — add metal pool |
| `pd-standard disk type cannot be used by c3-standard-192-metal` | Phase 3 — use `hyperdisk-virt-sc` |
| `IncompatibleVolumeModes` | Use registry import, not snapshot DataSource clone |
| Importer stuck `Init:0/1` | Check `describe pod` for attach error; likely wrong StorageClass |
| DV `ImportScheduled` 15+ min | Normal first import; check importer on metal node |
| `Source PVC win2k22 not available` | Phase 4 Windows pipeline |
| VM **Stopped**, `insufficient permissions in clone source namespace default` | Phase **6.0** — grant `cdi.kubevirt.io:clone-sourcer`; toggle Halted→Always |
| `SecureBoot requires SMM` | `features.smm.enabled: true` |
| VM in wrong namespace | `oc get vm -A` |

---

## Terraform all-in-one (greenfield)

```bash
cp configuration/tfvars/terraform.tfvars.openshift-virt.example configuration/tfvars/terraform.tfvars
# gcp_project, clustername, gcp_zone=us-central1-a, enable_openshift_virt=true
make all
=======

```text
namespace "<linux-project>" deleted
namespace "<windows-project>" deleted
>>>>>>> Stashed changes
```


---

## Official references (Phases 2 and 3)

| Topic | Red Hat documentation |
|-------|------------------------|
| Install OpenShift Virtualization on OSD | [OSD 4 — Installing Virtualization](https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/virtualization/installing) |
| Install OpenShift Virtualization (OCP) | [OCP — Installing Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/virtualization/installing) (match your version) |
| Hyperdisk + virt on GCP | [KCS 7139046 — Storage configuration for OpenShift Virtualization 4.21.x on Google Cloud](https://access.redhat.com/articles/7139046) |
| Hyperdisk StorageClass / pools | [OCP 4.21 — GCP PD hyperdisk-balanced procedure](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/storage/persistent-storage-csi-gcp-pd) |
| OSD virt storage overview | [OSD 4 — Virtualization storage](https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/virtualization/storage) |
| GCP Hyperdisk storage pools | [Google Cloud — Hyperdisk storage pools](https://cloud.google.com/compute/docs/disks/hyperdisks-storage-pools) (Phase 3.1) |

