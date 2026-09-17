# UC-03 — Persistent storage with Amazon EBS gp3

**Provenance:** [ROSA Technical Solutions.pdf](../../ROSA%20Technical%20Solutions.pdf) — Scenario 3.

## Summary

Provision a **gp3** volume via a custom **StorageClass**, bind a **PVC**, and mount it in a pod—with optional tuned IOPS/throughput.

## Why this matters

- Stateful apps need durable block storage; gp3 decouples IOPS/throughput from size.
- Validates the pre-installed **Amazon EBS CSI Driver** on ROSA (`ebs.csi.aws.com`).
- Common regression for zone placement, encryption, and `WaitForFirstConsumer`.

## Architecture

```
 [Pod] --> volumeMount /data
    |
 [PVC gp3-custom]
    |
 [EBS CSI Driver Operator]
    |
 [AWS EBS gp3 volume (encrypted)]
```

## Prerequisites

- Cluster `ready`; default EBS CSI operator healthy:

  ```bash
  oc get co | grep -i csi
  oc get sc | grep -E 'gp3|ebs'
  ```

## Steps

1. Apply StorageClass, PVC, and Pod (from PDF):

   ```yaml
   apiVersion: storage.k8s.io/v1
   kind: StorageClass
   metadata:
     name: gp3-custom
   provisioner: ebs.csi.aws.com
   volumeBindingMode: WaitForFirstConsumer
   allowVolumeExpansion: true
   parameters:
     type: gp3
     iops: "3000"
     throughput: "125"
     encrypted: "true"
   ---
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: app-data-pvc
     namespace: my-app
   spec:
     accessModes: [ReadWriteOnce]
     storageClassName: gp3-custom
     resources:
       requests:
         storage: 20Gi
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: storage-pod
     namespace: my-app
   spec:
     containers:
       - name: app
         image: ubi9/ubi
         command: ["sh", "-c", "echo data > /data/test.log && sleep 3600"]
         volumeMounts:
           - mountPath: /data
             name: data-volume
     volumes:
       - name: data-volume
         persistentVolumeClaim:
           claimName: app-data-pvc
   ```

2. Wait for bind and run:

   ```bash
   oc get pvc app-data-pvc -n my-app
   oc exec -n my-app storage-pod -- cat /data/test.log
   ```

3. Confirm EBS volume in AWS:

   ```bash
   PV="$(oc get pvc app-data-pvc -n my-app -o jsonpath='{.spec.volumeName}')"
   oc get pv "${PV}" -o jsonpath='{.spec.csi.volumeHandle}{"\n"}'
   ```

## Expected output

- PVC `Bound`
- Pod `Running`
- File content `data`

## Success criteria

```bash
oc get pvc app-data-pvc -n my-app -o jsonpath='{.status.phase}' | grep -q Bound
oc exec -n my-app storage-pod -- test -f /data/test.log
```

## Failure signals

- PVC `Pending` → CSI driver, AZ capacity, or StorageClass typo.
- Pod stuck `ContainerCreating` → volume attach / node in same AZ.
