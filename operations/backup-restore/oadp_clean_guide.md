# OADP Data Mover Demo: Backup & Restore on Azure Red Hat OpenShift

## Overview

This guide demonstrates the OpenShift API for Data Protection (OADP) functionality on Azure Red Hat OpenShift (ARO) using OADP 1.4.5. OADP provides enterprise-grade backup and restore capabilities for stateful applications, including CSI volume snapshots and filesystem backups using Kopia as the uploader.

## Prerequisites

- Azure Red Hat OpenShift 4.12+ cluster
- Cluster administrator access
- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- OADP Operator 1.4.5 installed

## Part 1: Environment Setup

### 1.1 Set Environment Variables

```bash
# Set your Azure environment variables
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export AZURE_RESOURCE_GROUP="your-aro-resource-group"
export AZURE_STORAGE_ACCOUNT_ID="oadpbackupstorage$(date +%s)"
export AZURE_REGION="eastus"
```

### 1.2 Create Azure Storage Account

```bash
# Login to Azure
az login --service-principal -u $AZURE_CLIENT_ID -p $AZURE_CLIENT_SECRET --tenant $AZURE_TENANT_ID

# Create storage account for OADP backups
az storage account create \
  --name $AZURE_STORAGE_ACCOUNT_ID \
  --resource-group $AZURE_RESOURCE_GROUP \
  --location $AZURE_REGION \
  --sku Standard_GRS \
  --encryption-services blob \
  --https-only true \
  --kind BlobStorage \
  --access-tier Hot

# Create blob container
export AZURE_STORAGE_CONTAINER="oadp-backups"
az storage container create \
  --name $AZURE_STORAGE_CONTAINER \
  --account-name $AZURE_STORAGE_ACCOUNT_ID
```

### 1.3 Create OADP Credentials Secret

```bash
# Create namespace for OADP
oc create namespace openshift-adp

# Create credentials file
cat << EOF > credentials-velero
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
AZURE_RESOURCE_GROUP=${AZURE_RESOURCE_GROUP}
AZURE_CLOUD_NAME=AzurePublicCloud
EOF

# Create secret in OpenShift
oc create secret generic cloud-credentials-azure \
  --namespace openshift-adp \
  --from-file cloud=credentials-velero

# Clean up credentials file
rm credentials-velero
```

## Part 2: Install and Configure OADP Operator

### 2.1 Install OADP Operator

```bash
# Create operator subscription for OADP 1.4.5
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: redhat-oadp-operator
  namespace: openshift-adp
spec:
  channel: stable-1.4
  name: redhat-oadp-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# Wait for operator to be ready
oc wait --for=condition=Ready pod -l app.kubernetes.io/name=velero -n openshift-adp --timeout=300s
```

### 2.2 Create Data Protection Application (DPA)

```bash
# Create DPA with OADP 1.4.5 configuration
cat << EOF | oc apply -f -
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: oadp-dpa
  namespace: openshift-adp
spec:
  configuration:
    velero:
      defaultPlugins:
        - azure
        - csi
      featureFlags:
        - EnableCSI
    nodeAgent:
      enable: true
      uploaderType: kopia
      podConfig:
        resourceAllocations:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
    name: azure-backup-location
  backupLocations:
    - velero:
        provider: azure
        default: true
        credential:
          key: cloud
          name: cloud-credentials-azure
        config:
          resourceGroup: ${AZURE_RESOURCE_GROUP}
          storageAccount: ${AZURE_STORAGE_ACCOUNT_ID}
          subscriptionId: ${AZURE_SUBSCRIPTION_ID}
        objectStorage:
          bucket: ${AZURE_STORAGE_CONTAINER}
          prefix: velero
  snapshotLocations:
    - velero:
        provider: azure
        config:
          resourceGroup: ${AZURE_RESOURCE_GROUP}
          subscriptionId: ${AZURE_SUBSCRIPTION_ID}
      name: azure-snapshot-location
EOF
```

### 2.3 Create VolumeSnapshotClass for CSI Snapshots

```bash
# Create Azure Disk VolumeSnapshotClass
cat << EOF | oc apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-azuredisk-vsc
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: disk.csi.azure.com
deletionPolicy: Delete
parameters:
  incremental: "true"
EOF
```

### 2.4 Verify OADP Installation

```bash
# Check DPA status
oc get dpa -n openshift-adp

# Verify all pods are running
oc get pods -n openshift-adp

# Check backup storage location (note the actual name may be different)
oc get backupstoragelocations -n openshift-adp

# Check volume snapshot location
oc get volumesnapshotlocations -n openshift-adp

# Verify VolumeSnapshotClass
oc get volumesnapshotclasses
```

