# Database Migration on ROSA / ARO

Online schema change demo using **Expand/Contract**, **DDL/DML role split**, **External Secrets Operator (ESO)**, and a **dedicated migrator ServiceAccount**.

Primary target: **ROSA HCP** (in-cluster Postgres for the lab; swap host for RDS when ready). ARO path uses the same Jobs — only the ESO `SecretStore` changes (Azure Key Vault).

## Sample scenario

Legacy `orders` table stores a single `customer_name` and packs line items in a JSONB column. We migrate to first/last name columns and a normalized `order_items` table **without downtime**.

| Phase | Who | What |
|-------|-----|------|
| **Expand** | DDL role | Add nullable columns + `order_items` table |
| **Backfill** | DML role | Split names, explode JSONB → rows |
| **App cutover** | App (dual-write) | Read/write new shape; keep legacy warm |
| **Contract** | DDL role | Drop `customer_name` + `items` after apps stop using them |

Full narrative: [docs/scenario.md](docs/scenario.md) · Architecture: [docs/architecture.md](docs/architecture.md) · Runbook: [docs/runbook.md](docs/runbook.md)

## Directory layout

```
database-migration/
├── README.md
├── scaffold.sh                 # Recreate empty tree (optional)
├── docs/
│   ├── architecture.md
│   ├── scenario.md
│   ├── runbook.md
│   └── rosa-hcp.md
├── sql/
│   ├── 00-baseline-schema.sql  # Legacy schema
│   ├── 01-roles.sql            # DDL / DML / app roles
│   └── 02-seed.sql
├── migrations/
│   ├── expand/                 # DDL only
│   ├── backfill/               # DML only
│   └── contract/               # DDL only
├── openshift/
│   ├── 00-namespace.yaml
│   ├── 10-serviceaccount.yaml  # db-migrator SA
│   ├── 20-rbac.yaml
│   ├── 30-postgres.yaml
│   ├── jobs/
│   └── secrets/                # ESO + fallback Secret
├── apps/order-api/             # Tiny API proving dual-read
└── scripts/
    ├── deploy.sh               # ROSA HCP lab deploy
    ├── run-phase.sh            # expand | backfill | contract
    ├── verify.sh
    └── cleanup.sh
```

## Quick start (ROSA HCP)

```bash
# oc login to your ROSA HCP cluster first
cd operations/database-migration

./scripts/deploy.sh                 # NS, SA, Postgres, roles, seed, fallback secrets
./scripts/run-phase.sh expand       # DDL Job
./scripts/run-phase.sh backfill     # DML Job
./scripts/verify.sh                 # Row counts / null checks
# … cut app over (see runbook) …
./scripts/run-phase.sh contract     # DDL drop legacy
./scripts/cleanup.sh                # Tear down lab
```

Optional ESO (AWS Secrets Manager) instead of the fallback Secret:

```bash
USE_ESO=1 ./scripts/deploy.sh
# See docs/rosa-hcp.md for SecretStore + IRSA notes
```

## Security model (interview talking points)

1. **Expand/Contract** — never rewrite columns in place under traffic; add → backfill → switch → drop.
2. **DDL ≠ DML** — expand/contract Jobs use `db_ddl`; backfill uses `db_dml` (no `ALTER`/`DROP`).
3. **ESO** — credentials never live in Git; synced into the namespace as Secrets.
4. **Dedicated SA** — `db-migrator` runs Jobs; app Deployment uses `order-api` with DML-only (or tighter) grants.

## Prerequisites

- ROSA HCP (or ARO) with `oc` logged in
- Cluster ability to create projects / deploy workloads
- Optional: External Secrets Operator + cloud secret store for the ESO path
