#!/usr/bin/env bash
# Step 6: Verify data integrity after cross-cloud restore on DR cluster.
# Usage: ./06-verify-data.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd oc

use_context "${DR_CONTEXT}"

EXPECTED=""
[[ -f "${SCRIPTS_ROOT}/results/.dr-marker-expected" ]] && EXPECTED="$(cat "${SCRIPTS_ROOT}/results/.dr-marker-expected")"
[[ -n "${EXPECTED}" ]] || fail "Expected marker not found. Run 02-deploy-test-app.sh and 04-run-backup.sh first."

log "Verifying restored data on DR cluster"
record_result "verify-data" "START" ""

POD="$(oc get pod -n "${TEST_NAMESPACE}" -l app=dr-test-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"
[[ -n "${POD}" ]] || fail "No dr-test-app pod on DR cluster in ${TEST_NAMESPACE}"

ACTUAL="$(oc exec -n "${TEST_NAMESPACE}" "${POD}" -- cat /data/dr-marker.txt 2>/dev/null || echo "")"
[[ -n "${ACTUAL}" ]] || fail "Could not read marker from restored pod"

log "Expected: ${EXPECTED}"
log "Actual:   ${ACTUAL}"

if [[ "${ACTUAL}" == "${EXPECTED}" ]]; then
  ok "Data marker matches — cross-cloud restore validated"
  record_result "verify-data" "PASS" "${ACTUAL}"
else
  fail "Data mismatch — RPO/restore integrity failure"
  record_result "verify-data" "FAIL" "expected=${EXPECTED} actual=${ACTUAL}"
fi

# PVC check
pvc_phase="$(oc get pvc dr-test-data -n "${TEST_NAMESPACE}" -o jsonpath='{.status.phase}')"
[[ "${pvc_phase}" == "Bound" ]] && ok "PVC Bound on DR" || warn "PVC phase: ${pvc_phase}"

record_result "verify-data" "PASS" "pvc=${pvc_phase}"