## Part 3: Deploy Demo Application

### 3.1 Create Demo Namespace and Application

```bash
# Create demo namespace
oc create namespace oadp-demo

# Deploy OpenShift-compatible application with persistent storage
cat << EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-pvc
  namespace: oadp-demo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: managed-csi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: oadp-demo
  labels:
    app: demo-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
      annotations:
        backup.velero.io/backup-volumes: data-volume
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: demo-app
        image: registry.redhat.io/ubi8/httpd-24:latest
        ports:
        - containerPort: 8080
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          capabilities:
            drop:
              - ALL
        volumeMounts:
        - name: data-volume
          mountPath: /var/www/html
        - name: tmp-volume
          mountPath: /tmp
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
      volumes:
      - name: data-volume
        persistentVolumeClaim:
          claimName: demo-pvc
      - name: tmp-volume
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: demo-app-service
  namespace: oadp-demo
spec:
  selector:
    app: demo-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: ClusterIP
EOF
```

### 3.2 Add Test Data

```bash
# Wait for deployment to be ready
oc rollout status deployment/demo-app -n oadp-demo

# Add test data to the persistent volume
oc exec -n oadp-demo deployment/demo-app -- /bin/bash -c "echo '<h1>Demo Application</h1><p>Data created at $(date)</p>' > /var/www/html/index.html"
oc exec -n oadp-demo deployment/demo-app -- /bin/bash -c "echo 'Additional test file content' > /var/www/html/test.txt"
oc exec -n oadp-demo deployment/demo-app -- /bin/bash -c "mkdir -p /var/www/html/data && echo 'Sample data file' > /var/www/html/data/sample.txt"

# Verify data was created
oc exec -n oadp-demo deployment/demo-app -- ls -la /var/www/html/
```

## Part 4: Perform Backup

### 4.1 Create Backup

```bash
# Get the actual BackupStorageLocation name
BSL_NAME=$(oc get backupstoragelocations -n openshift-adp -o jsonpath='{.items[0].metadata.name}')
echo "Using BackupStorageLocation: $BSL_NAME"

# Create backup with both CSI snapshots and filesystem backup
cat << EOF | oc apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: demo-backup-complete
  namespace: openshift-adp
spec:
  includedNamespaces:
    - oadp-demo
  storageLocation: ${BSL_NAME}
  ttl: 720h0m0s
  snapshotVolumes: true
  csiSnapshotTimeout: 10m
  defaultVolumesToFsBackup: true
  includedResources:
    - persistentvolumes
    - persistentvolumeclaims
    - deployments
    - services
    - pods
    - configmaps
    - secrets
EOF
```

### 4.2 Monitor Backup Progress

```bash
# Monitor backup status
oc get backup demo-backup-complete -n openshift-adp -w

# Check backup details
oc describe backup demo-backup-complete -n openshift-adp

# Verify volume snapshots were created
oc get volumesnapshots -n oadp-demo

# Check nodeAgent pods for filesystem backup activity
oc get pods -n openshift-adp -l app.kubernetes.io/name=node-agent

# View backup logs
oc logs -l app.kubernetes.io/name=velero -n openshift-adp --tail=20
```

### 4.3 Verify Backup Completion

```bash
# Check final backup status (should be "Completed")
oc get backup demo-backup-complete -n openshift-adp -o jsonpath='{.status.phase}'

# List all volume snapshots
oc get volumesnapshots -n oadp-demo
```

## Part 5: Simulate Disaster and Restore

### 5.1 Simulate Data Loss

```bash
# Delete the entire namespace to simulate disaster
oc delete namespace oadp-demo

# Verify namespace is gone
oc get namespace oadp-demo
```

### 5.2 Perform Restore

```bash
# Create restore from backup
cat << EOF | oc apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: demo-restore-complete
  namespace: openshift-adp
spec:
  backupName: demo-backup-complete
  includedNamespaces:
    - oadp-demo
  restorePVs: true
  existingResourcePolicy: update
EOF

# Monitor restore progress
oc get restore demo-restore-complete -n openshift-adp -w

# Check restore details
oc describe restore demo-restore-complete -n openshift-adp
```

### 5.3 Verify Restore Success

