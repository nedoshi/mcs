# Cross-Cloud DR Validation Guide — Step-by-Step Testing

Hands-on guide to validate ARO ↔ ROSA HCP disaster recovery using automated scripts and manual checks.

**Scripts:** [`scripts/`](./scripts/) · **Checklist:** [`dr-drill-checklist.md`](./dr-drill-checklist.md) · **Results template:** [`dr-test-results-template.md`](./dr-test-results-template.md)

---

## What This Validates

| Test | Proves |
|------|--------|
| Preflight | Both clusters healthy, versions aligned, OADP BSL available |
| Backup/restore | Cross-cloud data portability via OADP Kopia → S3 |
| Data verify | RPO integrity — marker file survives restore |
| GitOps | DR cluster reconciling before disaster |
| Smoke | API, ingress, test workload on DR |

This is the **monthly backup/restore test** from the DR drill checklist. For quarterly failover (DNS cutover), follow [`failover-runbook-aro-rosa.md`](./failover-runbook-aro-rosa.md) after this passes.

---

## Prerequisites

### Clusters

- Primary and DR clusters provisioned ([`cross-cloud-dr/environments/`](../../cluster-creation-cloud/cross-cloud-dr/environments/))
- Same OpenShift **minor** version on both
- `oc` logged in — contexts configured for both clusters

### OADP

- OADP operator installed on **both** clusters
- Shared S3 backup bucket configured — [OADP Cross-Cloud S3 Guide](../backup-restore/oadp_cross_cloud_s3_guide.md)
- DPA applied from [`examples/yaml/dpa-s3-cross-cloud.yaml`](../../examples/yaml/dpa-s3-cross-cloud.yaml)
- `cloud-credentials-aws` secret in `openshift-adp` on both clusters

### Tools

```bash
# Required
oc jq

# Required for backup/restore steps
velero version   # https://velero.io/docs/basic-install/

# Optional
aws s3 ls s3://YOUR-BACKUP-BUCKET/   # verify bucket access
```

### Velero CLI setup

Point velero at each cluster before running restore:

```bash
# Primary
oc config use-context prod-aro-primary/admin
velero install --crds-only=false  # if not using oc plugin; usually use cluster's velero

# Or use velero with KUBECONFIG / context — scripts use oc config use-context
```

---

## Step 0: Configure

```bash
cd operations/disaster-recovery/scripts
cp config.env.example config.env
```

Edit `config.env`:

```bash
PRIMARY_CONTEXT="prod-aro-primary/admin"    # oc config get-contexts
DR_CONTEXT="prod-rosa-dr/admin"
STORAGE_CLASS_MAPPINGS="managed-csi=gp3-csi-kms,managed-premium=gp3-csi-kms"
RTO_TARGET_MINUTES=120
```

For **ROSA primary → ARO DR**, reverse mappings:

```bash
STORAGE_CLASS_MAPPINGS="gp3-csi-kms=managed-csi,gp3-csi=managed-csi"
```

Verify contexts:

```bash
oc config use-context "${PRIMARY_CONTEXT}" && oc whoami && oc get nodes
oc config use-context "${DR_CONTEXT}" && oc whoami && oc get nodes
```

---

## Step 1: Run Automated Validation (Recommended)

```bash
chmod +x *.sh lib/common.sh
./run-dr-validation.sh
```

This runs steps 1–8 in order. Results logged to `scripts/results/dr-validation-*.log`.

### Run individual steps

```bash
./run-dr-validation.sh --step 1   # preflight only
./run-dr-validation.sh --step 4   # backup only (after steps 1-3)
./run-dr-validation.sh --step 5   # restore on DR
```

### Cleanup after test

```bash
./run-dr-validation.sh --cleanup   # run full suite then delete test ns
# or
./09-cleanup.sh --both
```

---

## Step 2: Manual Walkthrough (What Each Script Does)

### Step 1 — Preflight (`01-preflight.sh`)

Checks:
- ClusterOperators Available on both clusters
- Nodes Ready
- OpenShift version match (warns if mismatch)
- OADP namespace, DPA, BackupStorageLocation phase
- velero CLI presence

**Pass:** Script exits 0.

**Fail:** Fix OADP/BSL before continuing — see [OADP guide troubleshooting](../backup-restore/oadp_cross_cloud_s3_guide.md).

---

### Step 2 — Deploy test app (`02-deploy-test-app.sh`)

Deploys [`manifests/dr-test-app.yaml`](./manifests/dr-test-app.yaml):
- Namespace `dr-validation`
- PVC + pod writing `/data/dr-marker.txt`
- Velero annotation `backup.velero.io/backup-volumes: data`

Override StorageClass if needed:

```bash
./02-deploy-test-app.sh --storage-class gp3-csi-kms   # ROSA primary
./02-deploy-test-app.sh --storage-class managed-csi # ARO primary
```

---

### Step 3 — Verify OADP (`03-verify-oadp.sh`)

Confirms:
- nodeAgent/Kopia enabled
- Default BSL `Available` on primary **and** DR
- Same S3 bucket (best effort)

---

### Step 4 — Backup on primary (`04-run-backup.sh`)

- Updates marker with timestamp
- Creates velero backup: `dr-validation-YYYYMMDD-HHMMSS`
- Waits for `Completed`
- Records backup duration

Manual equivalent:

