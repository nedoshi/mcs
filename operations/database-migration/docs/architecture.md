# Architecture

## Control plane (OpenShift)

```
┌─────────────────────────────────────────────────────────────┐
│  Project: db-migration                                      │
│                                                             │
│  SA: db-migrator ──────► Job/expand   (Secret: ddl creds)   │
│                     ├──► Job/backfill (Secret: dml creds)   │
│                     └──► Job/contract (Secret: ddl creds)   │
│                                                             │
│  SA: order-api ────────► Deployment/order-api (app creds)   │
│                                                             │
│  ESO ExternalSecret ───► K8s Secret (ddl | dml | app)       │
│         ▲                                                   │
│         │ IRSA / workload identity                          │
│  AWS Secrets Manager (ROSA)  or  Azure Key Vault (ARO)      │
│                                                             │
│  Postgres (lab Deployment)  or  RDS / Azure DB (prod)       │
└─────────────────────────────────────────────────────────────┘
```

## Why a dedicated ServiceAccount

- Jobs do not share the app SA → tighter RBAC and audit trail (`oc get events`, CloudTrail/OCP audit)
- ESO / IRSA annotations attach only to migrator if cloud API access is needed
- App compromise does not inherit DDL credentials (creds are different Secrets)

## Credential flow

```
Cloud secret store
    │  ExternalSecret (refreshInterval)
    ▼
Secret/db-credentials-ddl   →  Job env: PGUSER/PGPASSWORD (db_ddl)
Secret/db-credentials-dml   →  Job env: PGUSER/PGPASSWORD (db_dml)
Secret/db-credentials-app   →  Deployment env (db_app)
```

Lab default (`USE_ESO=0`): `openshift/secrets/fallback-secret.yaml` creates the three Secrets directly. Swap to ESO without changing Job specs — same Secret names.

## Migration runner

Jobs use `postgres:16-alpine` + `psql`, mounting SQL from a ConfigMap built by `scripts/run-phase.sh`. Production alternatives: Flyway/Liquibase/Atlas as the Job image — keep the **same** SA + role split.

## ROSA HCP notes

- Hosted control plane: your Jobs run on the worker/data plane; that is fine.
- Prefer private Postgres (RDS in same VPC) for anything beyond the lab.
- ESO needs operator installed in the cluster; SecretStore uses IRSA for Secrets Manager — see [rosa-hcp.md](rosa-hcp.md).