```bash
# Check if namespace was recreated
oc get namespace oadp-demo

# Verify pods are running
oc get pods -n oadp-demo

# Check PVC restoration
oc get pvc -n oadp-demo

# Verify data was restored
oc exec -n oadp-demo deployment/demo-app -- cat /var/www/html/index.html
oc exec -n oadp-demo deployment/demo-app -- cat /var/www/html/test.txt
oc exec -n oadp-demo deployment/demo-app -- cat /var/www/html/data/sample.txt

# Test application functionality
oc port-forward -n oadp-demo svc/demo-app-service 8080:80 &
curl http://localhost:8080
kill %1
```

## Part 6: Cleanup

### 6.1 Clean Demo Resources

```bash
# Delete demo application
oc delete namespace oadp-demo

# Delete backups and restores
oc delete backup demo-backup-complete -n openshift-adp
oc delete restore demo-restore-complete -n openshift-adp

# Delete volume snapshots (if any remain)
oc delete volumesnapshots --all -n oadp-demo 2>/dev/null || true
```

### 6.2 Optional: Remove OADP Operator

```bash
# Delete DPA (this will remove velero and nodeAgent pods)
oc delete dpa oadp-dpa -n openshift-adp

# Delete VolumeSnapshotClass
oc delete volumesnapshotclass csi-azuredisk-vsc

# Uninstall operator (optional)
oc delete subscription redhat-oadp-operator -n openshift-adp

# Delete namespace (optional)
oc delete namespace openshift-adp
```

### 6.3 Clean Azure Resources

```bash
# Delete Azure storage account (optional)
az storage account delete \
  --name $AZURE_STORAGE_ACCOUNT_ID \
  --resource-group $AZURE_RESOURCE_GROUP \
  --yes
```

## Troubleshooting

### Common Issues and Solutions

**1. BackupStorageLocation not found**
```bash
# Check if BSL exists
oc get backupstoragelocations -n openshift-adp

# If missing, check DPA status
oc describe dpa oadp-dpa -n openshift-adp

# Check Velero logs
oc logs -l app.kubernetes.io/name=velero -n openshift-adp
```

**2. No Volume Snapshots Created**
```bash
# Verify VolumeSnapshotClass exists
oc get volumesnapshotclasses

# Check if snapshot controllers are running
oc get pods -n openshift-cluster-storage-operator | grep snapshot

# Test manual snapshot creation
oc create -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-snapshot
  namespace: oadp-demo
spec:
  volumeSnapshotClassName: csi-azuredisk-vsc
  source:
    persistentVolumeClaimName: demo-pvc
EOF
```

**3. Backup Fails with Validation Error**
```bash
# Check backup for validation errors
oc describe backup <backup-name> -n openshift-adp

# Common fixes:
# - Ensure correct storageLocation name in backup spec
# - Verify credentials secret exists and is correct
# - Check Azure permissions
```

**4. Restore Fails with Resource Policy Error**
```bash
# Use correct existingResourcePolicy values:
# - "none" (default): fail if resource exists
# - "update": update existing resource
```

### Monitoring Commands

```bash
# Monitor OADP components
oc get pods -n openshift-adp

# Check backup/restore status
oc get backup,restore -n openshift-adp

# View detailed logs
oc logs -l app.kubernetes.io/name=velero -n openshift-adp -f

# Monitor nodeAgent activity
oc logs -l app.kubernetes.io/name=node-agent -n openshift-adp -f

# Check Azure storage
az storage blob list --account-name $AZURE_STORAGE_ACCOUNT_ID --container-name $AZURE_STORAGE_CONTAINER
```

## Key Features Demonstrated

✅ **Enterprise Backup & Restore**: Complete application data protection  
✅ **CSI Volume Snapshots**: Native Azure Disk snapshots for fast recovery  
✅ **Filesystem Backup with Kopia**: File-level backup using modern deduplication  
✅ **Cross-Region Protection**: Azure GRS storage for geographic redundancy  
✅ **OpenShift Security**: Compatible with OpenShift security context constraints  
✅ **Automated Workflows**: Simple backup and restore operations  
✅ **Disaster Recovery**: Complete namespace and data restoration  

This demo showcases OADP's enterprise-grade capabilities for protecting stateful workloads on Azure Red Hat OpenShift, ensuring business continuity and data protection compliance.


Yes, absolutely! The method demonstrated in this guide **already includes** persistent storage volume backup through multiple approaches. Let me clarify the different ways OADP backs up persistent storage:

## How OADP Backs Up Persistent Storage

