# Cross-Cloud DR Validation Scripts

Automated test suite for ARO ↔ ROSA HCP backup/restore validation.

**Full guide:** [DR Validation Guide](../dr-validation-guide.md)

## Quick Start

```bash
cd operations/disaster-recovery/scripts
cp config.env.example config.env
# Edit PRIMARY_CONTEXT, DR_CONTEXT, STORAGE_CLASS_MAPPINGS

chmod +x *.sh lib/common.sh
./run-dr-validation.sh
```

## Requirements

- `oc`, `jq`, `velero` CLI
- OADP configured on both clusters with shared S3 bucket
- Cluster contexts in kubeconfig

## Scripts

| Script | Step |
|--------|------|
| `run-dr-validation.sh` | Run all steps (or `--step N`) |
| `01-preflight.sh` | Cluster health, OADP BSL |
| `02-deploy-test-app.sh` | Test PVC workload on primary |
| `03-verify-oadp.sh` | Kopia + shared bucket check |
| `04-run-backup.sh` | Velero backup on primary |
| `05-run-restore.sh` | Cross-cloud restore on DR |
| `06-verify-data.sh` | Marker file integrity |
| `07-verify-gitops.sh` | Argo CD on DR |
| `08-smoke-test.sh` | API / ingress smoke tests |
| `09-cleanup.sh` | Remove test namespace |

Results: `results/dr-validation-*.log`
