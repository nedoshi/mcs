# OSD on GCP: End-to-End Linux and Windows VM Provisioning

Guide for provisioning Linux and Windows virtual machines on an **existing** OpenShift Dedicated (OSD) cluster on GCP using OpenShift Virtualization.

**Start here:** complete **[Step 0 — Set environment variables](#step-0--set-environment-variables)**, then run each phase in order (copy-paste commands).

**Audience:** Cluster already installed (CCS, WIF or service account). Default workers are **N2** (e.g. `n2-standard-4`). You want Linux + Windows guests (Server **2022** or **2025**).

This runbook is **self-contained** — no git repository or companion files. In **Step 0**, replace every placeholder (e.g. `my-cluster`, not `<cluster-name>`) before pasting commands. For Windows golden images: **Path A** = Tekton pipeline (Eval Center URL), or **Path B** = upload a local ISO from your Mac (no Pipelines operator).

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

# === Linux boot source ===
export LINUX_DATASOURCE=centos-stream9

# === Windows version: set WIN_VERSION to 2022 or 2025 (drives pipeline + Phase 6 template) ===
export WIN_VERSION=2025   # 2022 | 2025
export WIN_BOOTSOURCE_NAMESPACE=openshift-virtualization-os-images
case "$WIN_VERSION" in
  2022)
    export WIN_BOOTSOURCE_DV=win2k22
    export WIN_PREFERENCE=windows.2k22.virtio
    export WIN_AUTOUNATTEND_CM=windows2k22-autounattend
    export WIN_PIPELINE_GENERATE_NAME=windows2k22-installer-run-
    export WIN_TEMPLATE=windows2k22-server-medium
    export WIN_EVAL_URL='https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022'
    ;;
  2025)
    export WIN_BOOTSOURCE_DV=win2k25
    export WIN_PREFERENCE=windows.2k25.virtio
    export WIN_AUTOUNATTEND_CM=windows2k25-autounattend
    export WIN_PIPELINE_GENERATE_NAME=windows2k25-installer-run-
    export WIN_TEMPLATE=windows2k25-server-medium
    export WIN_EVAL_URL='https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025'
    ;;
  *)
    echo "WIN_VERSION must be 2022 or 2025"; return 1 2>/dev/null || exit 1
    ;;
esac

# Where the Windows DataSource is Ready after Phase 4 (hub pipeline often uses default)
export WIN_DS_NAMESPACE=default
# If 4.2.6 shows Ready only in openshift-virtualization-os-images, use instead:
# export WIN_DS_NAMESPACE=openshift-virtualization-os-images

# === Storage + SSH paths ===
export HYPERDISK_SC=hyperdisk-virt-sc
export VIRT_POOL_NAME="${CLUSTER_NAME}-virt-pool"
export STORAGE_POOL_PATH="projects/${GCP_PROJECT}/zones/${GCP_ZONE}/storagePools/${VIRT_POOL_NAME}"
export SSH_KEY="${SSH_KEY:-/tmp/virt-linux}"

# Path A (Tekton): paste Eval Center ISO URL before starting the Windows pipeline
export WIN_IMAGE_DOWNLOAD_URL=''
# Path B (no Pipelines): local ISO on your Mac (after download)
export WIN_ISO_PATH="${WIN_ISO_PATH:-$HOME/Downloads/windows-server.iso}"
export VIRTIO_ISO_PATH="${VIRTIO_ISO_PATH:-$HOME/Downloads/virtio-win.iso}"

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

> **Convention:** **Expected output** blocks use placeholders (`<metal-worker-node-name>`, `<linux-vm-name>`, …). Commands use `$LINUX_VM_NAME`, `$WIN_BOOTSOURCE_DV`, etc. from Step 0. Cluster names/ages will differ. Run **`oc get` with one resource type per command** (e.g. `oc get vm` then `oc get dv` — not `oc get vm,dv`).

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
ocm create machinepool "$METAL_POOL_ID" \
  --cluster "$CLUSTER_ID" \
  --replicas 1 \
  --instance-type c3-standard-192-metal
```

**Expected output:**

```text
# export CLUSTER_ID=...
# (no output if single match)

