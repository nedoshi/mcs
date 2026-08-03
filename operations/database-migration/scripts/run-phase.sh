#!/usr/bin/env bash
# Run one Expand/Contract phase as a Job under SA db-migrator.
# Usage: ./scripts/run-phase.sh expand|backfill|contract
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NS="${NAMESPACE:-db-migration}"
PHASE="${1:-}"

usage() {
  echo "Usage: $0 expand|backfill|contract"
  exit 1
}

[[ -n "${PHASE}" ]] || usage

case "${PHASE}" in
  expand)
    SQL_DIR="${ROOT_DIR}/migrations/expand"
    SECRET="db-credentials-ddl"
    ;;
  backfill)
    SQL_DIR="${ROOT_DIR}/migrations/backfill"
    SECRET="db-credentials-dml"
    ;;
  contract)
    SQL_DIR="${ROOT_DIR}/migrations/contract"
    SECRET="db-credentials-ddl"
    ;;
  *)
    usage
    ;;
esac

command -v oc >/dev/null || { echo "Missing oc"; exit 1; }
oc whoami >/dev/null 2>&1 || { echo "oc login required"; exit 1; }

JOB="db-migrate-${PHASE}"
CM="migration-sql-${PHASE}"

echo "==> Phase=${PHASE} secret=${SECRET} sa=db-migrator"

# Drop prior Job so re-runs are clean
oc delete job "${JOB}" -n "${NS}" --ignore-not-found
oc delete configmap "${CM}" -n "${NS}" --ignore-not-found

echo "==> ConfigMap ${CM} from ${SQL_DIR}"
oc create configmap "${CM}" -n "${NS}" --from-file="${SQL_DIR}"

SCRATCH="$(mktemp)"
trap 'rm -f "${SCRATCH}"' EXIT
sed -e "s/PHASE/${PHASE}/g" -e "s/SECRET_NAME/${SECRET}/g" \
  "${ROOT_DIR}/openshift/jobs/migrate-job.yaml.tpl" > "${SCRATCH}"

oc apply -f "${SCRATCH}" -n "${NS}"

echo "==> Waiting for Job/${JOB}"
# Wait until complete or failed
for _ in $(seq 1 60); do
  SUCCEEDED="$(oc get job "${JOB}" -n "${NS}" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo '')"
  FAILED="$(oc get job "${JOB}" -n "${NS}" -o jsonpath='{.status.failed}' 2>/dev/null || echo '')"
  if [[ "${SUCCEEDED}" == "1" ]]; then
    echo "Job succeeded"
    oc logs "job/${JOB}" -n "${NS}" || true
    exit 0
  fi
  if [[ "${FAILED}" == "1" ]]; then
    echo "Job failed"
    oc logs "job/${JOB}" -n "${NS}" || true
    oc describe job "${JOB}" -n "${NS}" | tail -40
    exit 1
  fi
  sleep 2
done

echo "Timed out waiting for Job/${JOB}"
oc describe job "${JOB}" -n "${NS}" | tail -40
exit 1
