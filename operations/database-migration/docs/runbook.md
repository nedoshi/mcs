# Runbook

## 0. Deploy lab

```bash
oc login ...   # ROSA HCP
./scripts/deploy.sh
```

Creates project `db-migration`, SA `db-migrator`, in-cluster Postgres, baseline schema, roles, seed data, fallback Secrets, and a tiny `order-api`.

## 1. Expand (DDL)

```bash
./scripts/run-phase.sh expand
./scripts/verify.sh --phase expand
```

Expect: columns `customer_first_name`, `customer_last_name` exist; table `order_items` exists; legacy columns still present.

## 2. Dual-write (app)

Point the app at dual-write mode (lab API supports `WRITE_MODE=dual`):

```bash
oc set env deployment/order-api WRITE_MODE=dual -n db-migration
```

New orders populate both legacy and new fields.

## 3. Backfill (DML)

```bash
./scripts/run-phase.sh backfill
./scripts/verify.sh --phase backfill
```

Expect: zero null first/last names on historical rows; `order_items` count matches JSONB lengths.

## 4. Cutover

```bash
oc set env deployment/order-api WRITE_MODE=new READ_MODE=new -n db-migration
# confirm traffic / metrics — then contract
```

## 5. Contract (DDL)

```bash
./scripts/run-phase.sh contract
./scripts/verify.sh --phase contract
```

Expect: `customer_name` and `items` gone.

## 6. Cleanup

```bash
./scripts/cleanup.sh
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Job CrashLoop / auth failed | `oc get secret -n db-migration`; role passwords in `01-roles.sql` must match Secret |
| Backfill Job tries DDL and fails | Confirm Job uses `db-credentials-dml` |
| ESO Secret not syncing | `oc describe externalsecret -n db-migration`; SecretStore IAM/permissions |
| Contract drops while app still reading legacy | Check `READ_MODE` on Deployment before contract |
