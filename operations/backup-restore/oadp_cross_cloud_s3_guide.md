# OADP Cross-Cloud Backup & Restore — ARO ↔ ROSA HCP via S3

Configure OpenShift API for Data Protection (OADP) for **cross-cloud** disaster recovery between ARO and ROSA HCP using an **AWS S3** backup target with **Kopia/datamover** (file-level PV backup).

> **Why not CSI snapshots?** Azure Disk snapshots cannot attach to AWS EBS. Cross-cloud PV restore requires Kopia/datamover mode, not snapshot restore.

**Related:** [Cross-Cloud DR Guide](../../docs/guide/cross-cloud-dr-aro-rosa/README.md) · [ARO Backup Runbook](../../docs/storage/aro_backup_restore.md) · [DPA YAML Examples](../../examples/yaml/dpa-s3-cross-cloud.yaml)

---

## Architecture

```
┌─────────────────┐         ┌─────────────────┐
│  ARO Primary    │         │  ROSA HCP DR    │
│  OADP + Kopia   │         │  OADP + Kopia   │
└────────┬────────┘         └────────▲────────┘
         │                           │
         └──────────► S3 Bucket ◄────┘
                    (Object Lock,
                     versioning,
                     cross-account IAM)
```

Both clusters read/write the same S3 bucket. Primary backs up; DR restores.

---

## Prerequisites

- ARO and/or ROSA HCP clusters with cluster-admin access
- AWS account with S3 bucket in a region accessible from both clouds
- OpenShift 4.12+; OADP Operator 1.4+
- `oc`, `aws` CLI installed
- Cross-cloud network path to S3 (public endpoint or VPC endpoint on ROSA; ARO egress to S3)

---

## Part 1: Create S3 Backup Bucket

```bash
export AWS_REGION="us-east-1"
export BACKUP_BUCKET="openshift-cross-cloud-dr-backups"
export VELERO_IAM_USER="velero-cross-cloud"

# Create bucket with versioning and encryption
aws s3api create-bucket \
  --bucket "${BACKUP_BUCKET}" \
  --region "${AWS_REGION}" \
  $( [ "${AWS_REGION}" != "us-east-1" ] && echo "--create-bucket-configuration LocationConstraint=${AWS_REGION}" )

aws s3api put-bucket-versioning \
  --bucket "${BACKUP_BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "${BACKUP_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "aws:kms"}}]
  }'

# Optional: Object Lock for ransomware resilience (bucket must be created with ObjectLockEnabled)
# aws s3api put-object-lock-configuration ...
```

### IAM Policy (least privilege)

Create IAM user or role with access limited to the backup bucket:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::openshift-cross-cloud-dr-backups",
        "arn:aws:s3:::openshift-cross-cloud-dr-backups/*"
      ]
    }
  ]
}
```

On **ROSA HCP**, prefer IRSA for Velero instead of long-lived keys. On **ARO**, use a dedicated service principal or AWS IAM user keys stored in OpenShift secrets — scope separately from admin credentials.

---

## Part 2: Install OADP on Both Clusters

```bash
oc create namespace openshift-adp

cat <<EOF | oc apply -f -
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

oc wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=oadp-operator \
  -n openshift-adp --timeout=300s
```

---

## Part 3: Create Credentials Secret

```bash
cat <<EOF > credentials-velero
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
EOF

oc create secret generic cloud-credentials-aws \
  --namespace openshift-adp \
  --from-file cloud=credentials-velero

rm credentials-velero
```

For ROSA with IRSA, use the OADP AWS plugin with `spec.configuration.velero.defaultPlugins: [aws, openshift, csi]` and annotate the Velero service account — see [Velero AWS plugin docs](https://velero.io/docs/main/contributions/aws-config/).

---

## Part 4: Deploy DataProtectionApplication

Apply the reference manifest (edit placeholders first):

```bash
oc apply -f examples/yaml/dpa-s3-cross-cloud.yaml
```

Or create inline — **Kopia enabled, no snapshot location for cross-cloud**:

```bash
cat <<EOF | oc apply -f -
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: oadp-cross-cloud-s3
  namespace: openshift-adp
spec:
  configuration:
    velero:
      defaultPlugins:
        - aws
        - openshift
      featureFlags:
        - EnableCSI
    nodeAgent:
      enable: true
      uploaderType: kopia
  backupLocations:
    - velero:
        provider: aws
        default: true
        credential:
          key: cloud
          name: cloud-credentials-aws
        config:
          region: ${AWS_REGION}
        objectStorage:
          bucket: ${BACKUP_BUCKET}
          prefix: velero
  # No snapshotLocations — cross-cloud restore uses Kopia file backup only
EOF
```

Verify:

```bash
oc get dpa -n openshift-adp
oc get backupstoragelocation -n openshift-adp
```

---

## Part 5: Backup Schedule

```bash
oc apply -f examples/yaml/backup-schedule-cross-cloud.yaml
```

Align schedule to RPO:

| Tier | Schedule |
|------|----------|
| Tier 2 | Every 4 hours |
| Tier 1 | Every 15–60 minutes |
| Tier 3 | Daily |

---

## Part 6: Annotate Workloads for PV Backup

Add to pod template annotations:

```yaml
metadata:
  annotations:
    backup.velero.io/backup-volumes: data-volume
```

Use the volume name from the pod spec.

---

## Part 7: Cross-Cloud Restore (Primary → DR)

On the **DR cluster** (opposite cloud):

```bash
# List backups from shared S3
velero backup get

# Restore with StorageClass mapping (ARO → ROSA example)
velero restore create restore-$(date +%Y%m%d) \
  --from-backup <backup-name> \
  --storage-class-mappings managed-csi=gp3-csi-kms,managed-premium=gp3-csi-kms \
  --include-namespaces production

# Monitor restore
velero restore describe restore-$(date +%Y%m%d)
oc get pods -n production
```

Reverse mapping for ROSA → ARO restore: `gp3-csi-kms=managed-csi`.

---

## Part 8: Validation Checklist

- [ ] BackupStorageLocation phase `Available` on both clusters
- [ ] Test backup from primary completes successfully
- [ ] Test restore on DR cluster within RTO target — record time
- [ ] StorageClass mapping verified for all stateful apps
- [ ] S3 Object Lock or versioning enabled
- [ ] Backup failure alerting configured
- [ ] Credentials scoped separately from cluster admin

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| BSL unavailable | S3 credentials, bucket policy, region mismatch |
| PV not in backup | `backup.velero.io/backup-volumes` annotation missing |
| Restore PVC pending | StorageClass mapping incorrect for DR cloud |
| ARO cannot reach S3 | Egress/firewall allows `s3.<region>.amazonaws.com` |

---

## Related Files

- [`examples/yaml/dpa-s3-cross-cloud.yaml`](../../examples/yaml/dpa-s3-cross-cloud.yaml)
- [`examples/yaml/backup-schedule-cross-cloud.yaml`](../../examples/yaml/backup-schedule-cross-cloud.yaml)
- [`operations/disaster-recovery/dr-drill-checklist.md`](../disaster-recovery/dr-drill-checklist.md)
