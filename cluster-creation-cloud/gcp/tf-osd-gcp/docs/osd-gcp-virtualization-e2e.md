# OSD on GCP: End-to-End Linux and Windows VM Provisioning

Guide for provisioning Linux and Windows virtual machines on an **existing** OpenShift Dedicated (OSD) cluster on GCP using OpenShift Virtualization.

**Audience:** Cluster already installed (CCS, WIF or service account). Default workers are **N2** (e.g. `n2-standard-4`). You want Linux + Windows guests.

**Related docs:**

- [gcp-windows-ondemand-licensing-validation.md](gcp-windows-ondemand-licensing-validation.md) — GCP Windows PAYG license tagging on metal worker boot disks
- [../README.md](../README.md) — Terraform cluster deployment and `enable_openshift_virt`

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
│  │ c3-standard-192-metal (KVM, 192 vCPU)    │  ← KubeVirt pods │
│  └──────────────────────────────────────────┘                   │
│                                                                 │
│  VM disk storage (guest PVCs on metal nodes)                    │
│  • hyperdisk-virt-sc — REQUIRED on C3 metal (Hyperdisk only)    │
│  • standard-csi / ssd-csi — pd-standard/pd-ssd; CANNOT attach │
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

GCP bare metal (`c3-standard-192-metal`) accepts **only Hyperdisk** volumes for attached disks — not `pd-standard` (`standard-csi`) or `pd-ssd` (`ssd-csi`).

If you use `standard-csi` for a VM on a metal node, the importer or virt-launcher pod fails with:

```text
Failed to Attach: googleapi: Error 400: pd-standard disk type cannot be used by
c3-standard-192-metal machine type., badRequest
```

**This is the most common reason Linux VMs stay stuck in `Provisioning` or `ImportScheduled` after KVM and the virt operator are working.**

---

## Why `scripts/test-vm-ssh.sh` often fails

| Symptom | Root cause | Fix |
|---------|------------|-----|
| `Insufficient devices.kubevirt.io/kvm` | No C3 metal pool | Phase 1 |
| `pd-standard disk type cannot be used by c3-standard-192-metal` | VM disk on `standard-csi` / `ssd-csi` | Phase 3 + use `hyperdisk-virt-sc` |
| `IncompatibleVolumeModes` | Snapshot clone Block vs Filesystem mismatch | Use registry import (Phase 5) not snapshot clone |
| PVC `Pending` + `WaitForFirstConsumer` loop | Binding deadlock with populator | `cdi.kubevirt.io/storage.bind.immediate.requested: "true"` + pre-import DV |
| Importer `Init:0/1` for 15+ min | Disk attach error on metal (see above) | Hyperdisk StorageClass |
| Script exits after 5 min | First import takes **15–25 min** | `oc get dv -w` longer |
| `Source PVC win2k22 not available` | Windows not auto-imported | Phase 4 |
| `SecureBoot requires SMM` | Windows template | `features.smm.enabled: true` |
| VM NotFound in expected namespace | Wrong OpenShift project | `oc get vm -A` |

The stock test script uses default storage (no `hyperdisk-virt-sc`) and is unsuitable for C3 metal clusters without modification.

---

## Prerequisites checklist

### Variables (set once per session)

```bash
export CLUSTER_NAME=nddemo
export GCP_PROJECT=it-cloud-gcp-mobb-amer
export GCP_REGION=us-central1
export GCP_ZONE=us-central1-a          # must match metal worker zone
export WORKER_SUBNET=${CLUSTER_NAME}-worker-subnet
```

### Cluster and CLI

```bash
oc login <api-url> --token=<token>
oc whoami
gcloud config set project "$GCP_PROJECT"
```

### Tools

| Tool | Purpose |
|------|---------|
| `oc` | Cluster admin |
| `virtctl` | SSH / VNC — Console → Virtualization → virtctl |
| `gcloud` | Hyperdisk pool, Windows license |
| `ocm` | Add machine pool |

### GCP

- [ ] `c3-standard-192-metal` available in `GCP_ZONE`
- [ ] Quota for 1+ metal instance + Hyperdisk pool (**min 10 TiB**)
- [ ] `compute.googleapis.com` enabled

---

## Phase 1 — Add a C3 metal machine pool

N2-only clusters cannot run VMs.

### OCM CLI

```bash
export CLUSTER_ID=$(ocm list clusters --no-headers --columns id,name \
  | awk -v n="$CLUSTER_NAME" '$2==n {print $1}')

ocm create machinepool --cluster "$CLUSTER_ID" \
  --id worker-virt \
  --replicas 1 \
  --instance-type c3-standard-192-metal \
  --multi-availability-zone=false
```

### Red Hat console

Cluster → **Machine pools** → **Add machine pool** → `c3-standard-192-metal`, 1 replica, zone `us-central1-a`.

### Verify (10–20 min)

```bash
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.devices\.kubevirt\.io/kvm}{"\n"}{end}' | grep 1k

gcloud compute instances list --project="$GCP_PROJECT" \
  --filter="machineType:c3-standard-192-metal"
```

