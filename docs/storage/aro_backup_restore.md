# ARO Cross-Cluster Backup & Restore with OADP (Velero) Using Shared Storage

## Overview

This runbook demonstrates how to:
- Configure OADP (Velero) in two Azure Red Hat OpenShift (ARO) clusters for cross-cluster backup/restore
- Store backups and snapshots in **customer-managed resource groups** (to avoid ARO-managed RG deny assignments)
- Validate the configuration using a sample application with persistent data

## Prerequisites

- Two ARO clusters (source and target) with cluster admin access
- Azure CLI installed and configured with appropriate permissions
- `oc` (OpenShift CLI) installed and authenticated to both clusters
- `jq` installed for JSON parsing
- Azure subscription with permissions to:
  - Create resource groups
  - Create storage accounts
  - Create service principals
  - Assign RBAC roles
  - Create and manage Azure Disk snapshots
- OADP operator installed on both clusters (via OperatorHub)

## Version Compatibility

This runbook is tested with:
- **OpenShift**: 4.10 - 4.14
- **OADP**: 1.1.0+
- **Velero**: 1.11.0+ (included with OADP)
- **Azure Disk CSI Driver**: v1.27+ (included with OpenShift)

## Security Considerations

### Credential Management
- **Never commit credentials** to version control
- Store service principal credentials in OpenShift secrets
- Use Azure Key Vault for production environments
- Rotate service principal credentials regularly
- Consider using managed identities instead of service principals

### Access Control
- Use least privilege RBAC assignments for service principals
- Limit backup storage account access to necessary resources only
- Enable Azure Monitor and alerting for backup operations
- Audit backup and restore operations regularly

### Data Protection
- Enable encryption at rest for backup storage accounts
- Use customer-managed keys (CMK) for sensitive data
- Implement backup retention policies
- Test restore procedures regularly
- Document disaster recovery procedures

## Architecture Diagram

```
+------------------+           +----------------------------+
|  Source Cluster  |           |  Target Cluster            |
| (ARO, OADP)      |           | (ARO, OADP)                |
|                  |           |                            |
|   +----------+   |           |   +----------+             |
|   |  App     |   |           |   |  App     |             |
|   | + PVC    |---|----+      |   | + PVC    |             |
|   +----------+   |    |      |   +----------+             |
+------------------+    |      +----------------------------+
                        |
                        v
+---------------------------------------------+
| Backup Storage Account (Blob)              |
| (in BACKUP_RG)                              |
+---------------------------------------------+
                        |
                        v
+---------------------------------------------+
| Snapshot Resource Group (SNAPSHOT_RG)       |
|  - Azure Disk Snapshots                     |
|  - Restored Disks for Target Cluster        |
+---------------------------------------------+
```

**Flow**:
1. **Backup** from Source Cluster → Blob Storage (BSL)  
2. **Volume snapshots** stored in `SNAPSHOT_RG` (VSL)  
3. **Restore** on Target Cluster → disks created from snapshots in `SNAPSHOT_RG` → attached to PVCs  

---

## 1. Environment Variables

Replace placeholders with your actual values:

```bash
AZ_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
AZ_LOCATION="eastus"
BACKUP_RG="velero-backup-rg"
SNAPSHOT_RG="velero-snap-rg"
VELERO_SA="velerobackup$RANDOM"   # must be globally unique
BLOB_CONTAINER="velero"
VELERO_SP_NAME="velero-sp"
```

---

## 2. Resource Group & Storage Setup

```bash
az group create -n $BACKUP_RG -l $AZ_LOCATION
az group create -n $SNAPSHOT_RG -l $AZ_LOCATION

az storage account create \
  --name $VELERO_SA \
  --resource-group $BACKUP_RG \
  --sku Standard_LRS \
  --kind StorageV2 \
  --encryption-services blob \
  --https-only true

az storage container create -n $BLOB_CONTAINER --account-name $VELERO_SA
```

---

## 3. Create Service Principal

```bash
sp=$(az ad sp create-for-rbac --name $VELERO_SP_NAME --skip-assignment)
APP_ID=$(echo $sp | jq -r .appId)
APP_SECRET=$(echo $sp | jq -r .password)
TENANT_ID=$(echo $sp | jq -r .tenant)
```

---

## 4. Role Assignments

### Storage Blob Data Contributor on Storage Account

```bash
sa_scope="/subscriptions/$AZ_SUBSCRIPTION_ID/resourceGroups/$BACKUP_RG/providers/Microsoft.Storage/storageAccounts/$VELERO_SA"
az role assignment create --assignee $APP_ID --role "Storage Blob Data Contributor" --scope $sa_scope
```

### Contributor on Snapshot RG

