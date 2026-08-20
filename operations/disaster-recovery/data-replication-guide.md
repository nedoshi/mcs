# Data Replication — Cross-Cloud DR (Tier 1+ Workloads)

Per-app data replication patterns for ARO ↔ ROSA HCP. Complete the [Stateful Workload Inventory](./stateful-workload-inventory.md) first.

**Related:** [Cross-Cloud DR Guide](../../docs/guide/cross-cloud-dr-aro-rosa/README.md) · [OADP S3 Guide](../backup-restore/oadp_cross_cloud_s3_guide.md)

---

## Decision Matrix

| Data Type | Cold (Backup) | Pilot Light | Active/Passive | Active/Active |
|-----------|---------------|-------------|----------------|---------------|
| PVC files | OADP Kopia | OADP + frequent schedule | OADP + near-real-time | App-level dual-write or shared object store |
| PostgreSQL | pg_dump / restore | Async logical replication | Streaming replication + promote | Multi-master or write-partitioning |
| Object storage | rclone one-way sync | Scheduled sync | Continuous sync | Dual-write or CRDT |
| Redis | RDB export | Backup/restore | Backup/restore | Shared Redis (e.g. Elasticache Global — AWS-only) or app cache miss |

---

## 1. PVC Data — OADP Kopia

Default for in-cluster persistent volumes. **Do not use CSI snapshots** for cross-cloud restore.

```bash
# Backup on primary (see oadp_cross_cloud_s3_guide.md)
velero backup create app-backup --include-namespaces production

# Restore on DR with StorageClass mapping
velero restore create app-restore \
  --from-backup app-backup \
  --storage-class-mappings managed-csi=gp3-csi-kms
```

Annotate pods: `backup.velero.io/backup-volumes: <volume-name>`

---

## 2. PostgreSQL — Logical Replication (Cross-Cloud)

Requires **Site-to-Site VPN** or private connectivity between Azure and AWS for replication traffic.

### Primary: Azure Database for PostgreSQL Flexible Server

### DR: Amazon RDS PostgreSQL

```sql
-- On primary (Azure): create publication
CREATE PUBLICATION dr_pub FOR ALL TABLES;

-- On DR (RDS): create subscription (after VPN connectivity)
CREATE SUBSCRIPTION dr_sub
  CONNECTION 'host=<azure-postgres-fqdn> port=5432 dbname=app user=replicator password=<secret> sslmode=require'
  PUBLICATION dr_pub;
```

Monitor lag:

```sql
SELECT * FROM pg_stat_subscription;
```

**Failover:** `ALTER SUBSCRIPTION dr_sub DISABLE;` then promote RDS to accept writes.

See [examples/postgresql-logical-replication.md](./examples/postgresql-logical-replication.md) for full runbook.

---

## 3. Object Storage — Azure Blob ↔ S3 Sync

Use `rclone` on a scheduled CronJob or external pipeline:

```bash
#!/usr/bin/env bash
# See examples/object-storage-sync.sh
rclone sync azblob:container-name s3:bucket-name/prefix \
  --transfers 8 \
  --checkers 16
```

For Active/Active, prefer application writes to a **cloud-neutral** object store or dual-write pattern.

---

## 4. Secrets — Dual Vault (ESO)

Replicate secret values to both stores before failover:

| Secret | Azure Key Vault | AWS Secrets Manager |
|--------|-----------------|---------------------|
| `app/db-credentials` | ✓ | ✓ (same value) |
| `app/api-key` | ✓ | ✓ |

ESO `ExternalSecret` resources use cloud-local SecretStore — no cross-cloud API calls at runtime.

Reference: [`operations/database-migration/`](../../operations/database-migration/)

---

## 5. Kafka / Event Streaming

Cross-cloud event replication requires MirrorMaker 2 or equivalent over VPN. Budget for:

- Cross-cloud egress charges
- Consumer offset management on failover
- Idempotent consumers for at-least-once delivery

---

## Replication Lag Alerting

Alert when lag exceeds approved RPO:

| Source | Metric | Threshold |
|--------|--------|-----------|
| PostgreSQL | `pg_stat_subscription` lag bytes | Per BIA RPO |
| OADP | Last successful backup age | Schedule interval + buffer |
| rclone | Last sync job success | Job failure = page |

---

## Failover Data Promotion Order

1. Stop writes on primary (if reachable) — maintenance mode
2. Promote DB replica / finalize last sync
3. Restore OADP backup if needed (Cold tier)
4. Verify data integrity (checksums, row counts)
5. Cut traffic (see [Failover Runbook](./failover-runbook-aro-rosa.md))

---

## Validation Checklist

- [ ] Every Tier 1 app has documented replication method
- [ ] Cross-cloud VPN established if DB replication required
- [ ] Replication lag monitored and alerted
- [ ] Promotion runbook tested in non-prod
- [ ] Failback re-establishes replication direction