---

## Phase 2 — Install OpenShift Virtualization

```bash
cd cluster-creation-cloud/gcp/tf-osd-gcp
./scripts/install-openshift-virt.sh
```

Verify:

```bash
oc get hco -n openshift-cnv kubevirt-hyperconverged \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}{"\n"}'
# True
```

---

## Phase 3 — Hyperdisk storage (required for VM disks on metal)

Do this **before** creating any guest VM. Skipping this step causes attach failures on the metal node.

### 3.1 Create Hyperdisk Balanced storage pool in GCP

Pool must be in the **same zone** as the metal worker (`GCP_ZONE`). GCP minimum capacity is **10 TiB (10240 GiB)**.

```bash
gcloud compute storage-pools create ${CLUSTER_NAME}-virt-pool \
  --zone="$GCP_ZONE" \
  --project="$GCP_PROJECT" \
  --storage-pool-type=hyperdisk-balanced \
  --pool-provisioned-capacity-gb=10240 \
  --pool-provisioned-iops=10000 \
  --pool-provisioned-throughput=1024 \
  --capacity-provisioning-type=advanced \
  --performance-provisioning-type=advanced
```

Verify:

```bash
gcloud compute storage-pools list --project="$GCP_PROJECT" \
  --filter="zone:$GCP_ZONE"
```

Expected: `${CLUSTER_NAME}-virt-pool` in state `READY`.

**Cost note:** You provision 10 TiB of pool capacity even if VMs use less. Tune IOPS/throughput only if needed.

### 3.2 Create OpenShift StorageClass `hyperdisk-virt-sc`

```bash
cd cluster-creation-cloud/gcp/tf-osd-gcp

export STORAGE_POOL_PATH="projects/${GCP_PROJECT}/zones/${GCP_ZONE}/storagePools/${CLUSTER_NAME}-virt-pool"
./scripts/install-hyperdisk-storageclass.sh
```

Verify:

```bash
oc get storageclass hyperdisk-virt-sc
# PROVISIONER: pd.csi.storage.gke.io
# parameters.type: hyperdisk-balanced
```

Patch StorageProfile (install script may do this; confirm):

```bash
oc patch storageprofile hyperdisk-virt-sc --type=merge -p \
  '{"spec":{"claimPropertySets":[{"accessModes":["ReadWriteOnce"],"volumeMode":"Filesystem"}]}}'
```

### 3.3 Terraform alternative (new clusters)

Set in `terraform.tfvars` before `make all`:

```hcl
enable_openshift_virt = true
gcp_zone              = "us-central1-a"
hyperdisk_pool_capacity_gb = 10240
```

Terraform creates the pool, metal workers, virt operator, and `hyperdisk-virt-sc` automatically.

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

**Do not** clone from this DataSource via snapshot onto metal without Hyperdisk — use the registry import in Phase 5 instead.

### Windows — NOT auto-imported

```bash
oc get datasource win2k22 -n openshift-virtualization-os-images \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}{"\n"}'
# Often: PVC not found
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

#### 4.2 Windows Server 2022 boot-source pipeline

1. ISO URL: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022  
2. Console → **Help** → **Quick Starts** → **Creating a Windows boot source**  
   Or [ArtifactHub windows-efi-installer](https://artifacthub.io/packages/tekton-pipeline/redhat-pipelines/windows-efi-installer)
3. Wait 20–60 min; verify `win2k22` DataSource Ready = `True`.

#### 4.3 (Optional) Private Google Access

```bash
gcloud compute networks subnets update "$WORKER_SUBNET" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --enable-private-ip-google-access
```

---

## Phase 5 — Linux VM (reliable workflow)

**Pattern:** (1) import disk with Hyperdisk + registry + immediate bind, (2) attach existing PVC to VM.

### 5.1 Namespace and SSH key

```bash
oc new-project linux-vms

ssh-keygen -t ed25519 -f /tmp/virt-linux -N "" -q
export SSH_PUBKEY=$(cat /tmp/virt-linux.pub)
```

### 5.2 Import disk (DataVolume)

```bash
oc apply -f - <<'EOF'
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: linux-demo-disk
  namespace: linux-vms
  annotations:
    cdi.kubevirt.io/storage.bind.immediate.requested: "true"
spec:
  source:
    registry:
      url: docker://quay.io/containerdisks/centos-stream:9
      pullMethod: node
  storage:
    storageClassName: hyperdisk-virt-sc
    resources:
      requests:
        storage: 32Gi
EOF
```

Watch until **Succeeded** (15–25 min first time):

```bash
oc get dv linux-demo-disk -n linux-vms -w
```

```bash
oc get dv linux-demo-disk -n linux-vms -o jsonpath='{.status.phase}{"\n"}'
# Succeeded

