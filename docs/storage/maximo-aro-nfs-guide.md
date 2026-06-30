# Maximo on Azure Red Hat OpenShift - NFS Storage Configuration Guide

This guide provides comprehensive steps to configure file attachments in Maximo on Azure Red Hat OpenShift (ARO) using NFS storage with retain reclaim policy.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Step 1: Verify NFS Storage Class Configuration](#step-1-verify-nfs-storage-class-configuration)
- [Step 2: Configure Security Context Constraints (SCC)](#step-2-configure-security-context-constraints-scc)
- [Step 3: Create or Update PVC for Maximo Attachments](#step-3-create-or-update-pvc-for-maximo-attachments)
- [Step 4: Configure Pod Security Context](#step-4-configure-pod-security-context)
- [Step 5: Verify NFS Mount Permissions](#step-5-verify-nfs-mount-permissions)
- [Step 6: Configure Maximo System Properties](#step-6-configure-maximo-system-properties)
- [Step 7: Configure SELinux Context (if needed)](#step-7-configure-selinux-context-if-needed)
- [Step 8: Verify and Test](#step-8-verify-and-test)
- [Common Issues and Solutions](#common-issues-and-solutions)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting Commands](#troubleshooting-commands)

---

## Prerequisites

Before starting, verify your current PVC configuration:

```bash
# Check existing PVCs
oc get pvc -n <maximo-namespace>

# Describe specific PVC
oc describe pvc <pvc-name> -n <maximo-namespace>

# View PV details
oc get pv <pv-name> -o yaml
```

**Note**: Replace `<maximo-namespace>`, `<pvc-name>`, and other placeholders with your actual values throughout this guide.

---

## Step 1: Verify NFS Storage Class Configuration

### 1.1 Check Existing Storage Classes

```bash
# List all storage classes
oc get storageclass

# Describe the NFS storage class
oc describe storageclass <nfs-storage-class>
```

### 1.2 Verify Storage Class Configuration

Ensure your storage class has the correct configuration. Example:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-storage
provisioner: example.com/nfs
parameters:
  archiveOnDelete: "false"
reclaimPolicy: Retain
volumeBindingMode: Immediate
allowVolumeExpansion: true
```

**Key Requirements**:
- `reclaimPolicy: Retain` - Prevents data deletion
- Must support `ReadWriteMany` (RWX) access mode
- `allowVolumeExpansion: true` - Allows future expansion

---

## Step 2: Configure Security Context Constraints (SCC)

ARO uses strict Security Context Constraints. Maximo pods need proper SCC to write to NFS storage.

### 2.1 Check Current SCC

```bash
# Check which SCC is assigned to your Maximo pod
oc get pod <maximo-pod-name> -n <namespace> -o yaml | grep scc

# List all SCCs
oc get scc
```

### 2.2 Option A: Use anyuid SCC (Quick Solution)

```bash
# Add anyuid SCC to service account
oc adm policy add-scc-to-user anyuid -z <maximo-service-account> -n <namespace>
```

**Warning**: `anyuid` SCC may not be allowed in production environments. Use Option B for better security.

### 2.3 Option B: Create Custom SCC (Recommended)

Create a file named `maximo-scc.yaml`:

```yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: maximo-nfs-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegedContainer: false
allowedCapabilities: null
defaultAddCapabilities: null
fsGroup:
  type: RunAsAny
priority: 10
readOnlyRootFilesystem: false
requiredDropCapabilities:
- KILL
- MKNOD
- SETUID
- SETGID
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
```

Apply and bind the SCC:

```bash
# Apply the custom SCC
oc apply -f maximo-scc.yaml

# Bind SCC to service account
oc adm policy add-scc-to-user maximo-nfs-scc -z <maximo-service-account> -n <namespace>

# Verify binding
oc describe scc maximo-nfs-scc
```

---

## Step 3: Create or Update PVC for Maximo Attachments

### 3.1 Create Dedicated PVC for Attachments

Create a file named `maximo-doclinks-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: maximo-doclinks
  namespace: <maximo-namespace>
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: <nfs-storage-class>
  resources:
    requests:
      storage: 50Gi
```

### 3.2 Apply PVC

```bash
# Create the PVC
oc apply -f maximo-doclinks-pvc.yaml

# Verify PVC is bound
oc get pvc maximo-doclinks -n <namespace>

# Check PVC details
oc describe pvc maximo-doclinks -n <namespace>
```

**Expected Status**: `Status: Bound`

---

## Step 4: Configure Pod Security Context

### 4.1 Edit Maximo Deployment

```bash
# Edit the deployment
oc edit deployment <maximo-deployment> -n <namespace>
```

### 4.2 Add Security Context and Volume Configuration

Add or modify the following sections in your deployment:

```yaml
spec:
  template:
    spec:
      securityContext:
        fsGroup: 0
        runAsUser: 0
        runAsNonRoot: false
        supplementalGroups: [0, 1000]
      containers:
      - name: maximo
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          runAsNonRoot: false
          runAsUser: 0
        volumeMounts:
        - name: doclinks
          mountPath: /doclinks
          subPath: doclinks
      volumes:
      - name: doclinks
        persistentVolumeClaim:
          claimName: maximo-doclinks
```

### 4.3 Key Configuration Points

- **fsGroup: 0** - Sets the filesystem group ownership
- **runAsUser: 0** - Runs container as root (required for some NFS configurations)
- **mountPath: /doclinks** - Directory where NFS will be mounted
- **claimName: maximo-doclinks** - References the PVC created earlier

### 4.4 Save and Verify

After editing, the deployment will automatically rollout:

```bash
# Watch rollout status
oc rollout status deployment/<maximo-deployment> -n <namespace>

# Verify new pod is running
oc get pods -n <namespace>
```

---

## Step 5: Verify NFS Mount Permissions

### 5.1 Test Write Permissions

```bash
# Get the pod name
oc get pods -n <namespace>

# Execute into the Maximo pod
oc exec -it <maximo-pod-name> -n <namespace> -- /bin/bash
```

### 5.2 Inside the Pod - Test File Operations

```bash
# Navigate to the mount point
cd /doclinks

# Test write permission
touch test.txt
echo "test content" > test.txt

# List files with permissions
ls -la

# Check directory permissions
ls -ld /doclinks

# Read the file
cat test.txt

# Clean up
rm test.txt

# Exit the pod
exit
```

### 5.3 Expected Results

- You should be able to create, write, read, and delete files
- Directory permissions should show `drwxrwxrwx` or similar
- No "Permission denied" errors

### 5.4 NFS Server Configuration (If You Have Access)

If you encounter permission issues, check the NFS server exports:

```bash
# On the NFS server
cat /etc/exports

# Required configuration example:
# /path/to/nfs *(rw,sync,no_root_squash,no_all_squash)
```

**Key NFS Export Options**:
- `rw` - Read-write access
- `no_root_squash` - Preserves root user permissions
- `no_all_squash` - Preserves all user permissions
- `sync` - Synchronous writes

---

## Step 6: Configure Maximo System Properties

### 6.1 Access Maximo System Properties

1. Log into Maximo as administrator
2. Navigate to: **System Configuration > Platform Configuration > System Properties**

### 6.2 Configure Document Management Properties

Search for and configure the following properties:

| Property Name | Value | Description |
|---------------|-------|-------------|
| `mxe.doclink.path01` | `/doclinks` | Primary document storage path |
| `mxe.doclink.doctypes.topLevelPaths` | `ATTACHMENTS=Attachments` | Top-level folder structure |
| `mxe.doclink.securedAttachment` | `0` | Disable secured attachments (or 1 if needed) |
| `mxe.doclink.storage` | `FILE` | Use file system storage |

### 6.3 Additional Optional Properties

```properties
# Maximum file upload size (in MB)
mxe.doclink.maxfilesize=100

# Allowed file extensions
mxe.doclink.allowedfiletypes=pdf,doc,docx,xls,xlsx,jpg,png,txt

# Document path separator
mxe.doclink.pathseparator=/
```

### 6.4 Apply Configuration

1. Click **Save** in Maximo
2. Restart Maximo pods to apply changes:

```bash
# Restart deployment
oc rollout restart deployment/<maximo-deployment> -n <namespace>

# Wait for rollout to complete
oc rollout status deployment/<maximo-deployment> -n <namespace>

# Verify pods are running
oc get pods -n <namespace>
```

---

## Step 7: Configure SELinux Context (if needed)

If you're experiencing SELinux-related permission issues:

### 7.1 Add SELinux Options to Deployment

```bash
oc edit deployment <maximo-deployment> -n <namespace>
```

Add SELinux context:

```yaml
spec:
  template:
    spec:
      securityContext:
        seLinuxOptions:
          level: "s0:c123,c456"
          type: "svirt_sandbox_file_t"
        fsGroup: 0
        runAsUser: 0
```

### 7.2 Alternative: Update SCC

Modify your custom SCC to use `RunAsAny`:

```yaml
seLinuxContext:
  type: RunAsAny
```

---

## Step 8: Verify and Test

### 8.1 Check Pod Status

```bash
# Get pod status
oc get pods -n <namespace>

# View pod logs
oc logs <maximo-pod-name> -n <namespace>

# Follow logs in real-time
oc logs -f <maximo-pod-name> -n <namespace>
```

### 8.2 Test Attachment Upload in Maximo

1. Log into Maximo
2. Open any **Work Order**
3. Navigate to **Attachments** tab
4. Click **Attach Document**
5. Select a file and upload
6. Verify the file appears in the list

### 8.3 Verify File on Storage

```bash
# Execute into pod
oc exec -it <maximo-pod-name> -n <namespace> -- /bin/bash

# Navigate to doclinks
cd /doclinks/Attachments

# List uploaded files
ls -lR

# Exit
exit
```

### 8.4 Monitor for Errors

```bash
# Watch events
oc get events -n <namespace> --sort-by='.lastTimestamp' --watch

# Check for permission errors in logs
oc logs <maximo-pod-name> -n <namespace> | grep -i "permission\|denied\|error"
```

---

## Common Issues and Solutions

### Issue 1: Permission Denied When Writing to NFS

**Symptoms**:
- Cannot upload attachments in Maximo
- "Permission denied" errors in pod logs
- Cannot create files in `/doclinks` directory

**Solutions**:
1. Verify NFS server has `no_root_squash` option
2. Check fsGroup is set correctly (usually 0)
3. Ensure SCC allows `RunAsAny` for fsGroup
4. Verify directory ownership on NFS server

```bash
# Check on NFS server
ls -ld /path/to/nfs/export
chown -R nobody:nobody /path/to/nfs/export
chmod -R 777 /path/to/nfs/export
```

### Issue 2: Pod Can't Mount Volume

**Symptoms**:
- Pod stuck in `ContainerCreating` state
- Event shows "Unable to mount volume"

**Solutions**:
1. Verify SCC allows PVC volumes
2. Check service account has proper SCC binding
3. Ensure PVC is in `Bound` state
4. Verify NFS server is accessible from ARO nodes

```bash
# Check PVC status
oc get pvc -n <namespace>

# Check pod events
oc describe pod <maximo-pod-name> -n <namespace>

# Verify SCC binding
oc describe sa <service-account> -n <namespace>
```

### Issue 3: Files Upload but Can't Be Retrieved

**Symptoms**:
- Files upload successfully
- Error when trying to view/download attachments
- File not found errors in logs

**Solutions**:
1. Verify `mxe.doclink.path01` exactly matches mount path
2. Check path separators (use `/` not `\`)
3. Ensure file permissions are readable
4. Verify Maximo can access subdirectories

```bash
# Check file permissions
oc exec -it <maximo-pod-name> -n <namespace> -- ls -lR /doclinks
```

### Issue 4: SELinux Denials

**Symptoms**:
- `PermissionDenied` errors even with correct Unix permissions
- SELinux AVC denials in audit logs

**Solutions**:
1. Set `seLinuxContext: type: MustRunAs` in SCC
2. Use `spc_t` or `svirt_sandbox_file_t` type
3. Configure SELinux options in pod security context
4. Consider using `RunAsAny` for seLinuxContext

### Issue 5: Slow Performance

**Symptoms**:
- Slow attachment uploads/downloads
- Timeouts when accessing files

**Solutions**:
1. Check NFS server performance
2. Verify network connectivity between ARO and NFS
3. Increase NFS mount options: `rsize=8192,wsize=8192`
4. Monitor NFS server load and I/O

---

## Verification Checklist

Use this checklist to ensure proper configuration:

- [ ] **Storage Configuration**
  - [ ] PVC is bound and using ReadWriteMany access mode
  - [ ] Storage class reclaim policy is Retain
  - [ ] Storage class allows volume expansion

- [ ] **Security Configuration**
  - [ ] Service account has appropriate SCC assigned
  - [ ] SCC allows PVC volumes
  - [ ] Pod security context includes fsGroup and runAsUser
  - [ ] SELinux context is properly configured (if needed)

- [ ] **Volume Configuration**
  - [ ] Volume is mounted at correct path (e.g., /doclinks)
  - [ ] Volume mount uses correct PVC name
  - [ ] SubPath is configured if needed

- [ ] **NFS Configuration**
  - [ ] NFS exports include no_root_squash
  - [ ] NFS server is accessible from ARO nodes
  - [ ] Directory permissions allow read/write

- [ ] **Maximo Configuration**
  - [ ] System properties point to correct path
  - [ ] Document storage type is set to FILE
  - [ ] Top-level paths are configured

- [ ] **Testing**
  - [ ] Pod can create/read/delete files in mounted directory
  - [ ] Maximo logs show no permission errors
  - [ ] Can upload attachments through Maximo UI
  - [ ] Can download/view uploaded attachments

---

## Troubleshooting Commands

### General Diagnostics

```bash
# Get all resources in namespace
oc get all -n <namespace>

# Check events for errors (sorted by time)
oc get events -n <namespace> --sort-by='.lastTimestamp'

# View events with more details
oc get events -n <namespace> --sort-by='.lastTimestamp' -o wide

# Watch events in real-time
oc get events -n <namespace> --watch
```

### Pod Diagnostics

```bash
# View full pod configuration
oc get pod <pod-name> -n <namespace> -o yaml

# Check which SCC is being used
oc describe pod <pod-name> -n <namespace> | grep scc

# View pod resource usage
oc adm top pod <pod-name> -n <namespace>

# Get pod logs from previous instance
oc logs <pod-name> -n <namespace> --previous
```

### Storage Diagnostics

```bash
# List all PVCs with status
oc get pvc -n <namespace> -o wide

# Describe PVC details
oc describe pvc <pvc-name> -n <namespace>

# View PV backing the PVC
oc get pv

# Check storage class details
oc describe storageclass <storage-class-name>
```

### Security Diagnostics

```bash
# Verify service account
oc get sa <service-account> -n <namespace> -o yaml

# List SCC bindings for service account
oc describe sa <service-account> -n <namespace>

# Check all SCCs
oc get scc

# View SCC details
oc describe scc <scc-name>

# Check what SCC a pod is using
oc get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.annotations.openshift\.io/scc}'
```

### Network Diagnostics

```bash
# Test NFS connectivity from a pod
oc run -it --rm debug --image=busybox --restart=Never -n <namespace> -- sh
# Inside the debug pod:
ping <nfs-server-ip>
nc -zv <nfs-server-ip> 2049

# Check DNS resolution
nslookup <nfs-server-hostname>
```

### Deployment Diagnostics

```bash
# View deployment configuration
oc get deployment <deployment-name> -n <namespace> -o yaml

# Check deployment status
oc rollout status deployment/<deployment-name> -n <namespace>

# View deployment history
oc rollout history deployment/<deployment-name> -n <namespace>

# Undo last deployment
oc rollout undo deployment/<deployment-name> -n <namespace>
```

---

## Additional Resources

### OpenShift Documentation
- [Managing Security Context Constraints](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html)
- [Persistent Storage Using NFS](https://docs.openshift.com/container-platform/latest/storage/persistent_storage/persistent-storage-nfs.html)

### Maximo Documentation
- Maximo Application Suite documentation on IBM website
- Maximo Manage installation and configuration guides

### Support Contacts

If issues persist after following this guide:
1. Check Maximo logs for specific error messages
2. Review ARO cluster events and logs
3. Contact your OpenShift administrator for SCC/network issues
4. Contact Maximo support for application-specific issues

---

## Revision History

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-12 | 1.0 | Initial documentation |

---

**Note**: Always test configuration changes in a non-production environment first. Back up your Maximo data and configuration before making changes.