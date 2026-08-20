# Stateful Workload Inventory — Cross-Cloud DR

Mandatory before cross-cloud DR architecture sign-off. One row per stateful component. Link each row to a replication method from [Data Replication Guide](./data-replication-guide.md).

**Related:** [BIA Workshop Template](./bia-workshop-template.md) · [Cross-Cloud DR Guide](../../docs/guide/cross-cloud-dr-aro-rosa/README.md)

---

## Inventory Metadata

| Field | Value |
|-------|-------|
| Primary cluster | ☐ ARO · ☐ ROSA HCP |
| DR cluster | ☐ ARO · ☐ ROSA HCP |
| Last updated | |
| Owner | |

---

## Workload Inventory

| App | Namespace | Data Type | Primary Storage | DR Storage | Replication Method | RPO Target | Owner | Tested (date) |
|-----|-----------|-----------|-----------------|------------|-------------------|------------|-------|---------------|
| _example: orders-api_ | _production_ | _PostgreSQL_ | _Azure Flexible Server_ | _Amazon RDS_ | _Logical replication_ | _5 min_ | _App Team_ | _YYYY-MM-DD_ |
| | | PVC / DB / Object / Cache / Secrets | | | OADP Kopia / DB streaming / rclone / ESO dual-vault | | | |
| | | | | | | | | |
| | | | | | | | | |

---

## Replication Method Quick Reference

| Data Type | Primary (ARO) | DR (ROSA) | Recommended Method |
|-----------|---------------|-----------|-------------------|
| PVC (app files) | Azure Disk CSI | EBS gp3 CSI | OADP Kopia/datamover — **not CSI snapshots** |
| PostgreSQL | Azure Flexible Server | Amazon RDS | Logical replication or cross-cloud read replica + promote |
| MySQL | Azure Database for MySQL | Amazon RDS | Binlog replication / Azure geo-restore (Cold only) |
| Redis | Azure Cache for Redis | ElastiCache | Backup/restore (Cold); no native cross-cloud active replication |
| Object storage | Azure Blob | S3 | rclone sync, Azure Data Factory, or dual-write |
| Secrets | Azure Key Vault | AWS Secrets Manager | ESO with pre-populated secrets in both vaults |
| Kafka | Event Hubs / in-cluster | MSK / in-cluster | MirrorMaker 2 / geo-replication (requires VPN) |

---

## StorageClass Mapping (OADP Restore)

When restoring PVCs cross-cloud, map StorageClasses in the Velero restore:

| Primary StorageClass (ARO) | DR StorageClass (ROSA) |
|----------------------------|------------------------|
| `managed-csi` / `managed-premium` | `gp3-csi-kms` |
| `azurefile-csi` | Use NFS-compatible class or re-architect to block storage |

Configure mapping in restore flags or `velero restore create --storage-class-mappings`.

---

## Validation Checklist

- [ ] Every Tier 0–1 app has a row with assigned replication method
- [ ] Replication lag alerting configured per RPO target
- [ ] Quarterly restore test scheduled per app tier
- [ ] PaaS services (RDS, Azure DB) have independent DR runbooks
- [ ] Failback/data promotion owner documented per row
