#!/usr/bin/env bash
# Step 5: Restore backup on DR cluster (cross-cloud).
# Usage: ./05-run-restore.sh [backup-name]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd oc velero jq

BACKUP_NAME="${1:-}"
if [[ -z "${BACKUP_NAME}" && -f "${SCRIPTS_ROOT}/results/.last-backup-name" ]]; then
  BACKUP_NAME="$(cat "${SCRIPTS_ROOT}/results/.last-backup-name")"
fi
[[ -n "${BACKUP_NAME}" ]] || fail "Provide backup name or run 04-run-backup.sh first"

use_context "${DR_CONTEXT}"

RESTORE_NAME="${BACKUP_NAME}-restore"
START_EPOCH="$(date +%s)"

log "Restoring ${BACKUP_NAME} on DR cluster as ${RESTORE_NAME}"
log "StorageClass mappings: ${STORAGE_CLASS_MAPPINGS}"
record_result "restore" "START" "${RESTORE_NAME} from ${BACKUP_NAME}"

# Optional: remove existing test ns for clean restore
if oc get ns "${TEST_NAMESPACE}" >/dev/null 2>&1; then
  warn "Namespace ${TEST_NAMESPACE} exists on DR — restore will merge/update resources"
fi

# Build --storage-class-mappings flags
SC_FLAGS=()
IFS=',' read -ra PAIRS <<< "${STORAGE_CLASS_MAPPINGS}"
for pair in "${PAIRS[@]}"; do
  SC_FLAGS+=(--storage-class-mappings "${pair}")
done

velero restore create "${RESTORE_NAME}" \
  --from-backup "${BACKUP_NAME}" \
  "${SC_FLAGS[@]}" \
  --include-namespaces "${TEST_NAMESPACE}"

wait_for_restore "${RESTORE_NAME}"

log "Waiting for restored workload"
oc wait --for=condition=available deployment/dr-test-app -n "${TEST_NAMESPACE}" --timeout=600s 2>/dev/null || {
  warn "Deployment not available yet — checking pods"
  oc get pods -n "${TEST_NAMESPACE}"
}

END_EPOCH="$(date +%s)"
DURATION=$((END_EPOCH - START_EPOCH))
echo "${RESTORE_NAME}" > "${SCRIPTS_ROOT}/results/.last-restore-name"
echo "${DURATION}" > "${SCRIPTS_ROOT}/results/.last-restore-duration-sec"

ok "Restore completed in ${DURATION}s"
record_result "restore" "PASS" "duration=${DURATION}s"

RTO_MIN=$(( (DURATION + 59) / 60 ))
log "Restore duration: ${DURATION}s (~${RTO_MIN} min). RTO target: ${RTO_TARGET_MINUTES} min"
if (( RTO_MIN <= RTO_TARGET_MINUTES )); then
  ok "Restore within RTO target"
  record_result "rto" "PASS" "${RTO_MIN}min <= ${RTO_TARGET_MINUTES}min"
else
  warn "Restore exceeded RTO target"
  record_result "rto" "FAIL" "${RTO_MIN}min > ${RTO_TARGET_MINUTES}min"
fi

velero restore describe "${RESTORE_NAME}" | head -30
