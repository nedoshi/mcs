#!/usr/bin/env bash
# Step 2: Deploy test application with PVC on primary cluster.
# Usage: ./02-deploy-test-app.sh [--storage-class managed-csi]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

STORAGE_CLASS="managed-csi"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --storage-class) STORAGE_CLASS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

MANIFEST="${DR_ROOT}/manifests/dr-test-app.yaml"
TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

require_cmd oc sed

use_context "${PRIMARY_CONTEXT}"
log "Deploying test app to ${TEST_NAMESPACE} on primary (StorageClass: ${STORAGE_CLASS})"

sed "s/storageClassName: managed-csi/storageClassName: ${STORAGE_CLASS}/" "${MANIFEST}" > "${TMP}"
oc apply -f "${TMP}"

log "Waiting for deployment"
oc wait --for=condition=available deployment/dr-test-app -n "${TEST_NAMESPACE}" --timeout=300s

log "Waiting for PVC bound"
for _ in $(seq 1 60); do
  phase="$(oc get pvc dr-test-data -n "${TEST_NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo Pending)"
  [[ "${phase}" == "Bound" ]] && break
  sleep 5
done
[[ "${phase}" == "Bound" ]] || fail "PVC dr-test-data not Bound (phase: ${phase})"

# Write fresh marker
POD="$(oc get pod -n "${TEST_NAMESPACE}" -l app=dr-test-app -o jsonpath='{.items[0].metadata.name}')"
MARKER="$(oc exec -n "${TEST_NAMESPACE}" "${POD}" -- cat /data/dr-marker.txt 2>/dev/null || echo "")"
[[ -n "${MARKER}" ]] || fail "Could not read marker from test pod"

ok "Test app running. Marker: ${MARKER}"
echo "${MARKER}" > "${SCRIPTS_ROOT}/results/.dr-marker-expected"
record_result "deploy-test-app" "PASS" "${MARKER}"
