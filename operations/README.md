# OpenShift Operations

This directory contains operational guides for managing and maintaining OpenShift clusters.

## Directory Structure

### [Monitoring](monitoring/)
Guides for setting up and configuring monitoring and alerting for OpenShift clusters.

- [ARO Monitoring Guide](monitoring/aro-monitoring-guide.md) - Azure Monitor integration and OpenShift native monitoring

### [Backup & Restore](backup-restore/)
Backup and disaster recovery guides using OADP and other tools.

- [OADP Clean Guide](backup-restore/oadp_clean_guide.md) - OpenShift API for Data Protection setup and usage
- [OADP Cross-Cloud S3 Guide](backup-restore/oadp_cross_cloud_s3_guide.md) - ARO ↔ ROSA HCP backup via S3 + Kopia

### [Disaster Recovery](disaster-recovery/)
Cross-cloud DR runbooks, templates, and validation for ARO ↔ ROSA HCP.

- [DR Validation Guide](disaster-recovery/dr-validation-guide.md) - Step-by-step testing with scripts
- [Validation Scripts](disaster-recovery/scripts/run-dr-validation.sh) - Automated backup/restore test suite
- [DR Operations Index](disaster-recovery/README.md) - Full index of runbooks and templates
- [Failover Runbook](disaster-recovery/failover-runbook-aro-rosa.md) - Primary → DR cutover
- [Failback Runbook](disaster-recovery/failback-runbook-aro-rosa.md) - DR → primary restore

### [Troubleshooting](troubleshooting/)
Common issues and their solutions.

- [OCM Visibility](troubleshooting/OCM_visibility.md) - Troubleshooting cluster visibility in Red Hat Hybrid Cloud Console

### [Database Migration](database-migration/)
Online schema change lab for **ROSA HCP** / ARO: Expand/Contract phases, DDL vs DML Postgres roles, ESO secret sync, dedicated `db-migrator` ServiceAccount.

- [README](database-migration/README.md) — quick start
- [Scenario](database-migration/docs/scenario.md) — sample `customer_name` → first/last + JSONB → `order_items`
- [Runbook](database-migration/docs/runbook.md) — phase-by-phase `oc` flow

## Related Documentation

- [Cluster Installation](../cluster-creation-onprem/) - On-premises cluster installation
- [Cloud Deployments](../cluster-creation-cloud/) - Managed cloud OpenShift services
- [Architecture](../docs/architecture/) - Architecture and design patterns