```bash
oc config use-context prod-aro-primary/admin
velero backup create dr-test --include-namespaces dr-validation --default-volumes-to-fs-backup=true --wait
velero backup describe dr-test
```

---

### Step 5 — Restore on DR (`05-run-restore.sh`)

- Switches to DR context
- Restores with StorageClass mappings from `config.env`
- Waits for restore `Completed`
- Compares duration to `RTO_TARGET_MINUTES`

Manual equivalent:

```bash
oc config use-context prod-rosa-dr/admin
velero restore create dr-test-restore \
  --from-backup dr-validation-20260820-120000 \
  --storage-class-mappings managed-csi=gp3-csi-kms \
  --include-namespaces dr-validation
velero restore describe dr-test-restore
oc get pods -n dr-validation -w
```

---

### Step 6 — Verify data (`06-verify-data.sh`)

Reads marker from restored pod on DR — must match pre-backup value.

**Pass:** Proves cross-cloud PV restore integrity (Kopia path works).

---

### Step 7 — GitOps (`07-verify-gitops.sh`)

On DR cluster:
- `openshift-gitops-server` ready
- Argo CD Applications `Synced` / `Healthy`

Optional: set `HUB_CONTEXT` in `config.env` to list ManagedCluster labels on ACM hub.

---

### Step 8 — Smoke test (`08-smoke-test.sh`)

- API login works
- Console URL resolvable
- Test deployment ready
- OAuth route present (manual Entra login still required)

**Manual Entra ID check:**
1. Open DR console URL
2. Log in with Entra ID account
3. Confirm RBAC groups grant expected access

---

## Step 3: Extended Validation (Beyond Scripts)

### Registry pull test

Simulate primary registry unavailable:

1. Block egress to primary cloud registry (network policy or firewall test rule)
2. Confirm DR cluster pulls from Quay/dual-push/ECR copy
3. Redeploy a test pod using production image

See [`identity-registry-setup.md`](./identity-registry-setup.md).

### DB replication lag (Tier 1 apps)

```bash
# PostgreSQL example — on DR subscriber
psql -c "SELECT * FROM pg_stat_subscription;"
```

Lag must stay below approved RPO. See [`examples/postgresql-logical-replication.md`](./examples/postgresql-logical-replication.md).

### DNS / traffic failover (Quarterly drill)

Do **not** run in production without change window:

1. Follow [`failover-runbook-aro-rosa.md`](./failover-runbook-aro-rosa.md)
2. Repoint test DNS record to DR ingress
3. Measure propagation time
4. Execute [`failback-runbook-aro-rosa.md`](./failback-runbook-aro-rosa.md)

See [`traffic-steering-guide.md`](./traffic-steering-guide.md).

---

## Step 4: Record Results

Copy metrics from `scripts/results/dr-validation-*.log` into [`dr-test-results-template.md`](./dr-test-results-template.md):

| Metric | Source |
|--------|--------|
| Backup duration | `.last-backup-duration-sec` |
| Restore duration | `.last-restore-duration-sec` (partial RTO) |
| RTO pass/fail | Compared to `RTO_TARGET_MINUTES` in config.env |
| Data integrity | Step 6 pass/fail |

Complete [`cross-cloud-production-readiness-checklist.md`](../../docs/guide/aro-decision-matrix/cross-cloud-production-readiness-checklist.md) items X4.5, X6.1–X6.3.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| BSL not Available | Check S3 creds, bucket policy, region in DPA |
| Backup missing PV data | Add `backup.velero.io/backup-volumes` annotation; use `--default-volumes-to-fs-backup` |
| Restore PVC Pending | Fix `STORAGE_CLASS_MAPPINGS` in config.env |
| velero: backup not found on DR | Confirm both clusters use same S3 bucket/prefix |
| Version mismatch warning | Align OpenShift versions before production DR |
| Marker mismatch after restore | Backup may be stale — re-run steps 2→5 in sequence |

---

## Test Cadence

| Frequency | Action |
|-----------|--------|
| Monthly | `./run-dr-validation.sh` (steps 1–8) |
| Quarterly | Full failover drill + DNS cutover |
| Annual | Failback drill |
| 2×/year | Tabletop — [`dr-drill-checklist.md`](./dr-drill-checklist.md) |

---

## Script Reference

| Script | Purpose |
|--------|---------|
| `run-dr-validation.sh` | Orchestrator — runs all steps |
| `01-preflight.sh` | Cluster + OADP preflight |
| `02-deploy-test-app.sh` | Test workload on primary |
| `03-verify-oadp.sh` | OADP/Kopia/S3 verification |
| `04-run-backup.sh` | Backup on primary |
| `05-run-restore.sh` | Cross-cloud restore on DR |
| `06-verify-data.sh` | Data integrity check |
| `07-verify-gitops.sh` | Argo CD on DR |
| `08-smoke-test.sh` | API/ingress/app smoke tests |
| `09-cleanup.sh` | Remove test resources |

---

## Related Documentation

- [Cross-Cloud DR Strategy](../../docs/guide/cross-cloud-dr-aro-rosa/README.md)
- [OADP Cross-Cloud S3 Guide](../backup-restore/oadp_cross_cloud_s3_guide.md)
- [Failover Runbook](./failover-runbook-aro-rosa.md)
- [Failback Runbook](./failback-runbook-aro-rosa.md)
