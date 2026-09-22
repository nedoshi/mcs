# GCP Windows PAYG activation on OSD (OpenShift Virtualization)

Activate a Windows guest with **Google PAYG** on OSD CCS + C3 metal: Datacenter golden image → tag metal host → KMS / `slmgr`.

**Prerequisites:** OpenShift Virtualization; C3 metal worker (`hyperdisk-balanced`); Hyperdisk StorageClass; `oc`, `virtctl`, `gcloud`.

---

## Step 0 — Environment

```bash
export CLUSTER_NAME=<cluster-name>
export GCP_PROJECT=<project-id>
export GCP_REGION=<region>
export GCP_ZONE=<zone>
export WORKER_SUBNET=${CLUSTER_NAME}-worker-subnet

export WINDOWS_PROJECT=windows-vms
export WINDOWS_VM_NAME=win-demo
export WIN_BOOTSOURCE_DV=win2k25
export WIN_DS_NAMESPACE=default
export HYPERDISK_SC=hyperdisk-virt-sc

export WIN_PAYG_LICENSE_URL="https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc"
export WIN_ISO_PATH="$HOME/Downloads/windows-server-2025-datacenter.iso"
export VIRTIO_ISO_PATH="$HOME/Downloads/virtio-win.iso"

gcloud config set project "$GCP_PROJECT"
oc whoami
```

**Expected output:**

```text
# oc whoami
<your-user>

# gcloud config set project ...
Updated property [core/project].
```

```bash
gcloud compute instances list --project="$GCP_PROJECT" \
  --filter="machineType:c3-standard-192-metal OR machineType:c3-highcpu-192-metal"
export NODE=<metal-worker-gce-name>
```

**Expected output:**

```text
NAME                              ZONE           MACHINE_TYPE           ...  STATUS
<cluster>-…-worker-virt-a-xxxxx   <zone>         c3-standard-192-metal  ...  RUNNING
```

---

## Step 1 — Tag the metal host (day-2)

```bash
oc get vmi -A -o wide | grep "$NODE" || true
for ns in windows-vms default linux-vms; do
  oc get vm -n "$ns" -o name 2>/dev/null | while read -r vm; do
    oc stop "$vm" -n "$ns" 2>/dev/null || true
  done
done
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

```bash
gcloud compute instances describe "$NODE" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
  --format='yaml(disks[].boot,disks[].licenses,disks[].type)'
```

**Expected output:**

```yaml
disks:
- boot: true
  licenses:
  - https://www.googleapis.com/compute/v1/projects/redhat-marketplace-public/global/licenses/...
  - https://www.googleapis.com/compute/v1/projects/windows-cloud/global/licenses/windows-server-2025-dc
  type: PERSISTENT
```

---

## Step 2 — Private Google Access and KMS reachability

```bash
gcloud compute networks subnets describe "$WORKER_SUBNET" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --format='value(privateIpGoogleAccess)'
```

**Expected output:**

```text
True
```

If `False`:

```bash
gcloud compute networks subnets update "$WORKER_SUBNET" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --enable-private-ip-google-access
```

**Expected output:**

```text
Updated [...].
```

```bash
gcloud compute routers list --project="$GCP_PROJECT" --regions="$GCP_REGION"
export NAT_ROUTER=<nat-router-name>
gcloud compute routers nats list --router="$NAT_ROUTER" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --format='yaml(name,sourceSubnetworkIpRangesToNat)'
```

**Expected output:** at least one NAT whose source ranges cover the worker subnet (or all subnetworks).

```bash
oc debug node/"$NODE" -- chroot /host bash -c \
  'nc -zv -w 5 kms.windows.googlecloud.com 1688 || nc -zv -w 5 35.190.247.13 1688'
```

**Expected output:**

```text
Ncat: Connected to 35.190.247.13:1688.
```

---

## Step 3 — Datacenter golden image

### 3.1 Download ISOs

1. [Windows Server 2025 Eval](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025) → **Datacenter (Desktop Experience)** → `$WIN_ISO_PATH`
2. VirtIO: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso → `$VIRTIO_ISO_PATH`

```bash
ls -lh "$WIN_ISO_PATH" "$VIRTIO_ISO_PATH"
```

**Expected output:**

```text
-rw-r--r--  ...  ~5-7G  ...  windows-server-2025-datacenter.iso
-rw-r--r--  ...  ~600M  ...  virtio-win.iso
```

### 3.2 Default StorageClass

```bash
oc patch storageclass "$HYPERDISK_SC" --type merge -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
oc get storageclass "$HYPERDISK_SC" \
  -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}'
```

**Expected output:**

```text
true
```

### 3.3 Upload ISOs

```bash
virtctl image-upload dv "${WIN_BOOTSOURCE_DV}-iso" \
  --namespace=default \
  --size=10Gi \
  --image-path="$WIN_ISO_PATH" \
  --storage-class="$HYPERDISK_SC" \
  --access-mode=ReadWriteOnce \
  --force-bind \
  --insecure

virtctl image-upload dv virtio-win-iso \
  --namespace=default \
  --size=1Gi \
  --image-path="$VIRTIO_ISO_PATH" \
  --storage-class="$HYPERDISK_SC" \
  --access-mode=ReadWriteOnce \
  --force-bind \
  --insecure

oc get dv,pvc "${WIN_BOOTSOURCE_DV}-iso" virtio-win-iso -n default
```

**Expected output:**

```text
NAME                      PHASE       PROGRESS   AGE
datavolume/.../win2k25-iso     Succeeded   N/A        ...
datavolume/.../virtio-win-iso  Succeeded   N/A        ...

