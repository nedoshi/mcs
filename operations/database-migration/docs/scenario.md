# Scenario: Online rename + JSONB normalization

## Business change

The order service historically stored:

```sql
customer_name  VARCHAR(256)   -- "Ada Lovelace"
items          JSONB          -- [{"sku":"LAP-001","qty":1,"price_cents":189999}, ...]
```

Product wants searchable first/last name and reportable line items. We cannot take a maintenance window.

## Target shape

```sql
customer_first_name  VARCHAR(128)
customer_last_name   VARCHAR(128)
-- items column removed after contract

CREATE TABLE order_items (
  id           BIGSERIAL PRIMARY KEY,
  order_id     BIGINT NOT NULL REFERENCES orders(id),
  sku          VARCHAR(32) NOT NULL,
  quantity     INTEGER NOT NULL,
  price_cents  INTEGER NOT NULL
);
```

## Expand / Contract timeline

```
t0  Legacy app reads/writes customer_name + items
t1  EXPAND (DDL)     — add first/last + order_items (nullable / empty)
t2  App dual-write    — write BOTH legacy and new columns/tables
t3  BACKFILL (DML)    — copy historical rows into new shape
t4  App dual-read     — prefer new columns; fall back to legacy if null
t5  App cutover       — read/write new shape only
t6  CONTRACT (DDL)    — DROP customer_name, DROP items
```

### Why not `ALTER … RENAME` / one big UPDATE?

- Long locks on large tables under OLTP load
- No safe rollback if the app still expects the old column
- Mixed DDL+DML under one privileged DB user (blast radius)

### Role split in this lab

| Phase | Postgres role | Allowed |
|-------|---------------|---------|
| Expand / Contract | `db_ddl` | `ALTER`, `CREATE`, `DROP` on app schema |
| Backfill | `db_dml` | `SELECT`/`INSERT`/`UPDATE` only — **no** schema changes |
| App runtime | `db_app` | CRUD on tables; no DDL |

Jobs mount the matching Secret (`db-credentials-ddl` or `db-credentials-dml`) and run as ServiceAccount `db-migrator`.

## Demo seed data

Three orders with multi-word names and 1–2 JSONB line items. After backfill you should see:

- `orders.customer_first_name` / `customer_last_name` populated
- `order_items` row count = sum of JSONB array lengths
- After contract: `customer_name` and `items` gone

## Failure / rollback notes

| Failure | Rollback |
|---------|----------|
| Expand fails mid-script | Re-run (scripts are idempotent `IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS`) |
| Backfill wrong split logic | Fix SQL; re-run UPDATE (DML only) — do **not** grant DDL to fix data |
| Contract too early | Restore from backup / re-add columns — **never** contract until metrics show zero legacy reads |

See [runbook.md](runbook.md) for exact `oc` commands.
