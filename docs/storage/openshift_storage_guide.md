# OpenShift Storage Options Matrix and Setup Guide

## Table of Contents
1. [Storage Options Comparison Matrix](#storage-options-comparison-matrix)
2. [ROSA (AWS) Storage Setup](#rosa-aws-storage-setup)
   - [EBS Storage Setup](#1-ebs-storage-setup)
   - [EFS Setup for Shared Storage](#2-efs-setup-for-shared-storage)
   - [Testing ROSA Storage](#3-testing-rosa-storage)
3. [ARO (Azure) Storage Setup](#aro-azure-storage-setup)
   - [Azure Disk Storage Setup](#1-azure-disk-storage-setup)
   - [Azure Files Setup](#2-azure-files-setup)
   - [Azure NetApp Files Setup](#3-azure-netapp-files-setup)
   - [Testing ARO Storage](#4-testing-aro-storage)
4. [Validation and Testing Scripts](#validation-and-testing-scripts)
5. [Troubleshooting Common Issues](#troubleshooting-common-issues)

---

## Prerequisites

Before following this guide, ensure you have:

- **OpenShift Cluster**: ROSA or ARO cluster with cluster admin access
- **CLI Tools**: 
  - `oc` (OpenShift CLI) installed and authenticated
  - `aws` CLI (for ROSA) or `az` CLI (for ARO) installed and configured
- **Permissions**: 
  - Cluster admin role on OpenShift
  - Appropriate cloud provider permissions (IAM roles for AWS, RBAC for Azure)
- **OpenShift Version**: OpenShift 4.8+ (CSI drivers are included by default)
  - **Tested with**: OpenShift 4.10, 4.11, 4.12, 4.13, 4.14
- **Network Access**: Ability to access cloud provider APIs from cluster nodes

## Version Compatibility

This guide is tested and validated with:
- **OpenShift**: 4.10 - 4.14
- **ROSA**: All supported ROSA versions
- **ARO**: All supported ARO versions
- **CSI Drivers**: 
  - AWS EBS CSI Driver: v1.27+ (included with ROSA)
  - AWS EFS CSI Driver: v1.7+ (via OperatorHub)
  - Azure Disk CSI Driver: v1.27+ (included with ARO)
  - Azure Files CSI Driver: v1.27+ (included with ARO)

## Storage Options Comparison Matrix

| Storage Type | ROSA (AWS) | ARO (Azure) | Performance | Use Cases | Access Mode | Cost |
|--------------|------------|-------------|-------------|-----------|-------------|------|
| **Block Storage** | EBS gp3, io1, io2 | Azure Disk Premium/Ultra | High IOPS, Low Latency | Databases, VMs | RWO | Medium-High |
| **File Storage** | EFS | Azure Files Premium | Medium, Shared Access | Shared configs, logs | RWX | Medium |
| **High-Performance File** | FSx Lustre | Azure NetApp Files | Very High | HPC, Analytics | RWX | High |
| **Object Storage** | S3 (via CSI) | Azure Blob (via CSI) | Variable | Backups, Archives | N/A | Low |
| **Local/Ephemeral** | Instance Store | Local SSD | Highest | Caching, Temp data | RWO | Low |

## ROSA (AWS) Storage Setup {#rosa-aws-storage-setup}

### 1. EBS Storage Setup

#### Prerequisites
```bash
# Verify ROSA cluster is running
rosa describe cluster <cluster-name>

# Check existing storage classes
oc get storageclass
```

#### Create Custom EBS Storage Classes

**GP3 Storage Class (General Purpose)**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-csi
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
```

**IO2 Storage Class (High Performance)**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: io2-csi
provisioner: ebs.csi.aws.com
parameters:
  type: io2
  iops: "10000"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
```

#### Apply Storage Classes
```bash
# Apply the storage classes
oc apply -f gp3-storageclass.yaml
oc apply -f io2-storageclass.yaml

# Verify creation
oc get storageclass
```

### 2. EFS Setup for Shared Storage

#### Install EFS CSI Driver
```bash
# Create the EFS CSI driver
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: aws-efs-csi-driver
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: aws-efs-csi-driver
  namespace: aws-efs-csi-driver
spec:
  targetNamespaces:
  - aws-efs-csi-driver
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: aws-efs-csi-driver-operator
  namespace: aws-efs-csi-driver
spec:
  channel: stable
  name: aws-efs-csi-driver-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

#### Create EFS File System (AWS CLI)
```bash
# Get VPC ID from ROSA cluster
VPC_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*rosa*" \
  --query 'Reservations[0].Instances[0].VpcId' \
  --output text)

# Create EFS file system
EFS_ID=$(aws efs create-file-system \
  --creation-token rosa-efs-$(date +%s) \
  --throughput-mode provisioned \
  --provisioned-throughput-in-mibps 500 \
  --encrypted \
  --query 'FileSystemId' \
  --output text)

echo "EFS ID: $EFS_ID"

# Get subnet IDs
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[?MapPublicIpOnLaunch==`false`].SubnetId' \
  --output text)

# Create mount targets
for subnet in $SUBNET_IDS; do
  aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id $subnet \
    --security-groups $(aws ec2 describe-security-groups \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*worker*" \
      --query 'SecurityGroups[0].GroupId' --output text)
done
```

#### Create EFS Storage Class
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-xxxxxxxxx  # Replace with your EFS ID from AWS console or CLI
  directoryPerms: "700"
volumeBindingMode: Immediate
reclaimPolicy: Delete
```

### 3. Testing ROSA Storage

#### Test EBS Storage
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3-csi
  resources:
    requests:
      storage: 20Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: ebs-test-pod
spec:
  containers:
  - name: test-container
    image: nginx
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: ebs-test-pvc
```

#### Test EFS Storage
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-test-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: efs-test-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: efs-test
  template:
    metadata:
      labels:
        app: efs-test
    spec:
      containers:
      - name: test-container
        image: nginx
        volumeMounts:
        - name: efs-storage
          mountPath: /shared-data
      volumes:
      - name: efs-storage
        persistentVolumeClaim:
          claimName: efs-test-pvc
```

## ARO (Azure) Storage Setup {#aro-azure-storage-setup}

### 1. Azure Disk Storage Setup

#### Check Default Storage Classes
```bash
# Check existing storage classes
oc get storageclass

# Default classes in ARO:
# - managed-csi (Standard_LRS)
# - managed-premium (Premium_LRS)
```

#### Create Custom Azure Disk Storage Classes

**Premium SSD Storage Class**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-premium-ssd
provisioner: disk.csi.azure.com
parameters:
  skuName: Premium_LRS
  cachingmode: ReadOnly
  kind: Managed
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

**Ultra SSD Storage Class (High Performance)**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-ultra-ssd
provisioner: disk.csi.azure.com
parameters:
  skuName: UltraSSD_LRS
  cachingmode: None
  diskIOPSReadWrite: "2000"
  diskMBpsReadWrite: "125"
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

### 2. Azure Files Setup

#### Install Azure Files CSI Driver (if not present)
```bash
# Check if Azure Files CSI driver is installed
oc get csidriver files.csi.azure.com

# If not present, install via operator
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: azure-file-csi-driver-operator
  namespace: openshift-cluster-csi-drivers
spec:
  channel: stable
  name: azure-file-csi-driver-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

#### Create Azure Files Storage Class
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-files-premium
provisioner: file.csi.azure.com
parameters:
  skuName: Premium_LRS
  protocol: smb
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
```

### 3. Azure NetApp Files Setup

#### Prerequisites
```bash
# Register Azure NetApp Files provider (run in Azure CLI)
az provider register --namespace Microsoft.NetApp
az provider show --namespace Microsoft.NetApp
```

#### Create NetApp Account and Pool (Azure CLI)
```bash
# Set variables
RESOURCE_GROUP="aro-rg"
LOCATION="eastus"
ANF_ACCOUNT="aro-anf-account"
POOL_NAME="aro-pool"
VNET_NAME="aro-vnet"
SUBNET_NAME="anf-subnet"

# Create NetApp account
az netappfiles account create \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --account-name $ANF_ACCOUNT

# Create capacity pool
az netappfiles pool create \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --account-name $ANF_ACCOUNT \
  --pool-name $POOL_NAME \
  --size 4 \
  --service-level Premium

# Create dedicated subnet for ANF
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name $SUBNET_NAME \
  --address-prefixes 10.0.5.0/24 \
  --delegations Microsoft.NetApp/volumes
```

#### Install Astra Trident for NetApp Files
```bash
# Download and install Trident
curl -L https://github.com/NetApp/trident/releases/download/v23.04.0/trident-installer-23.04.0.tar.gz -o trident-installer.tar.gz
tar -xf trident-installer.tar.gz
cd trident-installer

# Install Trident operator
oc create ns trident
oc apply -f deploy/crds/trident.netapp.io_tridentorchestrators_crd_post1.16.yaml
oc apply -f deploy/bundle.yaml

# Create TridentOrchestrator
cat <<EOF | oc apply -f -
apiVersion: trident.netapp.io/v1
kind: TridentOrchestrator
metadata:
  name: trident
spec:
  debug: true
  namespace: trident
EOF
```

### 4. Testing ARO Storage

#### Test Azure Disk Storage
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: azure-disk-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: azure-premium-ssd
  resources:
    requests:
      storage: 32Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: azure-disk-test
spec:
  containers:
  - name: test-container
    image: nginx
    volumeMounts:
    - name: disk-storage
      mountPath: /data
  volumes:
  - name: disk-storage
    persistentVolumeClaim:
      claimName: azure-disk-pvc
```

#### Test Azure Files Storage
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: azure-files-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: azure-files-premium
  resources:
    requests:
      storage: 100Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azure-files-test
spec:
  replicas: 3
  selector:
    matchLabels:
      app: files-test
  template:
    metadata:
      labels:
        app: files-test
    spec:
      containers:
      - name: test-container
        image: nginx
        volumeMounts:
        - name: files-storage
          mountPath: /shared
      volumes:
      - name: files-storage
        persistentVolumeClaim:
          claimName: azure-files-pvc
```

## Validation and Testing Scripts

### Storage Performance Testing

#### Basic I/O Test
```bash
# Test script for storage performance
cat <<'EOF' > storage-perf-test.yaml
apiVersion: v1
kind: Pod
metadata:
  name: storage-perf-test
spec:
  containers:
  - name: perf-test
    image: ubuntu:20.04
    command: ["/bin/bash"]
    args:
    - -c
    - |
      apt-get update && apt-get install -y fio
      echo "Testing sequential write performance..."
      fio --name=seqwrite --ioengine=libaio --rw=write --bs=1M --size=1G --numjobs=1 --filename=/data/testfile
      echo "Testing random read performance..."
      fio --name=randread --ioengine=libaio --rw=randread --bs=4k --size=1G --numjobs=4 --filename=/data/testfile
      sleep 3600
    volumeMounts:
    - name: test-storage
      mountPath: /data
  volumes:
  - name: test-storage
    persistentVolumeClaim:
      claimName: <your-pvc-name>  # Replace with your actual PVC name
EOF
```

#### Multi-Pod Shared Storage Test
```bash
# Test shared storage across multiple pods
cat <<'EOF' > shared-storage-test.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shared-storage-test
spec:
  replicas: 3
  selector:
    matchLabels:
      app: shared-test
  template:
    metadata:
      labels:
        app: shared-test
    spec:
      containers:
      - name: writer
        image: busybox
        command: ["/bin/sh"]
        args:
        - -c
        - |
          while true; do
            echo "$(date): $(hostname)" >> /shared/test.log
            sleep 10
          done
        volumeMounts:
        - name: shared-vol
          mountPath: /shared
      volumes:
      - name: shared-vol
        persistentVolumeClaim:
          claimName: <your-rwx-pvc-name>  # Replace with your ReadWriteMany PVC name
EOF
```

### Monitoring and Validation Commands

```bash
# Check PVC status
oc get pvc

# Check PV details
oc get pv

# Check storage class details
oc describe storageclass <storage-class-name>

# Monitor storage usage
oc exec -it <pod-name> -- df -h /data

# Check CSI driver logs
oc logs -n kube-system -l app=csi-driver

# Validate volume attachment
oc describe pod <pod-name> | grep -A 10 Volumes

# Test storage expansion (if supported)
oc patch pvc <pvc-name> -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'
```

## Troubleshooting Common Issues

### ROSA Storage Issues
1. **EBS Volume Mount Failures**: Check IAM permissions and node security groups
2. **EFS Connection Issues**: Verify security group rules allow NFS traffic (port 2049)
3. **Storage Class Not Found**: Ensure CSI drivers are properly installed

### ARO Storage Issues
1. **Azure Disk Attachment Failures**: Check VM SKU limits and availability zones
2. **Azure Files Mount Issues**: Verify storage account and network connectivity
3. **Permission Denied**: Check security context and fsGroup settings

### General Validation Steps
1. Verify storage driver installation: `oc get csidriver`
2. Check storage class availability: `oc get storageclass`
3. Monitor PVC binding: `oc get pvc -w`
4. Validate pod startup: `oc describe pod <pod-name>`
5. Test actual I/O operations within pods

## Security Considerations

### Encryption

**At Rest:**
- **EBS (ROSA)**: Enable encryption in storage class parameters (`encrypted: "true"`)
- **Azure Disk**: Encryption at rest is enabled by default for managed disks
- **EFS (ROSA)**: Enable encryption in EFS file system configuration
- **Azure Files**: Encryption at rest is enabled by default

**In Transit:**
- All CSI driver communications use TLS
- EFS uses encrypted NFS connections (TLS 1.2+)
- Azure Files supports SMB 3.0+ with encryption

### Access Control

**IAM/RBAC:**
- **ROSA**: Ensure IAM roles for worker nodes have minimal required permissions
- **ARO**: Use managed identity with least privilege RBAC assignments
- Limit cluster admin access to storage operations
- Use namespace-level permissions where possible

**Network Security:**
- Configure security groups (AWS) or NSGs (Azure) to restrict storage access
- Use VPC endpoints (AWS) or Private Endpoints (Azure) for storage access
- Enable network policies in OpenShift to restrict pod-to-storage communication

### Secret Management

- Store cloud credentials in OpenShift secrets (not in YAML files)
- Use external secret management (e.g., Sealed Secrets, Vault) for production
- Rotate credentials regularly
- Never commit credentials to version control

### Best Practices

1. **Use separate storage accounts/resource groups** for production workloads
2. **Enable audit logging** for storage operations
3. **Implement backup strategies** before production deployment
4. **Test disaster recovery procedures** regularly
5. **Monitor storage usage** to prevent unexpected costs
6. **Use resource quotas** to limit storage consumption per namespace
7. **Review and update security policies** regularly

## Validation Checklist

Use this checklist to validate your storage setup:

### Pre-Deployment
- [ ] Verified OpenShift version compatibility
- [ ] Confirmed CSI drivers are installed and running
- [ ] Validated cloud provider permissions/roles
- [ ] Reviewed security requirements (encryption, access control)
- [ ] Tested in non-production environment first

### Storage Class Configuration
- [ ] Storage classes created and verified (`oc get storageclass`)
- [ ] Default storage class set appropriately
- [ ] Parameters configured correctly (encryption, performance tiers)
- [ ] Volume binding mode appropriate for use case

### PVC Creation
- [ ] PVC created successfully (`oc get pvc`)
- [ ] PVC bound to PV (`oc get pvc` shows Bound status)
- [ ] PV created in cloud provider (verify in AWS/Azure console)
- [ ] Storage size matches request

### Pod Integration
- [ ] Pod scheduled successfully with PVC mounted
- [ ] Volume mounted at expected path (`oc exec pod -- df -h`)
- [ ] Read/write permissions correct
- [ ] Data persists across pod restarts

### Performance Testing
- [ ] Baseline performance metrics recorded
- [ ] IOPS meet workload requirements
- [ ] Latency acceptable for application needs
- [ ] Throughput sufficient for data transfer

### Security Validation
- [ ] Encryption enabled and verified
- [ ] Access controls properly configured
- [ ] Secrets stored securely (not in plain text)
- [ ] Network policies applied (if applicable)
- [ ] Audit logging enabled

### Production Readiness
- [ ] Backup strategy implemented and tested
- [ ] Disaster recovery plan documented
- [ ] Monitoring and alerting configured
- [ ] Cost estimates reviewed
- [ ] Documentation updated with environment-specific details