### 1. **CSI Volume Snapshots** (What we demonstrated)
```bash
# This creates Azure Disk snapshots at the storage layer
snapshotVolumes: true
csiSnapshotTimeout: 10m
```
- Creates native Azure Disk snapshots
- Fast backup and restore (snapshot-based)
- Storage-efficient (only changed blocks)
- **Best for**: Large volumes, fast recovery requirements

### 2. **Filesystem Backup with Kopia** (Also demonstrated)
```bash
# This backs up files from inside the persistent volume
defaultVolumesToFsBackup: true
# Plus the pod annotation:
backup.velero.io/backup-volumes: data-volume
```
- Backs up actual file content to object storage
- Uses Kopia for deduplication and compression
- **Best for**: Cross-region portability, long-term retention

### 3. **Both Methods Together** (Recommended - what our demo does)
Our backup spec includes both:
```yaml
spec:
  snapshotVolumes: true              # CSI snapshots
  defaultVolumesToFsBackup: true     # Filesystem backup
```

## Different PV Backup Scenarios

### Scenario 1: Standard PVC (like our demo)
```yaml
# Works with any PVC using CSI-compatible storage class
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
  storageClassName: managed-csi  # Azure Disk CSI
```

### Scenario 2: Database Volumes
```yaml
# For databases, you might want both snapshot + filesystem backup
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
spec:
  template:
    metadata:
      annotations:
        # Force filesystem backup for database files
        backup.velero.io/backup-volumes: database-storage
    spec:
      containers:
      - name: postgres
        volumeMounts:
        - name: database-storage
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: database-storage
        persistentVolumeClaim:
          claimName: postgres-pvc
```

### Scenario 3: Multiple PVCs per Application
```yaml
# Backup multiple volumes in one application
metadata:
  annotations:
    # Comma-separated list of volumes to backup
    backup.velero.io/backup-volumes: app-data,app-config,app-logs
```

## Backup Options for Different Storage Types

### Azure Disk (managed-csi)
- ✅ **CSI Snapshots**: Native Azure snapshots
- ✅ **Filesystem Backup**: File-level backup
- **Best**: Use both for maximum protection

### Azure Files (file.csi.azure.com)
- ❌ **CSI Snapshots**: Not supported for Azure Files
- ✅ **Filesystem Backup**: Use filesystem backup only
```yaml
spec:
  snapshotVolumes: false
  defaultVolumesToFsBackup: true
```

### NFS or Other Storage
- **Depends on CSI driver support**
- **Fallback**: Always use filesystem backup

## Practical Example: Backing Up Different PV Types

```bash
# Create backup with specific volume targeting
cat << EOF | oc apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: multi-pv-backup
  namespace: openshift-adp
spec:
  includedNamespaces:
    - my-app-namespace
  storageLocation: ${BSL_NAME}
  
  # For Azure Disk PVCs - use snapshots
  snapshotVolumes: true
  csiSnapshotTimeout: 10m
  
  # For all PVCs - also do filesystem backup
  defaultVolumesToFsBackup: true
  
  # Optional: Exclude specific volumes from filesystem backup
  # defaultVolumesToRestic: false
  # Then use pod annotations for selective backup
EOF
```

## Volume-Specific Backup Control

### Option 1: Selective Volume Backup (Pod Annotations)
```bash
# Only backup specific volumes from a pod
oc annotate pod my-app backup.velero.io/backup-volumes=data-volume,config-volume

# Exclude specific volumes
oc annotate pod my-app backup.velero.io/backup-volumes-excludes=temp-volume,cache-volume
```

### Option 2: StorageClass-Based Selection
```bash
# Backup only PVCs with specific storage classes
cat << EOF | oc apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: premium-storage-backup
spec:
  labelSelector:
    matchLabels:
      backup.include: "true"
  # Add label to PVCs you want to backup
EOF
```

## Summary

**Yes, you can use the same OADP method to backup any persistent storage volume.** The method we demonstrated works for:

- ✅ Azure Disk PVCs (managed-csi)
- ✅ Azure Files PVCs  
- ✅ Any CSI-compatible storage
- ✅ Database volumes
- ✅ Application data volumes
- ✅ Multiple PVCs per application
- ✅ Mixed storage types in same backup

The key is choosing the right combination of:
1. **CSI Snapshots** (`snapshotVolumes: true`) - when supported
2. **Filesystem Backup** (`defaultVolumesToFsBackup: true`) - always works
3. **Pod Annotations** - for fine-grained control

Would you like me to show you a specific example for a particular type of persistent volume or application?
