# ROSA HCP setup

## Lab path (default)

No ESO required. `deploy.sh` applies `openshift/secrets/fallback-secret.yaml`.

```bash
./scripts/deploy.sh
```

Postgres runs in-cluster (PVC). Good for proving Expand/Contract + role split + SA isolation on ROSA HCP workers.

## ESO + AWS Secrets Manager

1. Install External Secrets Operator (OperatorHub / OLM).
2. Create SM secrets (example):

```bash
aws secretsmanager create-secret --name db-migration/ddl \
  --secret-string '{"username":"db_ddl","password":"<ddl-pass>","host":"postgres","port":"5432","dbname":"orders"}'

aws secretsmanager create-secret --name db-migration/dml \
  --secret-string '{"username":"db_dml","password":"<dml-pass>","host":"postgres","port":"5432","dbname":"orders"}'

aws secretsmanager create-secret --name db-migration/app \
  --secret-string '{"username":"db_app","password":"<app-pass>","host":"postgres","port":"5432","dbname":"orders"}'
```

3. Give ESO's controller SA (or a dedicated SA) IRSA access to those secrets — same OIDC pattern as the [IRSA demo](../../identity/irsa-workload-identity/).
4. Apply:

```bash
USE_ESO=1 ./scripts/deploy.sh
# or manually:
oc apply -f openshift/secrets/secretstore-aws.yaml
oc apply -f openshift/secrets/externalsecret-ddl.yaml
oc apply -f openshift/secrets/externalsecret-dml.yaml
oc apply -f openshift/secrets/externalsecret-app.yaml
```

Edit `secretstore-aws.yaml` region / role ARN before apply.

## ARO path

Use `openshift/secrets/secretstore-azure.yaml` (Key Vault) instead of the AWS SecretStore. Jobs and SQL are identical.

## Pointing at RDS

1. Provision RDS Postgres in the ROSA VPC (private subnets + SG allowing cluster).
2. Update Secret `host` to the RDS endpoint (fallback YAML or SM JSON).
3. Skip / delete the in-cluster `30-postgres.yaml` Deployment; keep the Service name as a DNS CNAME **or** change Job host via Secret only (Jobs read `PGHOST` from Secret).

## Capacity

Lab requests are tiny (~200m CPU / 256Mi for Postgres). HCP default worker is enough.
