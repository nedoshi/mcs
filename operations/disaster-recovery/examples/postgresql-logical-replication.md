# PostgreSQL Logical Replication — ARO (Azure) → ROSA DR (AWS RDS)

Cross-cloud logical replication runbook for Tier 1+ applications.

**Prerequisites:** Site-to-Site VPN between Azure VNet and AWS VPC; PostgreSQL 12+.

---

## Network

Ensure RDS security group allows inbound `5432` from Azure VNet CIDR via VPN.

---

## Primary (Azure Database for PostgreSQL Flexible Server)

```sql
-- Create replication user
CREATE USER replicator WITH REPLICATION PASSWORD 'CHANGE_ME';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replicator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO replicator;

-- Enable logical replication (server parameter)
-- azure.replication_support = logical  (via Azure portal / CLI)

CREATE PUBLICATION dr_pub FOR ALL TABLES;
```

Verify:

```sql
SELECT * FROM pg_publication;
```

---

## DR (Amazon RDS PostgreSQL)

```sql
-- Create matching schema (or restore from pg_dump baseline)
-- ...

CREATE SUBSCRIPTION dr_sub
  CONNECTION 'host=prod-postgres.postgres.database.azure.com port=5432 dbname=appdb user=replicator password=CHANGE_ME sslmode=require'
  PUBLICATION dr_pub
  WITH (copy_data = true);
```

Monitor:

```sql
SELECT subname, subenabled, latest_end_lsn FROM pg_subscription;
SELECT * FROM pg_stat_subscription;
```

---

## Failover — Promote DR to Primary

1. Enable maintenance mode on primary app (stop writes)
2. Wait for replication lag = 0
3. On DR RDS:

```sql
ALTER SUBSCRIPTION dr_sub DISABLE;
-- RDS: reboot if needed, update application connection strings
```

4. On former primary (if recoverable): `DROP SUBSCRIPTION` / rebuild as replica for failback

---

## Failback

Reverse publication/subscription direction after primary cloud recovers. See [Failback Runbook](../failback-runbook-aro-rosa.md).

---

## Troubleshooting

| Issue | Action |
|-------|--------|
| Connection timeout | Verify VPN routes and NSG/SG rules |
| Schema mismatch | Apply migrations to DR before subscription |
| High lag | Check cross-cloud bandwidth; reduce batch write size on primary |
