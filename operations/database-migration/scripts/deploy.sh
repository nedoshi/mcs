#!/usr/bin/env bash
# Deploy the database-migration lab on ROSA HCP (or ARO).
# Default: in-cluster Postgres + fallback Secrets (no ESO required).
# USE_ESO=1 applies AWS SecretStore + ExternalSecrets instead of fallback.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NS="${NAMESPACE:-db-migration}"
USE_ESO="${USE_ESO:-0}"
SKIP_APP="${SKIP_APP:-0}"

log() { printf '\n==> %s\n' "$*"; }
require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

require oc
oc whoami >/dev/null 2>&1 || { echo "oc login required"; exit 1; }

log "Project ${NS}"
oc apply -f "${ROOT_DIR}/openshift/00-namespace.yaml"
oc project "${NS}" >/dev/null

log "ServiceAccounts + RBAC"
oc apply -f "${ROOT_DIR}/openshift/10-serviceaccount.yaml"
oc apply -f "${ROOT_DIR}/openshift/20-rbac.yaml"

log "Postgres"
oc apply -f "${ROOT_DIR}/openshift/30-postgres.yaml"
oc wait --for=condition=available deployment/postgres -n "${NS}" --timeout=180s

log "Credentials (USE_ESO=${USE_ESO})"
if [[ "${USE_ESO}" == "1" ]]; then
  oc apply -f "${ROOT_DIR}/openshift/secrets/secretstore-aws.yaml"
  oc apply -f "${ROOT_DIR}/openshift/secrets/externalsecret-ddl.yaml"
  oc apply -f "${ROOT_DIR}/openshift/secrets/externalsecret-dml.yaml"
  oc apply -f "${ROOT_DIR}/openshift/secrets/externalsecret-app.yaml"
  log "Waiting for ExternalSecrets to sync…"
  for s in db-credentials-ddl db-credentials-dml db-credentials-app; do
    for _ in $(seq 1 30); do
      oc get secret "${s}" -n "${NS}" >/dev/null 2>&1 && break
      sleep 2
    done
    oc get secret "${s}" -n "${NS}" >/dev/null || {
      echo "Secret ${s} not synced — check ExternalSecret / SecretStore"
      exit 1
    }
  done
else
  oc apply -f "${ROOT_DIR}/openshift/secrets/fallback-secret.yaml"
fi

log "Baseline schema + roles + seed (as postgres superuser)"
PGPOD="$(oc get pod -n "${NS}" -l app=postgres -o jsonpath='{.items[0].metadata.name}')"
for f in 00-baseline-schema.sql 01-roles.sql 02-seed.sql; do
  echo "  applying ${f}"
  # stdin — required for DO $$ ... $$ blocks in 01-roles.sql
  oc exec -i -n "${NS}" "${PGPOD}" -- \
    env PGPASSWORD=postgres-lab-pass-change-me \
    psql -U postgres -d orders -v ON_ERROR_STOP=1 < "${ROOT_DIR}/sql/${f}"
done

if [[ "${SKIP_APP}" != "1" ]]; then
  log "order-api BuildConfig + binary build"
  oc apply -f "${ROOT_DIR}/openshift/40-order-api.yaml"
  oc start-build order-api -n "${NS}" \
    --from-dir="${ROOT_DIR}/apps/order-api" \
    --follow --wait
  oc rollout status deployment/order-api -n "${NS}" --timeout=180s || true
  ROUTE="$(oc get route order-api -n "${NS}" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
  [[ -n "${ROUTE}" ]] && echo "order-api: https://${ROUTE}"
fi

log "Ready. Next:"
echo "  ./scripts/run-phase.sh expand"
echo "  ./scripts/run-phase.sh backfill"
echo "  ./scripts/verify.sh"
echo "  ./scripts/run-phase.sh contract"
