#!/usr/bin/env bash
# Verify migration state after each phase.
# Usage: ./scripts/verify.sh [--phase expand|backfill|contract]
set -euo pipefail

NS="${NAMESPACE:-db-migration}"
PHASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

command -v oc >/dev/null || { echo "Missing oc"; exit 1; }
PGPOD="$(oc get pod -n "${NS}" -l app=postgres -o jsonpath='{.items[0].metadata.name}')"

psql() {
  oc exec -n "${NS}" "${PGPOD}" -- \
    env PGPASSWORD=postgres-lab-pass-change-me \
    psql -U postgres -d orders -v ON_ERROR_STOP=1 -At -c "$1"
}

echo "==> schema_migrations"
psql "SELECT version || ' ' || phase || ' ' || applied_by FROM app.schema_migrations ORDER BY applied_at;" || true

echo "==> orders columns"
psql "SELECT column_name FROM information_schema.columns WHERE table_schema='app' AND table_name='orders' ORDER BY ordinal_position;"

echo "==> order counts"
psql "SELECT count(*) FROM app.orders;"

fail=0

check() {
  local label="$1" expect="$2" actual
  actual="$(psql "$3")"
  if [[ "${actual}" == "${expect}" ]]; then
    echo "OK  ${label}: ${actual}"
  else
    echo "FAIL ${label}: expected=${expect} actual=${actual}"
    fail=1
  fi
}

run_expand_checks() {
  check "has first_name col" "1" \
    "SELECT count(*) FROM information_schema.columns WHERE table_schema='app' AND table_name='orders' AND column_name='customer_first_name';"
  check "has order_items table" "1" \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='app' AND table_name='order_items';"
  check "legacy customer_name still present" "1" \
    "SELECT count(*) FROM information_schema.columns WHERE table_schema='app' AND table_name='orders' AND column_name='customer_name';"
}

run_backfill_checks() {
  check "null first names" "0" \
    "SELECT count(*) FROM app.orders WHERE customer_first_name IS NULL;"
  check "order_items rows" "4" \
    "SELECT count(*) FROM app.order_items;"

  echo "==> negative test: db_dml must NOT alter schema"
  if oc exec -n "${NS}" "${PGPOD}" -- \
      env PGPASSWORD=dml-lab-pass-change-me \
      psql -U db_dml -d orders -c 'ALTER TABLE app.orders ADD COLUMN IF NOT EXISTS should_fail int;' >/dev/null 2>&1; then
    echo "FAIL: db_dml was able to ALTER TABLE"
    fail=1
  else
    echo "OK  db_dml denied ALTER (expected)"
  fi
}

run_contract_checks() {
  check "customer_name dropped" "0" \
    "SELECT count(*) FROM information_schema.columns WHERE table_schema='app' AND table_name='orders' AND column_name='customer_name';"
  check "items dropped" "0" \
    "SELECT count(*) FROM information_schema.columns WHERE table_schema='app' AND table_name='orders' AND column_name='items';"
}

case "${PHASE}" in
  expand)   run_expand_checks ;;
  backfill) run_backfill_checks ;;
  contract) run_contract_checks ;;
  "")
    # Best-effort full picture: run checks that won't false-fail mid-flight
    if psql "SELECT count(*) FROM information_schema.columns WHERE table_schema='app' AND table_name='orders' AND column_name='customer_first_name';" | grep -qx 1; then
      run_expand_checks
    fi
    if psql "SELECT count(*) FROM information_schema.tables WHERE table_schema='app' AND table_name='order_items';" | grep -qx 1; then
      ITEMS="$(psql "SELECT count(*) FROM app.order_items;" || echo 0)"
      if [[ "${ITEMS}" != "0" ]]; then
        run_backfill_checks
      fi
    fi
    if psql "SELECT count(*) FROM information_schema.columns WHERE table_schema='app' AND table_name='orders' AND column_name='customer_name';" | grep -qx 0; then
      run_contract_checks
    fi
    ;;
  *)
    echo "Unknown phase: ${PHASE}"
    exit 1
    ;;
esac

exit "${fail}"