NAME                             STATUS   VOLUME   CAPACITY   ...
persistentvolumeclaim/win2k25-iso     Bound    ...
persistentvolumeclaim/virtio-win-iso  Bound    ...
```

### 3.4 Create installer VM

```bash
oc apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: windows-manual-install
  namespace: default
spec:
  runStrategy: Always
  dataVolumeTemplates:
    - metadata:
        name: windows-manual-install-root
        annotations:
          cdi.kubevirt.io/storage.bind.immediate.requested: "true"
      spec:
        source:
          blank: {}
        storage:
          storageClassName: ${HYPERDISK_SC}
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 60Gi
  template:
    metadata:
      labels:
        kubevirt.io/domain: windows-manual-install
    spec:
      evictionStrategy: None
      nodeSelector:
        kubernetes.io/hostname: ${NODE}
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
EOF

oc get vmi windows-manual-install -n default -o wide
```

**Expected output:**

```text
virtualmachine.kubevirt.io/windows-manual-install created

NAME                     AGE   PHASE     IP           NODENAME                              READY
windows-manual-install   ...   Running   10.x.x.x     <metal-worker-name>                   True
```

### 3.5 Install Windows

Console: Virtualization → `windows-manual-install` → **Console**  
(or `virtctl vnc --proxy-only windows-manual-install -n default` → TigerVNC `127.0.0.1:<port from JSON>`)

1. Load disk driver: VirtIO CD → `viostor\2k25\amd64`
2. Select **Windows Server 2025 Datacenter (Desktop Experience)**
3. Complete install and first login
4. Install VirtIO guest tools and QEMU guest agent from VirtIO ISO
5. Sysprep:

```powershell
C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
```

```bash
oc get vmi windows-manual-install -n default
oc get vm windows-manual-install -n default
```

**Expected output:**

```text
Error from server (NotFound): virtualmachineinstances.kubevirt.io "windows-manual-install" not found

NAME                     AGE   STATUS    READY
windows-manual-install   ...   Stopped   False
```

### 3.6 Publish golden DataSource

```bash
oc patch vm windows-manual-install -n default --type merge \
  -p '{"spec":{"runStrategy":"Halted"}}'
oc delete vmi windows-manual-install -n default --ignore-not-found

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
oc get dv "$WIN_BOOTSOURCE_DV" -n default
oc get datasource "$WIN_BOOTSOURCE_DV" -n default \
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}'
```

**Expected output:**

```text
NAME      PHASE       PROGRESS   AGE
win2k25   Succeeded   100.0%     ...

Ready=True
```

Optional cleanup:

```bash
oc delete vm windows-manual-install -n default --ignore-not-found
oc delete dv "${WIN_BOOTSOURCE_DV}-iso" virtio-win-iso -n default --ignore-not-found
```

---

## Step 4 — Create guest on tagged metal

```bash
oc new-project "$WINDOWS_PROJECT" 2>/dev/null || oc project "$WINDOWS_PROJECT"

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

oc delete vm "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" --ignore-not-found
oc delete dv "${WINDOWS_VM_NAME}-rootdisk" -n "$WINDOWS_PROJECT" --ignore-not-found
oc delete pvc "${WINDOWS_VM_NAME}-rootdisk" -n "$WINDOWS_PROJECT" --ignore-not-found

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

oc get vmi "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" -o wide
oc get vmi "$WINDOWS_VM_NAME" -n "$WINDOWS_PROJECT" \
  -o jsonpath='{.spec.domain.devices.interfaces}{"\n"}'

HOST_IP=$(gcloud compute instances describe "$NODE" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
  --format='value(networkInterfaces[0].networkIP)')
echo "metal primary NIC: $HOST_IP"
```

**Expected output:**

```text
NAME       AGE   PHASE     IP         NODENAME                 READY
win-demo   ...   Running   10.x.x.x   <metal-worker-name>      True

[{"name":"default","masquerade":{},"model":"e1000e"}]

metal primary NIC: 10.x.x.x
```

(`NODENAME` must equal `$NODE`.)

---

## Step 5 — Activate Windows (guest)

Open console → Administrator PowerShell.

```powershell
DISM /online /Get-CurrentEdition
```

**Expected output:**

```text
Current Edition : ServerDatacenter
```

(or `ServerDatacenterEval` before convert)

```powershell
Test-NetConnection kms.windows.googlecloud.com -Port 1688
```

**Expected output:**

```text
TcpTestSucceeded : True
```

If edition is `ServerDatacenterEval`:

```powershell
DISM /online /Set-Edition:ServerDatacenter /ProductKey:D764K-2NDRG-47T6Q-P8T8W-YP6DF /AcceptEula
Restart-Computer
```

**Expected output:**

```text
The operation completed successfully.
```

Then:

```powershell
cscript //nologo C:\Windows\System32\slmgr.vbs /ipk D764K-2NDRG-47T6Q-P8T8W-YP6DF
cscript //nologo C:\Windows\System32\slmgr.vbs /skms 35.190.247.13:1688
cscript //nologo C:\Windows\System32\slmgr.vbs /ato
cscript //nologo C:\Windows\System32\slmgr.vbs /dli
```

**Expected output:**

```text
Installed product key ... successfully.
Key Management Service machine name set to 35.190.247.13:1688 successfully.
Product activated successfully.

Name: Windows(R), ServerDatacenter edition
Description: Windows(R) Operating System, VOLUME_KMSCLIENT channel
License Status: Licensed
```

---

## Final check

| Step | Expected |
|------|----------|
| 1 Host licenses | `windows-server-2025-dc` + RHCOS |
| 2 PGA | `True` |
| 2 KMS :1688 | Connected / `TcpTestSucceeded : True` |
| 3 Golden DataSource | `Ready=True` |
| 4 Guest VMI | `Running` on tagged `$NODE`, `masquerade` |
| 5 `/dli` | **License Status: Licensed** |