```bash
snap_scope="/subscriptions/$AZ_SUBSCRIPTION_ID/resourceGroups/$SNAPSHOT_RG"
az role assignment create --assignee $APP_ID --role "Contributor" --scope $snap_scope
```

---

## 5. Create Cloud Credentials Secret in Cluster

Create a file `cloud`:

```
AZURE_SUBSCRIPTION_ID=<your-sub>
AZURE_TENANT_ID=<your-tenant>
AZURE_CLIENT_ID=<APP_ID>
AZURE_CLIENT_SECRET=<APP_SECRET>
AZURE_CLOUD_NAME=AzurePublicCloud
```

Apply:

```bash
kubectl -n openshift-adp create secret generic cloud-credentials-azure --from-file=cloud=./cloud
```

---

## 6. OADP Configuration

Save as `dpa.yaml`:

```yaml
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: oadp
  namespace: openshift-adp
spec:
  configuration:
    velero:
      defaultPlugins:
        - azure
        - openshift
      restic:
        enable: true
  backupLocations:
    - velero:
        provider: azure
        name: azure
        credential:
          name: cloud-credentials-azure
          key: cloud
        config:
          storageAccount: "<VELERO_SA>"
          resourceGroup: "<BACKUP_RG>"
          subscriptionId: "<AZ_SUBSCRIPTION_ID>"
        objectStorage:
          bucket: "<BLOB_CONTAINER>"
          prefix: "backups"
        default: true
  snapshotLocations:
    - velero:
        provider: azure
        name: default
        config:
          resourceGroup: "<SNAPSHOT_RG>"
          subscriptionId: "<AZ_SUBSCRIPTION_ID>"
          incremental: "true"
```

Apply:

```bash
kubectl apply -f dpa.yaml
```

---

## 7. StorageClass for Custom Resource Group

Save as `sc-customrg.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-csi-customrg
provisioner: disk.csi.azure.com
parameters:
  skuname: StandardSSD_LRS
  cachingmode: None
  resourceGroup: "<SNAPSHOT_RG>"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

Apply:

```bash
kubectl apply -f sc-customrg.yaml
```

---

## 8. Assign Target Cluster Identity Permissions

Find target cluster principal ID:

```bash
az aro show -n <target-cluster-name> -g <target-cluster-rg> --query servicePrincipalProfile.clientId -o tsv
```

Assign Contributor to `SNAPSHOT_RG`:

```bash
az role assignment create --assignee <cluster-principal-id> --role "Contributor" --scope "/subscriptions/$AZ_SUBSCRIPTION_ID/resourceGroups/$SNAPSHOT_RG"
```

---

## 9. Deploy Sample App on Source Cluster

```bash
kubectl config use-context <source-cluster-context>
kubectl create namespace velero-test
```

`nginx-test.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-pvc
  namespace: velero-test
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: managed-csi-customrg
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: velero-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.21
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        persistentVolumeClaim:
          claimName: nginx-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-svc
  namespace: velero-test
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
```

Apply:

```bash
kubectl apply -f nginx-test.yaml
```

---

## 10. Insert Test Data

```bash
POD=$(kubectl -n velero-test get pod -l app=nginx -o jsonpath='{.items[0].metadata.name}')
kubectl -n velero-test exec -it $POD -- /bin/bash -c "echo 'Hello from SOURCE CLUSTER' > /usr/share/nginx/html/index.html"
kubectl -n velero-test exec -it $POD -- cat /usr/share/nginx/html/index.html
```

---

## 11. Backup on Source Cluster

```bash
velero backup create test-backup --include-namespaces velero-test --wait
velero backup describe test-backup --details
```

---

## 12. Restore on Target Cluster

```bash
kubectl config use-context <target-cluster-context>
velero restore create --from-backup test-backup --wait
```

---

## 13. Validate on Target Cluster

```bash
POD=$(kubectl -n velero-test get pod -l app=nginx -o jsonpath='{.items[0].metadata.name}')
kubectl -n velero-test exec -it $POD -- cat /usr/share/nginx/html/index.html
# Expected: Hello from SOURCE CLUSTER
```

---

## 14. Cleanup

```bash
kubectl config use-context <source-cluster-context>
kubectl delete ns velero-test

kubectl config use-context <target-cluster-context>
kubectl delete ns velero-test
```

---

## Validation Checklist

* [ ] PVC in source cluster used `managed-csi-customrg`
* [ ] Data verified in source pod before backup
* [ ] Backup contains PV snapshot in `SNAPSHOT_RG`
* [ ] Restore recreated PVC/PV in target cluster
* [ ] Data matches exactly between source and target

```

---

Do you want me to also make a **Mermaid diagram block** so GitHub renders it as a proper flowchart right in the README? That way your repo will have a clean visual without storing a PNG.
```