# ocm create machinepool ...
{
  "id": "<metal-pool-id>",
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
<metal-worker-node-name>    1k

# gcloud compute instances list ...
NAME                                        ZONE           MACHINE_TYPE              STATUS
<metal-worker-node-name>            ${GCP_ZONE}  c3-standard-192-metal     RUNNING
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

Wait until HCO reports **Available** (see Verify below). For extra waits, StorageProfile patches, or 4.21 VolumeSnapshotClass setup, use the Red Hat installing guide linked under [Official references](#official-references).

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
<virt-operator-csv-name>    OpenShift Virtualization          <virt-version>              Succeeded
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
Created [https://www.googleapis.com/compute/v1/projects/${GCP_PROJECT}/zones/${GCP_ZONE}/storagePools/${CLUSTER_NAME}-virt-pool].
```

> **Note:** `gcloud` uses `--provisioned-capacity` (e.g. `10TB`), not `--pool-provisioned-capacity-gb`. Terraform uses `pool_provisioned_capacity_gb = 10240` for the same 10 TiB minimum.

Verify:

```bash
gcloud compute storage-pools describe "$VIRT_POOL_NAME" \
  --zone="$GCP_ZONE" \
  --project="$GCP_PROJECT" \
  --format='yaml(name,zone,state,poolProvisionedCapacityGb,poolProvisionedIops,poolProvisionedThroughput)'
```

**Expected output:**

```text
name: ${CLUSTER_NAME}-virt-pool
poolProvisionedCapacityGb: '10240'
poolProvisionedIops: '10000'
poolProvisionedThroughput: '1024'
state: READY
zone: https://www.googleapis.com/compute/v1/projects/${GCP_PROJECT}/zones/${GCP_ZONE}
```

**Pass:** `state: READY`; capacity ≥ 10240 GiB; zone matches `GCP_ZONE`.

**Cost note:** You provision 10 TiB of pool capacity even if VMs use less. Tune IOPS/throughput only if needed.

### 3.2 Create OpenShift StorageClass `hyperdisk-virt-sc`

Uses `$STORAGE_POOL_PATH` and `$HYPERDISK_SC` from Step 0. **Do not** add `provisioned-iops-on-create` / `provisioned-throughput-on-create` — leave IOPS size-driven (needed for 9 Gi pipeline disks).

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
oc patch storageprofile "${HYPERDISK_SC}" --type=merge -p \
  '{"spec":{"claimPropertySets":[{"accessModes":["ReadWriteOnce"],"volumeMode":"Filesystem"}]}}'
oc get storageclass "${HYPERDISK_SC}"
```

**Pass:** `hyperdisk-virt-sc` exists; provisioner `pd.csi.storage.gke.io`; type `hyperdisk-balanced`; pool path matches `$STORAGE_POOL_PATH`.

### 3.3 Verify with a 9 Gi Hyperdisk PVC

`WaitForFirstConsumer` — PVC stays **Pending** until a consumer pod schedules. Apply PVC + pod together:

```bash
oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hyperdisk-9gi-test
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ${HYPERDISK_SC}
  resources:
    requests:
      storage: 9Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: hyperdisk-9gi-test-pod
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
        claimName: hyperdisk-9gi-test
EOF
oc get pvc hyperdisk-9gi-test -n default -w
```

**Pass:** PVC reaches `Bound` at **9Gi** on `hyperdisk-virt-sc`. Then cleanup:

```bash
oc delete pod hyperdisk-9gi-test-pod -n default --ignore-not-found
oc delete pvc hyperdisk-9gi-test -n default --ignore-not-found
```

### 3.4 Terraform alternative (new clusters)

Set in `terraform.tfvars` before `make all` (see [terraform.tfvars.openshift-virt.example](../configuration/tfvars/terraform.tfvars.openshift-virt.example)):

```hcl
enable_openshift_virt          = true
gcp_zone                       = "us-central1-a"   # same zone as metal workers
hyperdisk_pool_capacity_gb     = 10240
hyperdisk_pool_iops            = 10000
hyperdisk_pool_throughput_mbps = 1024
```

Terraform creates the pool; still create/verify `hyperdisk-virt-sc` as in **3.2** if the install script did not.

---

## Phase 4 — Golden images (boot sources)

### Linux — auto-imported (for DataSource reference only)

```bash
oc get datasource "$LINUX_DATASOURCE" -n openshift-virtualization-os-images \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
```

**Expected output:**

```text
True
```

**Do not** clone from this DataSource via snapshot onto metal without Hyperdisk — use the registry import in Phase 5 instead.

### Windows — NOT auto-imported

Pick a path:

| Path | When | Needs OpenShift Pipelines? |
|------|------|----------------------------|
| **[A] Tekton `windows-efi-installer`](#path-a--tekton-windows-efi-installer-pipeline)** | Cluster can pull the Eval Center ISO URL; you want unattended golden image | **Yes** (section 4.1) |
| **[B] Local ISO from Mac`](#path-b--local-iso-on-mac-no-pipelines-operator)** | ISO already downloaded; no Pipelines operator / no outbound ISO fetch | **No** |

Set `WIN_VERSION=2022` or `2025` in Step 0 first — that drives `WIN_BOOTSOURCE_DV`, preference, autounattend ConfigMap, PipelineRun name, and Phase 6 template.

```bash
oc get datasource "$WIN_BOOTSOURCE_DV" -n openshift-virtualization-os-images \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{" "}{.status.conditions[?(@.type=="Ready")].message}{"\n"}'
```

**Expected output (before Path A/B):**

```text
False PVC not found
```

**Expected output (after Path A/B succeeds):**

```text
True
```

---

### Path A — Tekton `windows-efi-installer` pipeline

#### 4.1 Install OpenShift Pipelines

Install the **Red Hat OpenShift Pipelines** Operator **once** — console **or** CLI from the official doc, not both (re-applying a Subscription/OperatorGroup after OperatorHub install causes CRD / OLM conflicts).

- [Installing OpenShift Pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.22/html/installing_and_configuring/installing-pipelines) (match the Pipelines version channel for your cluster)

Verify only:

```bash
oc get csv -A | grep -i pipelines
oc get tektonconfig config -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
```

**Expected output:**

```text
# oc get csv -A | grep -i pipelines
openshift-operators   <pipelines-operator-csv-name>   ...   Succeeded

# oc get tektonconfig ...
True
```

**Pass:** CSV `PHASE=Succeeded` and `TektonConfig` Ready=`True`. Then continue — do **not** create another Subscription.

#### 4.2 Windows Server boot-source pipeline (2022 or 2025)

The `windows-efi-installer` Tekton pipeline downloads a Microsoft ISO, runs an unattended install inside a temporary VM, sysprep-generalizes the disk, and publishes the **`$WIN_BOOTSOURCE_DV`** golden image. Expect **30–90 minutes** on Hyperdisk/metal.

| `WIN_VERSION` | `preferenceName` | `autounattendConfigMapName` | `baseDvName` / `isoDVName` | Eval Center |
|---------------|------------------|-----------------------------|----------------------------|-------------|
| `2022` | `windows.2k22.virtio` | `windows2k22-autounattend` | `win2k22` | [Server 2022](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022) |
| `2025` | `windows.2k25.virtio` | `windows2k25-autounattend` | `win2k25` | [Server 2025](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025) |

Do **not** mix versions (e.g. 2025 ISO with `windows2k22-autounattend`) — VirtIO driver paths differ (`2k22` vs `2k25`).

**Prerequisites (in addition to Phase 1 metal + Phase 3 Hyperdisk):**

- OpenShift Pipelines installed and Ready (section 4.1)
- A **C3 metal** worker with KVM (the installer VM cannot run on N2)
- On C3 metal, pipeline temp disks must use **Hyperdisk** — set `hyperdisk-virt-sc` as the default StorageClass before starting (revert afterward if you prefer):

```bash
oc patch storageclass "$HYPERDISK_SC" --type merge -p \
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

##### 4.2.1 Grant SCC to the pipeline ServiceAccount

The `modify-windows-iso-file` task must run as UID/GID **107**:

```bash
oc adm policy add-scc-to-user anyuid -z pipeline -n default
```

**Expected output:**

```text
clusterrole.rbac.authorization.k8s.io/system:openshift:scc:anyuid added: "pipeline"
```

##### 4.2.2 Obtain the Windows Server ISO URL

1. Open `$WIN_EVAL_URL` (from Step 0 — 2022 or 2025 Eval Center)
2. Register / sign in, continue to download
3. Select **English (United States)** — **64-bit** ISO
4. **Right-click** the Download button → **Copy link address** (do not click through; the URL expires in ~24 h)

```bash
# Paste the copied URL (must be en-US x64 matching WIN_VERSION)
export WIN_IMAGE_DOWNLOAD_URL='https://go.microsoft.com/fwlink/?linkid=...'  # overwrites Step 0 placeholder
test -n "$WIN_IMAGE_DOWNLOAD_URL" && echo "ISO URL set (${#WIN_IMAGE_DOWNLOAD_URL} chars) for WIN_VERSION=$WIN_VERSION"
```

**Expected output:**

```text
ISO URL set (142 chars) for WIN_VERSION=2025
```

##### 4.2.3 Match pipeline version to cluster

Uses `$PIPELINE_VERSION` from Step 0 (must match OpenShift **major.minor**):

```bash
echo "Using pipeline version: $PIPELINE_VERSION"
```

**Expected output:**

```text
Using pipeline version: v<major>.<minor>.0
```

Hub pipeline tag must match cluster OpenShift **major.minor** — see [ArtifactHub windows-efi-installer](https://artifacthub.io/packages/tekton-pipeline/redhat-pipelines/windows-efi-installer).

##### 4.2.4 Start the PipelineRun

Confirm the ISO URL and version exports are set, then create the PipelineRun:

```bash
test -n "$WIN_IMAGE_DOWNLOAD_URL" || { echo "Set WIN_IMAGE_DOWNLOAD_URL (Step 0 / 4.2.2)"; exit 1; }
echo "WIN_VERSION=$WIN_VERSION WIN_BOOTSOURCE_DV=$WIN_BOOTSOURCE_DV preference=$WIN_PREFERENCE"
```

Run in **`default`** (Tekton creates the `pipeline` ServiceAccount there). Parameters target `$WIN_BOOTSOURCE_DV`:

| Parameter | Value (from Step 0) |
|-----------|---------------------|
| `preferenceName` | `$WIN_PREFERENCE` |
| `autounattendConfigMapName` | `$WIN_AUTOUNATTEND_CM` (shipped with the pipeline) |
| `baseDvName` / `isoDVName` | `$WIN_BOOTSOURCE_DV` |
| `baseDvNamespace` | `$WIN_BOOTSOURCE_NAMESPACE` |
| `acceptEula` | `"true"` — you accept Microsoft’s license for this install |

```bash
oc create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: ${WIN_PIPELINE_GENERATE_NAME}
  namespace: default
spec:
  params:
    - name: winImageDownloadURL
      value: "${WIN_IMAGE_DOWNLOAD_URL}"
    - name: acceptEula
      value: "true"
    - name: preferenceName
      value: "${WIN_PREFERENCE}"
    - name: autounattendConfigMapName
      value: "${WIN_AUTOUNATTEND_CM}"
    - name: baseDvName
      value: "${WIN_BOOTSOURCE_DV}"
    - name: baseDvNamespace
      value: "${WIN_BOOTSOURCE_NAMESPACE}"
    - name: isoDVName
      value: "${WIN_BOOTSOURCE_DV}"
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
        value: "${PIPELINE_VERSION}"
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
pipelinerun.tekton.dev/<pipelinerun-name> created
```

> **Note:** `modify-windows-iso-file` defaults to a **1h** per-task timeout. On Hyperdisk/metal, guestfish extract/repack of the ~5–7 GiB ISO often exceeds that — you will see `TaskRunTimeout` even though the task was still working. The `timeout: 2h0m0s` override above fixes this; bump to `3h0m0s` if it times out again. `timeouts.pipeline: 4h0m0s` covers the full install.

**2025 example (same YAML — Step 0 already set these):** `generateName=windows2k25-installer-run-`, `preferenceName=windows.2k25.virtio`, `autounattendConfigMapName=windows2k25-autounattend`, `baseDvName`/`isoDVName`=`win2k25`.

##### 4.2.4a What the pipeline deletes (and what it keeps)

The `finally` block **always** runs after success or failure:

| Task | Deleted | Purpose |
|------|---------|---------|
| `delete-imported-iso` | ISO DataVolume/PVC (`$WIN_BOOTSOURCE_DV-xxxxx`) | Temp download — not needed after install |
| `cleanup-vm` | Installer VM (`windows-efi-xxxxx`) | Temp VM that ran Windows Setup |
| `delete-vm-rootdisk` | Installer scratch root disk | Source disk after clone to golden image |

**This is normal.** You do **not** run guest VMs from the ISO or the installer VM.

**What you keep:** the **`$WIN_BOOTSOURCE_DV`** golden-image DataVolume + DataSource (cloned installed disk). That is what Phase 6 clones for `$WINDOWS_VM_NAME`.

##### 4.2.4b Run only ONE pipeline at a time

Every run uses the same names (`$WIN_BOOTSOURCE_DV`, `$WIN_BOOTSOURCE_DV-*`, `windows-efi-*`). A second PipelineRun while one is running or after one succeeded will **overwrite or corrupt** the first run's golden image.

| Do | Don't |
|----|-------|
| Wait for `pipelinerun ... Succeeded` | Start a second pipeline "just in case" |
| Let `wait-for-vmi-status` finish (20–40 min) | Cancel a healthy run because ISO was deleted |
| Proceed to Phase 6 after boot source Ready | Re-run the pipeline after success |

If you already started a second run by mistake:

```bash
# Only cancel the NEWER run if the older one already Succeeded and you haven't lost the golden image
oc get pipelinerun -n default --sort-by=.metadata.creationTimestamp

# Cancel the in-progress duplicate (replace name):
oc delete pipelinerun windows2k25-installer-run-NEWER -n default
# or, if tkn is installed:
# tkn pipelinerun cancel windows2k25-installer-run-NEWER -n default
```

If the second run already replaced `$WIN_BOOTSOURCE_DV` with a `blank` DataVolume, the first golden image is gone — let the **current** run finish; do not start a third.

##### 4.2.5 Monitor progress

```bash
# Refresh every 2 minutes (one resource type per oc get).
# Mac: `brew install watch` or use the while-loop below.
watch -n 120 'date; oc get pipelinerun -n default; oc get taskrun -n default; echo; oc get vmi -n default; oc get vm -n default' \
  2>/dev/null || while true; do date; oc get pipelinerun -n default; oc get taskrun -n default; echo; oc get vmi -n default; oc get vm -n default; sleep 120; done

# Boot source Ready (run separately):
oc get datasource "$WIN_BOOTSOURCE_DV" -n default \
  -o jsonpath='default Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}' 2>/dev/null || true
oc get datasource "$WIN_BOOTSOURCE_DV" -n openshift-virtualization-os-images \
  -o jsonpath='os-images Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}' 2>/dev/null || true

# Or live stream (one type per command):
oc get pipelinerun -n default -w

# Temporary installer resources (default namespace)
oc get dv -n default | grep -E "$WIN_BOOTSOURCE_DV|windows-efi"
oc get pvc -n default | grep -E "$WIN_BOOTSOURCE_DV|windows-efi"
oc get vm -n default | grep -E "$WIN_BOOTSOURCE_DV|windows-efi"
oc get vmi -n default | grep -E "$WIN_BOOTSOURCE_DV|windows-efi"

# Golden image DV (final artifact — check BOTH namespaces; see 4.2.6)
oc get dv "$WIN_BOOTSOURCE_DV" -n default -o wide
oc get dv "$WIN_BOOTSOURCE_DV" -n openshift-virtualization-os-images -o wide 2>/dev/null || true
```

**Expected output — task progression:**

```text
# Early (~5–15 min): ISO import + modify
NAME                                                    SUCCEEDED   REASON      STARTTIME   COMPLETIONTIME
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

# oc get dv <windows-bootsource-dv> -n default
NAME                      PHASE       PROGRESS   RESTARTS   AGE
<windows-bootsource-dv>   Succeeded   100.0%                48m

# Installer VM gone after cleanup — expected:
# oc get vm -n default
No resources found
```

**Healthy progression:** `import-win-iso` → `modify-windows-iso-file` → `windows-efi-*` installer VM **Running** on metal → VM shuts down after sysprep → `create-datasource-root-disk` → **finally** deletes ISO + installer VM → `$WIN_BOOTSOURCE_DV` golden DV **Succeeded**.

**Installer VM healthy (mid-run):**

```text
# oc get vmi -n default
NAME                  PHASE       NODE                         READY
<installer-vmi-name>  Scheduled   <metal-worker-node-name>     False

# oc get pvc -n default | grep -E 'persistent-state|<windows-bootsource-dv>'
persistent-state-for-<installer-vmi-name>   Bound   ...   4Gi     hyperdisk-virt-sc
<windows-bootsource-dv>                     Bound   ...   22Gi    hyperdisk-virt-sc
```

**Bad signs:**

```text
# modify-windows-iso-file Pending 60+ min → PVC/IOPS issue
modify-windows-iso-file   Unknown   Pending   60m

# windows-efi-* Starting 10+ min + virt-launcher Pending → EFI state PVC failed
virt-launcher-windows-efi-xxxxx   0/3   Pending   0   10m
```

If a task fails, inspect logs:

```bash
PR=$(oc get pipelinerun -n default --sort-by=.metadata.creationTimestamp -o name | tail -1)
PR_NAME=${PR#pipelinerun.tekton.dev/}
oc describe pipelinerun "$PR_NAME" -n default

# TaskRun is not a Pod — use tkn, or logs from the pipeline pods:
tkn pipelinerun logs "$PR_NAME" -n default 2>/dev/null \
  || oc logs -n default -l "tekton.dev/pipelineRun=$PR_NAME" --all-containers --tail=100
```

##### 4.2.6 Verify boot source (check both namespaces)

Even when `baseDvNamespace=openshift-virtualization-os-images` is set on the PipelineRun, the hub pipeline (4.21.x) often publishes the golden image in **`default`**. Check both before Phase 6.

```bash
oc get pipelinerun -n default \
  -o jsonpath='{range .items[*]}{.metadata.name}{"  Succeeded="}{.status.conditions[?(@.type=="Succeeded")].status}{"  "}{.status.conditions[?(@.type=="Succeeded")].reason}{"\n"}{end}'

# Golden image DV — usable vs destroyed
oc get dv "$WIN_BOOTSOURCE_DV" -n default -o jsonpath='ns=default phase={.status.phase} source={.spec.source}{"\n"}'
oc get dv "$WIN_BOOTSOURCE_DV" -n openshift-virtualization-os-images -o jsonpath='ns=os-images phase={.status.phase} source={.spec.source}{"\n"}' 2>/dev/null || echo 'ns=os-images (not found)'

# DataSource Ready in both namespaces
oc get datasource "$WIN_BOOTSOURCE_DV" -n default \
  -o jsonpath='default: Ready={.status.conditions[?(@.type=="Ready")].status} msg={.status.conditions[?(@.type=="Ready")].message}{"\n"}'
oc get datasource "$WIN_BOOTSOURCE_DV" -n openshift-virtualization-os-images \
  -o jsonpath='os-images: Ready={.status.conditions[?(@.type=="Ready")].status} msg={.status.conditions[?(@.type=="Ready")].message}{"\n"}'
```

**Expected output — usable golden image (proceed to Phase 6):**

```text
# oc get pipelinerun ...
NAME                 SUCCEEDED   REASON
<pipelinerun-name>   True        Succeeded

# Golden DV — must be Succeeded with PVC clone source, NOT blank:
ns=default phase=Succeeded source={"pvc":{"name":"<windows-bootsource-dv>","namespace":"default"}}

default: Ready=True msg=
os-images: Ready=False msg=PVC not found
```

Set `export WIN_DS_NAMESPACE=default` (Step 0) when the Ready DataSource is in `default`.

**Expected output — golden image destroyed (re-run pipeline once, do not overlap runs):**

```text
ns=default phase=PendingPopulation source={"blank":{}}
default: Ready=False msg=Import DataVolume phase PendingPopulation
```

A second PipelineRun overwrote `$WIN_BOOTSOURCE_DV` with a blank installer root disk. Delete partial artifacts (4.2.7), run **one** new PipelineRun, wait for `Succeeded`.

**Expected output — both namespaces (ideal, less common on 4.21 hub pipeline):**

```text
ns=os-images phase=Succeeded source={"pvc":{...}}
os-images: Ready=True msg=
```

Use `export WIN_DS_NAMESPACE=openshift-virtualization-os-images` in Phase 6.

**Pass:** PipelineRun `Succeeded`; `$WIN_BOOTSOURCE_DV` DataVolume **Succeeded** with PVC source; DataSource **Ready=True** in at least one namespace.

Console: **Virtualization → Bootable volumes** — **Windows Server 2022** or **2025** may appear under the namespace where the DataSource is Ready.

##### 4.2.7 Cleanup failed or duplicate pipeline run

**Only use this when a run Failed**, or to remove artifacts from a **duplicate** run after canceling it. **Do not** delete `$WIN_BOOTSOURCE_DV` after a **Succeeded** pipeline — that is your boot source.

```bash
# Cancel/delete the failed or duplicate run (replace name):
oc delete pipelinerun <pipelinerun-name> -n default --ignore-not-found
# or: tkn pipelinerun cancel <pipelinerun-name> -n default

# delete stuck installer VM by name if needed:
# oc get vm -n default | grep windows-efi
# oc delete vm windows-efi-xxxxx -n default

# list leftover pipeline PVCs/DVs (ISO imports $WIN_BOOTSOURCE_DV-xxxxx, NOT golden if Succeeded)
oc get pvc -n default
oc get dv -n default
# oc delete dv <iso-dv-name> -n default --ignore-not-found
# oc delete pvc <iso-pvc-name> -n default --ignore-not-found

# Only delete $WIN_BOOTSOURCE_DV itself if verify (4.2.6) shows source=blank / pipeline never succeeded:
# oc delete dv "$WIN_BOOTSOURCE_DV" -n default
# oc delete pvc "$WIN_BOOTSOURCE_DV" -n default
```

**Expected output:**

```text
pipelinerun.tekton.dev "<pipelinerun-name>" deleted
virtualmachine.kubevirt.io "<installer-vm-name>" deleted
```

(Optional) Restore previous default StorageClass:

```bash
oc patch storageclass standard-csi --type merge -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
oc patch storageclass "$HYPERDISK_SC" --type merge -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

**Expected output:**

```text
storageclass.storage.k8s.io/standard-csi patched
storageclass.storage.k8s.io/hyperdisk-virt-sc patched
```

Common failures on GCP metal:

| Symptom | Fix |
|---------|-----|
| `pd-standard disk type cannot be used by c3-standard-192-metal` | Set `$HYPERDISK_SC` as default SC (top of 4.2) |
| `guestfish: ... Permissions denied` in `modify-windows-iso-file` | Re-apply `anyuid` SCC (4.2.1) and `taskRunSpecs` with `runAsUser: 107` |
| ISO download HTTP error | URL expired — generate a new link from Eval Center |
| `acceptEula` / pipeline exits immediately | Set `acceptEula: "true"` |
| `modify-windows-iso-file` **Pending** then **TaskRunTimeout** | Usually **PVC never bound**, not slow guestfish. `oc describe pvc -n default` → `provisioned IOPS is too high` — recreate `$HYPERDISK_SC` **without** fixed IOPS (Phase 3) |
| `windows-efi-*` VM stuck **Starting** / virt-launcher **Pending** | KubeVirt EFI state PVC is **4 Gi** — fails with fixed 3000+ IOPS. Same SC fix; delete stuck VM/PVC and re-run pipeline |
| `modify-windows-iso-file` **TaskRunTimeout** while **Running** | Guestfish still working — keep `timeout: 2h0m0s` under `taskRunSpecs`; set `timeouts.pipeline: 4h0m0s` |
| Pipeline **Succeeded** but ISO / installer VM **deleted** | Expected — golden image is `$WIN_BOOTSOURCE_DV` DV; verify 4.2.6 |
| Second pipeline overwrote DV with `source=blank` | Cancel duplicate run; let current run finish or re-run once (4.2.4b) |
| `Source PVC ... not available` on VM | DataSource not Ready or wrong `WIN_DS_NAMESPACE` — use `default` if pipeline put boot source there (4.2.6) |
| VM **Stopped** — `insufficient permissions in clone source namespace default` | Phase **6.0** — RBAC + Halted→Always toggle |

---

### Path B — Local ISO on Mac (no Pipelines operator)

Use this when you already have the Windows ISO on your Mac (or jump host) and **do not** want OpenShift Pipelines. Manual install + sysprep; longer hands-on time, same Phase 6 afterward.

**Prerequisites:** Phase 1 metal + Phase 3 Hyperdisk; `oc` + `virtctl` on the Mac; ISO downloaded locally.

##### 4.3.1 Confirm local files

```bash
# Windows Server ISO (2022 or 2025 — must match WIN_VERSION / preference you will use)
ls -lh "$WIN_ISO_PATH"

# VirtIO drivers ISO (required so Setup sees the disk)
# https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
ls -lh "$VIRTIO_ISO_PATH"
```

**Expected output:**

```text
-rw-r--r--  1 you  staff   5.7G  ...  windows-server.iso
-rw-r--r--  1 you  staff   600M  ...  virtio-win.iso
```

##### 4.3.2 Upload ISOs with `virtctl image-upload`

`$HYPERDISK_SC` must be default (or pass `--storage-class`). Upload from the Mac terminal (CDI uploadproxy must be reachable — typically via cluster API / VPN / `oc` login already working):

```bash
# Windows installer ISO (~6–8 Gi PVC)
virtctl image-upload dv "${WIN_BOOTSOURCE_DV}-iso" \
  --namespace=default \
  --size=10Gi \
  --image-path="$WIN_ISO_PATH" \
  --storage-class="$HYPERDISK_SC" \
  --access-mode=ReadWriteOnce \
  --force-bind \
  --insecure

# VirtIO drivers ISO
virtctl image-upload dv virtio-win-iso \
  --namespace=default \
  --size=1Gi \
  --image-path="$VIRTIO_ISO_PATH" \
  --storage-class="$HYPERDISK_SC" \
  --access-mode=ReadWriteOnce \
  --force-bind \
  --insecure
```

**Expected output (abbreviated):**

```text
PVC default/<windows-bootsource-dv>-iso created
waiting for PVC ... to be bound...
Uploading data to https://cdi-uploadproxy-openshift-cnv.apps.<cluster-domain>
...
Uploading ... completed successfully
```

If upload fails on TLS, keep `--insecure`. If the uploadproxy route is unreachable from the Mac, run the same commands from a bastion that can reach the cluster apps domain, or use Console → **Virtualization** → upload to PVC.

##### 4.3.3 Create installer VM (blank disk + both CD-ROMs)

```bash
oc apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: windows-manual-install
  namespace: default
spec:
  runStrategy: Always
  template:
    metadata:
      labels:
        kubevirt.io/domain: windows-manual-install
    spec:
      domain:
        cpu:
          cores: 4
          sockets: 1
          threads: 1
        memory:
          guest: 8Gi
        firmware:
          bootloader:
            efi:
              secureBoot: true
        features:
          smm:
            enabled: true
          acpi: {}
          apic: {}
          hyperv:
            relaxed: {}
            vapic: {}
            spinlocks:
              spinlocks: 8191
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
              bootOrder: 2
            - name: winiso
              cdrom:
                bus: sata
              bootOrder: 1
            - name: virtioiso
              cdrom:
                bus: sata
          interfaces:
            - name: default
              masquerade: {}
              model: e1000e
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          dataVolume:
            name: windows-manual-install-root
        - name: winiso
          persistentVolumeClaim:
            claimName: ${WIN_BOOTSOURCE_DV}-iso
        - name: virtioiso
          persistentVolumeClaim:
            claimName: virtio-win-iso
  dataVolumeTemplates:
    - metadata:
        name: windows-manual-install-root
        annotations:
          cdi.kubevirt.io/storage.bind.immediate.requested: "true"
      spec:
        storage:
          storageClassName: ${HYPERDISK_SC}
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 60Gi
        source:
          blank: {}
EOF
```

**Expected output:**

```text
virtualmachine.kubevirt.io/windows-manual-install created
```

```bash
oc get vmi windows-manual-install -n default -o wide -w
```

**Expected:** `PHASE=Running` on `<metal-worker-node-name>`.

##### 4.3.4 Install Windows (VNC) + VirtIO + guest agent + Sysprep

```bash
# Mac: use --proxy-only (see Phase 6.4) or Console → Console tab
virtctl vnc --proxy-only windows-manual-install -n default
# or: virtctl vnc windows-manual-install -n default   # needs TigerVNC installed
```

1. Boot from the Windows ISO; when Setup cannot find a disk, load **viostor** from the VirtIO CD (`E:\viostor\2k25\amd64` for 2025, `E:\viostor\2k22\amd64` for 2022).
2. Complete Server install (Standard Desktop Experience or Core — your choice).
3. After first login, install **VirtIO guest tools** (`virtio-win-gt-x64.msi`) and **QEMU guest agent** from the VirtIO ISO.
4. Optionally install NetKVM / balloon drivers if not covered by the MSI.
5. Run **Sysprep** generalize + shutdown:

```powershell
# Inside the guest (PowerShell as Administrator)
C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
```

**Expected:** Guest powers off; `oc get vmi windows-manual-install -n default` → no resources / VM **Stopped**.

##### 4.3.5 Publish golden DataSource from the root PVC

```bash
# Ensure VM is stopped before cloning the PVC
oc patch vm windows-manual-install -n default --type merge -p '{"spec":{"runStrategy":"Halted"}}'
oc delete vmi windows-manual-install -n default --ignore-not-found

# Clone root disk into the cluster boot-source name (default ns — matches Path A common outcome)
oc apply -f - <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ${WIN_BOOTSOURCE_DV}
  namespace: default
  annotations:
    cdi.kubevirt.io/storage.bind.immediate.requested: "true"
spec:
  source:
    pvc:
      namespace: default
      name: windows-manual-install-root
  storage:
    storageClassName: ${HYPERDISK_SC}
    resources:
      requests:
        storage: 60Gi
---
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataSource
metadata:
  name: ${WIN_BOOTSOURCE_DV}
  namespace: default
spec:
  source:
    pvc:
      name: ${WIN_BOOTSOURCE_DV}
      namespace: default
EOF

export WIN_DS_NAMESPACE=default
oc get dv "$WIN_BOOTSOURCE_DV" -n default -w
oc get datasource "$WIN_BOOTSOURCE_DV" -n default \
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}'
```

**Expected output:**

```text
# oc get dv ...
NAME                      PHASE       PROGRESS   AGE
<windows-bootsource-dv>   Succeeded   100.0%     10m

Ready=True
```

**Pass:** Same as Path A verify — `$WIN_BOOTSOURCE_DV` Ready in `$WIN_DS_NAMESPACE`. Proceed to Phase 6. You can delete `windows-manual-install` VM + ISO DVs afterward to reclaim space; **keep** the golden `$WIN_BOOTSOURCE_DV` DV/PVC.

```bash
# Optional cleanup of installer artifacts (keep golden image)
oc delete vm windows-manual-install -n default --ignore-not-found
oc delete dv "${WIN_BOOTSOURCE_DV}-iso" virtio-win-iso -n default --ignore-not-found
# Do NOT delete dv/"$WIN_BOOTSOURCE_DV" — that is the golden image
```

---

#### 4.4 (Optional) Private Google Access

```bash
gcloud compute networks subnets update "$WORKER_SUBNET" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --enable-private-ip-google-access
```

**Expected output:**

```text
Updated [https://www.googleapis.com/compute/v1/projects/${GCP_PROJECT}/regions/${GCP_REGION}/subnetworks/${WORKER_SUBNET}].
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

```bash
oc get dv "$LINUX_DV_NAME" -n "$LINUX_PROJECT" -o jsonpath='{.status.phase}{"\n"}'
oc get pvc "$LINUX_DV_NAME" -n "$LINUX_PROJECT"
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
importer-<linux-dv-name>-xxxxx    1/1     Running   0          8m
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
virtualmachine.kubevirt.io/<linux-vm-name> created
```

Watch (2–5 min after DV Succeeded):

```bash
oc get vm "$LINUX_VM_NAME" -n "$LINUX_PROJECT" -w
oc get vmi "$LINUX_VM_NAME" -n "$LINUX_PROJECT" -o wide
```

**Expected output:**

```text
# oc get vm ...
NAME         AGE   STATUS    READY
<linux-vm-name>   2m    Running   True

# oc get vmi ... -o wide
NAME         AGE   PHASE     IP            NODE                               READY
<linux-vm-name>   2m    Running   <guest-ip>    <metal-worker-node-name>   True
```

**Pass:** `NODE` is the metal worker (`*-virt-*` or `c3-standard-192-metal`); `READY=True`.

### 5.4 SSH test

```bash
virtctl ssh "centos@${LINUX_VM_NAME}" -n "$LINUX_PROJECT" \
  -i "$SSH_KEY" \
  --local-ssh-opts="-o StrictHostKeyChecking=accept-new" \
  --command "hostname"
```

**Expected output:**

```text
<linux-vm-name>
```

**Pass:** prints guest hostname (matches `<linux-vm-name>`).

---

## Phase 6 — Windows VM

**Prerequisites:** Phase 4 Path A or B **Succeeded**; `$WIN_BOOTSOURCE_DV` DataSource **Ready=True**; `$HYPERDISK_SC` exists.

**Order (do not skip):**
1. Confirm boot source Ready
2. **6.0** RBAC (if boot source is in `default`)
3. **Create** the VM — **6.2** (console) or **6.3** (CLI)
4. Watch until Running — **6.4**
5. Only if VM exists but is **Stopped** with clone RBAC errors → **6.5**

```bash
echo "WINDOWS_VM_NAME=$WINDOWS_VM_NAME WINDOWS_PROJECT=$WINDOWS_PROJECT"
echo "WIN_BOOTSOURCE_DV=$WIN_BOOTSOURCE_DV WIN_DS_NAMESPACE=$WIN_DS_NAMESPACE"

oc get datasource "$WIN_BOOTSOURCE_DV" -n "$WIN_DS_NAMESPACE" \
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}'
```

**Expected output:**

```text
Ready=True
```

If that prints `False` / NotFound, finish Phase 4 first. Do **not** run `oc patch vm` yet — the VM does not exist until **6.2** or **6.3**.

### 6.0 Cross-namespace clone RBAC (before create, when `WIN_DS_NAMESPACE=default`)

The boot-source pipeline often publishes `$WIN_BOOTSOURCE_DV` in **`default`**, while the guest VM lives in **`$WINDOWS_PROJECT`**. Grant clone permission **before** creating the VM.

```bash
# Ensure destination project exists first (creates the default SA)
oc new-project "$WINDOWS_PROJECT" 2>/dev/null || true

oc get clusterrole cdi.kubevirt.io:clone-sourcer

# If missing on older CNV, create it once:
oc apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cdi.kubevirt.io:clone-sourcer
rules:
  - apiGroups: ["cdi.kubevirt.io"]
    resources: ["datavolumes/source"]
    verbs: ["create"]
EOF

oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: allow-clone-from-default
  namespace: default
subjects:
  - kind: ServiceAccount
    name: default
    namespace: ${WINDOWS_PROJECT}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cdi.kubevirt.io:clone-sourcer
EOF

oc auth can-i create datavolumes.cdi.kubevirt.io \
  --subresource=source \
  --as="system:serviceaccount:${WINDOWS_PROJECT}:default" \
  -n default
```

**Expected output:**

```text
rolebinding.rbac.authorization.k8s.io/allow-clone-from-default created
yes
```

Skip 6.0 if `WIN_DS_NAMESPACE=openshift-virtualization-os-images` and you create the VM from that catalog entry.

### 6.1 (Optional) GCP Windows PAYG license on metal node

**Not required** for guest VMs from the golden image (eval/BYOL ISO). Skip unless you use **Google PAYG Windows** on the metal worker.

When you opt in:

- Tag goes on the **metal worker RHCOS boot disk**, not guest PVCs
- PAYG applies to the **entire** metal instance
- License on that disk is **effectively permanent** — plan dedicated pools (see off-ramp in the licensing doc)

| Approach | When |
|----------|------|
| **Provision-time** — `licenses` on boot disk in `GCPMachineProviderSpec` | New metal pool on a payload that supports `licenses` (often **not** OSD CCS — see [gcp-machine-api-disk-licenses-osd-findings.md](gcp-machine-api-disk-licenses-osd-findings.md)) |
| **Day-2** — cordon, drain, stop, `gcloud compute disks update --append-licenses`, start | Existing metal worker (supported on OSD CCS) |

C3 metal boot disks must be **`hyperdisk-balanced`**.

**Full pass criteria (host tag + PGA/KMS + SNAT + guest `slmgr /ato` approval):**  
[gcp-windows-ondemand-licensing-validation.md — End-to-end verification](gcp-windows-ondemand-licensing-validation.md#end-to-end-verification-host--network--guest)  

**Order for PAYG after a successful trial pipeline:**  
[6.1.1](#611-day-2-license-attach) tag metal → [6.1.2](#612-recreate-windows-vm-for-payg-golden-image-still-valid) recreate `$WINDOWS_VM_NAME` on that node (pipeline deletes installer VM only; golden image stays) → [6.1.3](#613-payg-activate-snat--slmgr) SNAT + `slmgr`.

#### 6.1.1 Day-2 license attach

RWO Hyperdisk guests usually **cannot live-migrate**. Stop VMs on the metal node **before** drain or the virt-launcher eviction webhook will deny (`eviction strategy but is not live-migratable`).

```bash
export WIN_PAYG_LICENSE_URL="https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc"
export NODE=<metal-worker-gce-name>   # e.g. nddemo-…-worker-virt-a-…

# Stop guests on this node first (linux + windows)
oc get vmi -A -o wide | grep "$NODE" || true
for ns in linux-vms windows-vms default; do
  oc get vm -n "$ns" -o name 2>/dev/null | while read -r vm; do
    oc stop "$vm" -n "$ns" 2>/dev/null || true
  done
done
# wait until no VMI remains on $NODE
until ! oc get vmi -A -o wide 2>/dev/null | grep -q "$NODE"; do sleep 5; done

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

**Verify (host tag only — then finish network + guest):**

```bash
gcloud compute instances describe "$NODE" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
  --format='yaml(disks[].boot,disks[].licenses,disks[].type)'
```

**Expected:** boot disk `licenses` includes `windows-server-2025-dc` (or your PAYG URL) plus RHCOS.

Then complete **PGA + KMS reachability + guest `slmgr /ato`** using  
[End-to-end verification](gcp-windows-ondemand-licensing-validation.md#end-to-end-verification-host--network--guest)  
(do not stop at the host tag — PAYG is not proven until `slmgr /ato` succeeds on a guest scheduled on `$NODE`).

**Off-ramp:** removing the license from that disk usually **fails** (sticky). Destroy/replace the worker or use a dedicated licensed pool. See [gcp-windows-ondemand-licensing-validation.md](gcp-windows-ondemand-licensing-validation.md).

#### 6.1.2 Recreate Windows VM for PAYG (golden image still valid)

The installer Pipeline **deletes** the temporary EFI installer VM/ISO after success. That is expected. Your boot source is the golden **`$WIN_BOOTSOURCE_DV`** DataSource — **do not re-run the pipeline** for PAYG.

Often `$WINDOWS_VM_NAME` (`win-demo`) was never created, was deleted during drain, or only exists as a Stopped stub. Recreate (or create) the guest from the golden image and **pin it to the tagged metal node**.

**0 — Confirm golden image; pick metal node**

```bash
# DataSource Ready?
oc get datasource "$WIN_BOOTSOURCE_DV" -n "$WIN_DS_NAMESPACE" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
# Expect: True  (if in default, also ensure 6.0 RBAC)

# Guest missing? (typical after pipeline-only or after drain)
oc get vm,vmi "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" 2>&1 || true

# Metal worker (PAYG host)
gcloud compute instances list --project="$GCP_PROJECT" \
  --filter="machineType:c3-standard-192-metal OR machineType:c3-highcpu-192-metal"
export NODE=<metal-worker-gce-name>   # must already have day-2 tag (6.1.1) or tag next
```

If the host is **not** tagged yet → run **6.1.1** on `$NODE` first, then return here.

**1 — Recreate guest from golden image (CLI), pinned to metal**

If an old broken VM/DV exists, remove it first:

```bash
oc delete vm "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" --ignore-not-found
oc delete dv "${WINDOWS_VM_NAME}-rootdisk" -n "$WINDOWS_PROJECT" --ignore-not-found
# PVC may remain — delete if present:
oc delete pvc "${WINDOWS_VM_NAME}-rootdisk" -n "$WINDOWS_PROJECT" --ignore-not-found
```

Then create (same shape as **6.3**, plus `nodeSelector` + `evictionStrategy: None` so later drains don’t wedge on LiveMigrate):

```bash
test -n "$WINDOWS_VM_NAME" && test -n "$WINDOWS_PROJECT" && test -n "$WIN_BOOTSOURCE_DV" && test -n "$NODE"
oc new-project "$WINDOWS_PROJECT" 2>/dev/null || oc project "$WINDOWS_PROJECT"

# 6.0 RBAC if golden image is in default
if [ "$WIN_DS_NAMESPACE" = "default" ]; then
  oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: allow-clone-from-default
  namespace: default
subjects:
  - kind: ServiceAccount
    name: default
    namespace: ${WINDOWS_PROJECT}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cdi.kubevirt.io:clone-sourcer
EOF
fi

oc apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${WINDOWS_VM_NAME}
  namespace: ${WINDOWS_PROJECT}
spec:
  runStrategy: Always
  dataVolumeTemplates:
    - metadata:
        name: ${WINDOWS_VM_NAME}-rootdisk
        annotations:
          cdi.kubevirt.io/storage.bind.immediate.requested: "true"
      spec:
        sourceRef:
          kind: DataSource
          name: ${WIN_BOOTSOURCE_DV}
          namespace: ${WIN_DS_NAMESPACE}
        storage:
          storageClassName: ${HYPERDISK_SC}
          resources:
            requests:
              storage: 60Gi
  template:
    metadata:
      labels:
        kubevirt.io/domain: ${WINDOWS_VM_NAME}
    spec:
      evictionStrategy: None
      nodeSelector:
        kubernetes.io/hostname: ${NODE}
      domain:
        cpu:
          cores: 2
          sockets: 1
          threads: 1
        memory:
          guest: 8Gi
        firmware:
          bootloader:
            efi:
              secureBoot: true
        features:
          smm:
            enabled: true
          acpi: {}
          apic: {}
          hyperv:
            relaxed: {}
            vapic: {}
            spinlocks:
              spinlocks: 8191
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
              bootOrder: 1
          interfaces:
            - name: default
              masquerade: {}
              model: e1000e
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          dataVolume:
            name: ${WINDOWS_VM_NAME}-rootdisk
EOF
```

```bash
oc get vm,vmi,dv "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" -w
# Wait: DV Succeeded, VMI Running on $NODE
oc get vmi "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" -o wide
# NODE column must equal the tagged metal worker
```

Console create (6.2) also works — after create, edit YAML and set `spec.template.spec.nodeSelector` + `evictionStrategy: None` the same way.

**2 — Continue PAYG verification** → [6.1.3](#613-payg-activate-snat--slmgr) (PGA, SNAT, `slmgr /ato`).

#### 6.1.3 PAYG activate (SNAT + `slmgr`)

Prereqs: host tagged (**6.1.1**); Windows guest **Running** on that metal node (**6.1.2** or existing VM); Step 0 env loaded.

You do **not** re-run the installer Pipeline for PAYG **if** the golden image is already **Datacenter** (or converts via DISM). Trial/eval **Standard Server Core** (`ServerStandardEvalCor`) often hits DISM **Error 1168** — then rebuild from a **Datacenter** ISO (step 3). Otherwise: Google host tag + KMS activation is the PAYG path.

**1 — Host tag + PGA + metal→KMS**

```bash
export NODE=$(oc get vmi "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" -o jsonpath='{.status.nodeName}')
echo "guest on: $NODE"

gcloud compute instances describe "$NODE" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
  --format='yaml(disks[].boot,disks[].licenses,disks[].type)'
# Pass: windows-server-2025-dc (+ RHCOS). enable-vmx ≠ PAYG.

gcloud compute networks subnets describe "$WORKER_SUBNET" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --format='value(privateIpGoogleAccess)'
# Pass: True (else --enable-private-ip-google-access)

oc debug node/"$NODE" -- chroot /host bash -c \
  'nc -zv -w 5 kms.windows.googlecloud.com 1688'
# Pass: port open  (hostname is *.googlecloud.com — NOT kms.windows.google.com)
# IP fallback: nc -zv -w 5 35.190.247.13 1688
```

**2 — SNAT path (masquerade → metal NIC → Cloud NAT / PGA)**

```bash
HOST_IP=$(gcloud compute instances describe "$NODE" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
  --format='value(networkInterfaces[0].networkIP)')
echo "metal primary NIC: $HOST_IP"

gcloud compute routers list --project="$GCP_PROJECT" --regions="$GCP_REGION"
# Then nats list on the worker router — source ranges must cover $WORKER_SUBNET

oc get vmi "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" \
  -o jsonpath='{.spec.domain.devices.interfaces}{"\n"}'
# Pass: masquerade present

oc get vmi "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" -o wide
# Pass: NODE == tagged metal
```

In the guest (Admin PowerShell / console — Phase 6.4):

```powershell
Test-NetConnection kms.windows.googlecloud.com -Port 1688
# Pass: TcpTestSucceeded : True
```

Optional while activating — capture on metal:

```bash
oc debug node/"$NODE" -- chroot /host bash -c \
  'tcpdump -ni any host kms.windows.googlecloud.com and port 1688 -c 20'
```

Expect traffic SNAT’d as `$HOST_IP` → KMS:1688.

**3 — Guest edition + activation approval**

Host tag `windows-server-2025-dc` expects a **Datacenter** guest. Prefer building the golden image from a **Windows Server 2025 Datacenter** ISO (Desktop Experience if possible). **Standard Evaluation Server Core** (`ServerStandardEvalCor`) is a common pipeline default and often **cannot** convert cleanly for PAYG.

In the guest (Admin PowerShell — prefer `cscript` so output stays in the console; Mac: Console **Paste** / TigerVNC):

```powershell
# Reachability (already proven if §2 passed)
Test-NetConnection kms.windows.googlecloud.com -Port 1688
# or: Test-NetConnection 35.190.247.13 -Port 1688

DISM /online /Get-CurrentEdition
DISM /online /Get-TargetEditions
```

| Current edition | Action for PAYG (`*-dc` host tag) |
|-----------------|-----------------------------------|
| `ServerDatacenter` / `ServerDatacenterCor` (non-eval) | Install DC GVLK if needed → `/skms` → `/ato` |
| `ServerDatacenterEval` / `ServerDatacenterEvalCor` | `DISM /Set-Edition:ServerDatacenter[Cor] /ProductKey:<DC-GVLK> /AcceptEula` → reboot → `/skms` → `/ato` |
| `ServerStandardEvalCor` | Targets usually `ServerDatacenterCor` + `ServerTurbineCor` only. Try DISM to **DatacenterCor**; if **Error 1168** → **rebuild golden image from Datacenter ISO** (do not use Turbine/Azure). |
| `ServerStandardEval` (Desktop) | Often converts; still prefer Datacenter media to match `windows-server-2025-dc` |

**Datacenter GVLK (2025):** `D764K-2NDRG-47T6Q-P8T8W-YP6DF`  
**Standard GVLK (2025):** `TVRH6-WHNXV-R9WG3-9XRFY-MY832` — only if host license is Standard, not `*-dc`.

Convert when needed (Core example):

```powershell
DISM /online /Set-Edition:ServerDatacenterCor /GetEula:C:\eula.rtf
DISM /online /Set-Edition:ServerDatacenterCor /ProductKey:D764K-2NDRG-47T6Q-P8T8W-YP6DF /AcceptEula
# If Error 1168 ("applying target edition component settings"): stop — rebuild from Datacenter ISO.
# Log: Select-String C:\WINDOWS\Logs\DISM\dism.log -Pattern '1168|license|EULA|Failed' | Select-Object -Last 30
Restart-Computer
```

After reboot (or if already non-eval Datacenter):

```powershell
cscript //nologo C:\Windows\System32\slmgr.vbs /skms 35.190.247.13:1688
cscript //nologo C:\Windows\System32\slmgr.vbs /ato
cscript //nologo C:\Windows\System32\slmgr.vbs /dli
cscript //nologo C:\Windows\System32\slmgr.vbs /xpr
```

**Pass:** `/ato` → product activated successfully; `/dli` → **License Status: Licensed** (KMS/volume — not `TIMEBASED_EVAL` / Initial grace).

**Fail cheat-sheet:**

| Code / symptom | Cause |
|----------------|--------|
| `0xC004F069` on `/ipk` | Still Evaluation — need DISM `Set-Edition`, not bare `/ipk` |
| DISM **Error 1168** | Core Standard Eval → DatacenterCor broken on this media — rebuild Datacenter golden image |
| `0x80072EE2` / `0xC004F074` | Network/DNS to KMS — fix §2 / guest `Test-NetConnection` |
| `/dli` still `TIMEBASED_EVAL` | Conversion/activation did not complete |

**Negative control (optional):** `/dli` before host tag (or guest off metal) → not Google-KMS Licensed; after tag + guest on `$NODE` → Licensed.

Full matrices: [licensing doc §3](gcp-windows-ondemand-licensing-validation.md#3-kms-level-verification-snat-active--activation-approval).

### 6.2 Create VM from the OpenShift Console

1. **Virtualization** → **Bootable volumes** — find Windows Server 2022/2025 **Ready** (check project **default** if needed).
2. **Home** → **Projects** → create `$WINDOWS_PROJECT` if missing.
3. If boot source is in `default`, finish **6.0** first.
4. **Virtualization** → **Catalog** → Windows Server 2022/2025 → **Customize VirtualMachine**:

| Field | Value |
|-------|-------|
| Name | `$WINDOWS_VM_NAME` (default `win-demo`) |
| Project | `$WINDOWS_PROJECT` |
| Storage class | `$HYPERDISK_SC` |
| Disk size | **≥ 60 GiB** |
| Run strategy | **Always** |

5. Select boot source `$WIN_BOOTSOURCE_DV`. If missing from catalog, use **6.3 CLI**.
6. Create → edit YAML → under `spec.template.spec.domain.features` set `smm.enabled: true` → Save.

**Expected:** VM appears in `$WINDOWS_PROJECT` within seconds; status moves Provisioning → Running (5–15 min for clone).

### 6.3 Create VM from CLI (recommended)

This path does **not** require a cluster template (`windows2k25-server-medium` is often missing). It creates the VM directly from the DataSource.

```bash
# Confirm env (name is win-demo by default — case-sensitive)
test -n "$WINDOWS_VM_NAME" && test -n "$WINDOWS_PROJECT" && test -n "$WIN_BOOTSOURCE_DV"
echo "Will create VM/$WINDOWS_VM_NAME in project/$WINDOWS_PROJECT from DataSource/$WIN_BOOTSOURCE_DV (ns=$WIN_DS_NAMESPACE)"

oc new-project "$WINDOWS_PROJECT" 2>/dev/null || oc project "$WINDOWS_PROJECT"

# RBAC if golden image is in default (6.0)
if [ "$WIN_DS_NAMESPACE" = "default" ]; then
  oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: allow-clone-from-default
  namespace: default
subjects:
  - kind: ServiceAccount
    name: default
    namespace: ${WINDOWS_PROJECT}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cdi.kubevirt.io:clone-sourcer
EOF
fi

# Create VM + root DataVolume (clone from golden image)
oc apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${WINDOWS_VM_NAME}
  namespace: ${WINDOWS_PROJECT}
spec:
  runStrategy: Always
  dataVolumeTemplates:
    - metadata:
        name: ${WINDOWS_VM_NAME}-rootdisk
        annotations:
          cdi.kubevirt.io/storage.bind.immediate.requested: "true"
      spec:
        sourceRef:
          kind: DataSource
          name: ${WIN_BOOTSOURCE_DV}
          namespace: ${WIN_DS_NAMESPACE}
        storage:
          storageClassName: ${HYPERDISK_SC}
          resources:
            requests:
              storage: 60Gi
  template:
    metadata:
      labels:
        kubevirt.io/domain: ${WINDOWS_VM_NAME}
    spec:
      domain:
        cpu:
          cores: 2
          sockets: 1
          threads: 1
        memory:
          guest: 8Gi
        firmware:
          bootloader:
            efi:
              secureBoot: true
        features:
          smm:
            enabled: true
          acpi: {}
          apic: {}
          hyperv:
            relaxed: {}
            vapic: {}
            spinlocks:
              spinlocks: 8191
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
              bootOrder: 1
          interfaces:
            - name: default
              masquerade: {}
              model: e1000e
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          dataVolume:
            name: ${WINDOWS_VM_NAME}-rootdisk
EOF
```

**Verify the VM exists before any patch:**

```bash
oc get vm "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT"
```

**Expected output:**

```text
NAME                AGE   STATUS         READY
win-demo            5s    Provisioning   False
# or Running / Stopped — but the NAME must appear
```

If you see `Error from server (NotFound)`:

```bash
# Wrong project / name / Step 0 not sourced?
echo "WINDOWS_PROJECT=$WINDOWS_PROJECT WINDOWS_VM_NAME=$WINDOWS_VM_NAME"
oc get vm -A | grep -i win || true
oc get datasource "$WIN_BOOTSOURCE_DV" -n "$WIN_DS_NAMESPACE"
# Re-run the oc apply block above — do not patch yet
```

Watch clone (5–15 min):

```bash
oc get vm -n "$WINDOWS_PROJECT"
oc get dv -n "$WINDOWS_PROJECT"
oc get vmi -n "$WINDOWS_PROJECT"
oc get pvc -n "$WINDOWS_PROJECT"
oc get vmi "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" -o wide -w
```

**Expected (healthy):**

```text
NAME       AGE   STATUS    READY
win-demo   10m   Running   True

NAME                 PHASE       PROGRESS
win-demo-rootdisk    Succeeded   100.0%
```

#### 6.3.1 Optional — create from cluster template instead

Only if the template exists on your cluster:

```bash
oc get templates -n openshift | grep -iE 'windows|2k2'
# set WIN_TEMPLATE to a name that actually lists, then:
oc process "${WIN_TEMPLATE}" -n openshift \
  -p NAME="${WINDOWS_VM_NAME}" \
  -p DATA_SOURCE_NAME="${WIN_BOOTSOURCE_DV}" \
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

oc get vm "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT"
```

### 6.4 Connect to the VM

**Easiest on Mac:** OpenShift Console → **Virtualization** → **VirtualMachines** → project `$WINDOWS_PROJECT` → `$WINDOWS_VM_NAME` → **Console** tab (no local VNC app needed).

**virtctl on macOS:** stock `virtctl vnc` fails with `no supported VNC app found for darwin` unless TigerVNC (or Chicken/RealVNC) is installed. Use proxy mode + any viewer, or install TigerVNC:

```bash
# Option A — proxy only, then connect with any VNC client (Screen Sharing / TigerVNC)
virtctl vnc --proxy-only "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT"
# prints e.g. Listening for VNC connections on local port 5901
# then: open vnc://127.0.0.1:5901   (macOS Screen Sharing)
# or point TigerVNC at 127.0.0.1:<port>

# Option B — install TigerVNC, then plain virtctl vnc works
# brew install --cask tigervnc-viewer
# virtctl vnc "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT"
```

**Expected:** Windows OOBE / login; `oc get vm "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT"` → `Running` / `Ready=True`.

### 6.5 Troubleshooting — VM exists but Stay Stopped (clone RBAC)

**Only after** `oc get vm "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT"` succeeds. If NotFound, go back to **6.3**.

```bash
oc get vm "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT"
oc get dv -n "$WINDOWS_PROJECT"
oc describe vm "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" | tail -20
```

**Broken symptom:**

```text
STATUS: Stopped
Message: ... insufficient permissions in clone source namespace default
```

Fix — re-apply RBAC, then toggle runStrategy:

```bash
# re-run 6.0 RoleBinding, then:
oc patch vm "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" --type merge -p '{"spec":{"runStrategy":"Halted"}}'
oc patch vm "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" --type merge -p '{"spec":{"runStrategy":"Always"}}'

oc get vm -n "$WINDOWS_PROJECT"
oc get dv -n "$WINDOWS_PROJECT"
```

Still Stopped → delete and recreate (RBAC can stay):

```bash
oc delete vm "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT"
# Re-run 6.3 apply block
```

**Alternatives:** create the guest in namespace `default` (same as golden image), or set `WIN_DS_NAMESPACE=openshift-virtualization-os-images` if the DataSource is Ready there.

---

## Phase 7 — Verification summary

```bash
echo "=== Metal / KVM ==="
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.devices\.kubevirt\.io/kvm}{"\n"}{end}' | grep 1k

echo "=== Hyperdisk ==="
gcloud compute storage-pools list --project="$GCP_PROJECT" --filter="zone=$GCP_ZONE"
oc get storageclass "$HYPERDISK_SC"

echo "=== Virtualization ==="
oc get hco -n openshift-cnv kubevirt-hyperconverged \
  -o jsonpath='Available={.status.conditions[?(@.type=="Available")].status}{"\n"}'

echo "=== Boot sources ==="
oc get datasource "$LINUX_DATASOURCE" -n openshift-virtualization-os-images \
  -o jsonpath='{.metadata.name}={.status.conditions[?(@.type=="Ready")].status} {.status.conditions[?(@.type=="Ready")].message}{"\n"}' 2>/dev/null || true
oc get datasource "$WIN_BOOTSOURCE_DV" -n "$WIN_DS_NAMESPACE" \
  -o jsonpath='{.metadata.name}@{.metadata.namespace}={.status.conditions[?(@.type=="Ready")].status} {.status.conditions[?(@.type=="Ready")].message}{"\n"}'

echo "=== VMs ==="
oc get vm -A
```

**Expected output (fully working cluster):**

```text
=== Metal / KVM ===
<metal-worker-node-name>    1k

=== Hyperdisk ===
NAME              ZONE           STATE
${CLUSTER_NAME}-virt-pool  ${GCP_ZONE}  READY

NAME                PROVISIONER            ...
hyperdisk-virt-sc   pd.csi.storage.gke.io  ...

=== Virtualization ===
Available=True

=== Boot sources ===
<linux-datasource-name>=True
<windows-bootsource-dv>=True

=== VMs ===
NAMESPACE    NAME         AGE   STATUS    READY
<linux-project>    <linux-vm-name>   1h    Running   True
<windows-project>  <windows-vm-name>     30m   Running   True
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
        ├─► Phase 4 Path A (Tekton) or Path B (local ISO) → $WIN_BOOTSOURCE_DV Ready (often in default ns)
        ├─► Phase 4.2.6: Verify golden DV Succeeded; DataSource Ready
        ├─► Phase 6.0: Cross-ns RBAC if $WIN_BOOTSOURCE_DV in default
        ├─► Phase 6.3: Create VM YAML (or 6.2 console) → Running
        ├─► Phase 6.4: Console / virtctl vnc
        └─► Optional PAYG: 6.1.1 tag metal → 6.1.2 recreate win guest on metal → 6.1.3 SNAT/`slmgr`; 6.5 if Stopped after create
```

---

## Cleanup

```bash
oc delete namespace "$LINUX_PROJECT" "$WINDOWS_PROJECT" --wait=false
# guest VM is in $WINDOWS_PROJECT (deleted with the namespace above)
# leftover installer / golden-image artifacts in default (Path A/B):
oc delete vm windows-manual-install -n default --ignore-not-found
oc delete dv "$WIN_BOOTSOURCE_DV" "${WIN_BOOTSOURCE_DV}-iso" virtio-win-iso -n default --ignore-not-found

# Optional: remove Hyperdisk pool (destructive — deletes pool capacity billing)
# gcloud compute storage-pools delete "$VIRT_POOL_NAME" \
#   --zone=$GCP_ZONE --project=$GCP_PROJECT
```

**Expected output:**

```text
namespace "<linux-project>" deleted
namespace "<windows-project>" deleted
```


---

## Official references

| Topic | Red Hat documentation |
|-------|------------------------|
| Install OpenShift Virtualization on OSD | [OSD 4 — Installing Virtualization](https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/virtualization/installing) |
| Install OpenShift Virtualization (OCP) | [OCP — Installing Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/virtualization/installing) (match your version) |
| Install OpenShift Pipelines | [Installing OpenShift Pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.22/html/installing_and_configuring/installing-pipelines) (Path A / 4.1 — install once via console **or** CLI) |
| Windows EFI installer pipeline | [ArtifactHub — windows-efi-installer](https://artifacthub.io/packages/tekton-pipeline/redhat-pipelines/windows-efi-installer) |
| Hyperdisk + virt on GCP | [KCS 7139046 — Storage configuration for OpenShift Virtualization 4.21.x on Google Cloud](https://access.redhat.com/articles/7139046) |
| Hyperdisk StorageClass / pools | [OCP 4.21 — GCP PD hyperdisk-balanced procedure](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/storage/persistent-storage-csi-gcp-pd) |
| OSD virt storage overview | [OSD 4 — Virtualization storage](https://docs.redhat.com/en/documentation/openshift_dedicated/4/html/virtualization/storage) |
| GCP Hyperdisk storage pools | [Google Cloud — Hyperdisk storage pools](https://cloud.google.com/compute/docs/disks/hyperdisks-storage-pools) (Phase 3.1) |

