# Cross-Cloud Disaster Recovery Operations

Operational guides, runbooks, and templates for **ARO ↔ ROSA HCP** disaster recovery.

**Strategy guide:** [Cross-Cloud DR — ARO ↔ ROSA HCP](../../docs/guide/cross-cloud-dr-aro-rosa/README.md)

---

## Planning

| Document | Purpose |
|----------|---------|
| [BIA Workshop Template](./bia-workshop-template.md) | Classify apps Tier 0–3; choose primary/DR direction |
| [Stateful Workload Inventory](./stateful-workload-inventory.md) | Per-app replication method assignment |
| [Cross-Cloud Production Checklist](../../docs/guide/aro-decision-matrix/cross-cloud-production-readiness-checklist.md) | Go-live gate |

---

## Infrastructure

| Document | Purpose |
|----------|---------|
| [Cross-Cloud DR tfvars](../../cluster-creation-cloud/cross-cloud-dr/README.md) | Terraform templates for primary + DR clusters |
| [ACM GitOps Setup](./acm-gitops-setup.md) | Register clusters; ApplicationSets |
| [Identity & Registry Setup](./identity-registry-setup.md) | Entra ID + Quay/Harbor/dual-push |

---

## Backup & Data

| Document | Purpose |
|----------|---------|
| [OADP Cross-Cloud S3 Guide](../backup-restore/oadp_cross_cloud_s3_guide.md) | OADP + Kopia backup to S3 |
| [Data Replication Guide](./data-replication-guide.md) | DB streaming, object sync, secrets |
| [PostgreSQL Logical Replication](./examples/postgresql-logical-replication.md) | Cross-cloud Postgres example |
| [Object Storage Sync Script](./examples/object-storage-sync.sh) | Azure Blob → S3 sync |

---

## Failover & Traffic

| Document | Purpose |
|----------|---------|
| [Failover Runbook](./failover-runbook-aro-rosa.md) | Primary → DR cutover |
| [Failback Runbook](./failback-runbook-aro-rosa.md) | DR → primary restore |
| [Traffic Steering Guide](./traffic-steering-guide.md) | Global DNS / LB design |

---

## Validation

| Document | Purpose |
|----------|---------|
| **[DR Validation Guide](./dr-validation-guide.md)** | **Step-by-step testing with automated scripts** |
| [Validation Scripts](./scripts/) | `run-dr-validation.sh` — backup/restore/GitOps smoke test |
| [DR Drill Checklist](./dr-drill-checklist.md) | Monthly / quarterly / annual exercises |
| [DR Test Results Template](./dr-test-results-template.md) | Record RTO/RPO measurements |

---

## YAML Examples

| File | Purpose |
|------|---------|
| [`examples/yaml/dpa-s3-cross-cloud.yaml`](../../examples/yaml/dpa-s3-cross-cloud.yaml) | DataProtectionApplication for S3 |
| [`examples/yaml/backup-schedule-cross-cloud.yaml`](../../examples/yaml/backup-schedule-cross-cloud.yaml) | Velero schedules |
| [`examples/dual-push-registry.yml`](./examples/dual-push-registry.yml) | CI dual-push to ACR + ECR |

---

## Related

- [ARO Multi-Region DR](../../docs/guide/aro-disaster-recovery/README.md) — same-cloud baseline
- [Multi-Cloud GitOps](../../cluster-creation-cloud/aws/shared-vpc/gitops/README.md)
- [OADP Clean Guide (ARO)](../backup-restore/oadp_clean_guide.md)