oc get pvc linux-demo-disk -n linux-vms
# Bound, hyperdisk-virt-sc
```

If importer pod fails, check attach errors:

```bash
oc get pods -n linux-vms | grep importer
oc describe pod -n linux-vms -l cdi.kubevirt.io/importer | tail -20
```

### 5.3 Create VM (uses existing PVC)

```bash
oc apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: linux-demo
  namespace: linux-vms
spec:
  runStrategy: Always
  template:
    metadata:
      labels:
        kubevirt.io/domain: linux-demo
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
          claimName: linux-demo-disk
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            user: centos
            ssh_authorized_keys:
              - "${SSH_PUBKEY}"
EOF
```

Watch (2–5 min after DV Succeeded):

```bash
oc get vm linux-demo -n linux-vms -w
oc get vmi linux-demo -n linux-vms -o wide
# NODE = *-worker-virt-*
```

### 5.4 SSH test

```bash
virtctl ssh "centos@vmi/linux-demo" -n linux-vms \
  -i /tmp/virt-linux \
  --local-ssh-opts="-o StrictHostKeyChecking=accept-new" \
  --command "hostname"
```

**Pass:** prints guest hostname.

---

## Phase 6 — Windows VM

**Prerequisites:** `win2k22` DataSource Ready; `hyperdisk-virt-sc` exists.

### 6.1 (Optional) GCP Windows PAYG license on metal node

See [gcp-windows-ondemand-licensing-validation.md](gcp-windows-ondemand-licensing-validation.md). Tags the **metal worker boot disk**, not the guest PVC.

### 6.2 Import Windows disk OR use template DataSource

After boot source pipeline, create VM from template with **Hyperdisk** and **SMM**:

```bash
oc new-project windows-vms

oc process windows2k22-server-medium -n openshift \
  -p NAME=win-demo \
  -p DATA_SOURCE_NAME=win2k22 \
  -p DATA_SOURCE_NAMESPACE=openshift-virtualization-os-images \
  -o yaml | python3 -c "
import yaml, sys
docs = list(yaml.safe_load_all(sys.stdin))
for d in docs:
    if d.get('kind') == 'VirtualMachine':
        d['metadata']['namespace'] = 'windows-vms'
        domain = d['spec']['template']['spec']['domain']
        domain.setdefault('features', {})['smm'] = {'enabled': True}
        d['spec']['dataVolumeTemplates'][0]['spec']['storage']['storageClassName'] = 'hyperdisk-virt-sc'
        d['spec']['dataVolumeTemplates'][0]['metadata'].setdefault('annotations', {})['cdi.kubevirt.io/storage.bind.immediate.requested'] = 'true'
print(yaml.dump_all(docs))
" | oc apply -f -

oc patch vm win-demo -n windows-vms --type merge -p '{"spec":{"runStrategy":"Always"}}'
```

### 6.3 Console

```bash
virtctl vnc win-demo -n windows-vms
```

---

## Phase 7 — Verification summary

```bash
echo "=== Metal / KVM ==="
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.devices\.kubevirt\.io/kvm}{"\n"}{end}' | grep 1k

echo "=== Hyperdisk ==="
gcloud compute storage-pools list --project="$GCP_PROJECT" --filter="zone:$GCP_ZONE"
oc get storageclass hyperdisk-virt-sc

echo "=== Virtualization ==="
oc get hco -n openshift-cnv kubevirt-hyperconverged \
  -o jsonpath='Available={.status.conditions[?(@.type=="Available")].status}{"\n"}'

echo "=== Boot sources ==="
for ds in centos-stream9 win2k22; do
  oc get datasource "$ds" -n openshift-virtualization-os-images \
    -o jsonpath="$ds={.status.conditions[?(@.type==\"Ready\")].status}{\" \"}{.status.conditions[?(@.type==\"Ready\")].message}{\"\n\"}"
done

echo "=== VMs ==="
oc get vm -A
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
        ├─► Phase 4: Boot source pipeline → win2k22 Ready
        ├─► Phase 6: Template + hyperdisk-virt-sc + SMM → virtctl vnc
        └─► Optional: Phase 6.1 metal boot-disk license
```

---

## Cleanup

```bash
oc delete namespace linux-vms windows-vms --wait=false
oc delete vm win-demo -n default --ignore-not-found

# Optional: remove Hyperdisk pool (destructive — deletes pool capacity billing)
# gcloud compute storage-pools delete ${CLUSTER_NAME}-virt-pool \
#   --zone=$GCP_ZONE --project=$GCP_PROJECT
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
| `SecureBoot requires SMM` | `features.smm.enabled: true` |
| VM in wrong namespace | `oc get vm -A` |

---

## Terraform all-in-one (greenfield)

```bash
cp configuration/tfvars/terraform.tfvars.openshift-virt.example configuration/tfvars/terraform.tfvars
# gcp_project, clustername, gcp_zone=us-central1-a, enable_openshift_virt=true
make all
```

Creates metal workers, Hyperdisk pool, virt operator, and `hyperdisk-virt-sc`. Windows boot source remains manual (Phase 4).
