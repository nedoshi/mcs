#!/usr/bin/env bash
# Step 4: Run OADP backup on primary cluster.
# Usage: ./04-run-backup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd oc
velero_available || fail "velero CLI required. Install: https://velero.io/docs/basic-install/"

use_context "${PRIMARY_CONTEXT}"

BACKUP_NAME="${BACKUP_NAME_PREFIX}-$(date +%Y%m%d-%H%M%S)"
START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_EPOCH="$(date +%s)"

log "Creating backup ${BACKUP_NAME} for namespace ${TEST_NAMESPACE}"
record_result "backup" "START" "${BACKUP_NAME} at ${START_TS}"

# Refresh marker before backup
POD="$(oc get pod -n "${TEST_NAMESPACE}" -l app=dr-test-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"
if [[ -n "${POD}" ]]; then
  MARKER="DR-VALIDATION-${START_TS}"
  oc exec -n "${TEST_NAMESPACE}" "${POD}" -- sh -c "echo '${MARKER}' > /data/dr-marker.txt"
  echo "${MARKER}" > "${SCRIPTS_ROOT}/results/.dr-marker-expected"
  ok "Updated marker before backup: ${MARKER}"
fi

velero backup create "${BACKUP_NAME}" \
  --include-namespaces "${TEST_NAMESPACE}" \
  --default-volumes-to-fs-backup=true \
  --wait

wait_for_backup "${BACKUP_NAME}"

END_EPOCH="$(date +%s)"
DURATION=$((END_EPOCH - START_EPOCH))
echo "${BACKUP_NAME}" > "${SCRIPTS_ROOT}/results/.last-backup-name"
echo "${DURATION}" > "${SCRIPTS_ROOT}/results/.last-backup-duration-sec"

ok "Backup completed in ${DURATION}s"
record_result "backup" "PASS" "${BACKUP_NAME} duration=${DURATION}s"

# Show backup details
velero backup describe "${BACKUP_NAME}" | head -30
