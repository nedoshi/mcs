#!/usr/bin/env bash
# Remove DR validation test resources.
# Usage: ./09-cleanup.sh [--primary] [--dr] [--both]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

TARGET="${1:---both}"

cleanup_cluster() {
  local ctx="$1"
  local label="$2"
  use_context "${ctx}"
  log "Cleaning ${TEST_NAMESPACE} on ${label}"
  oc delete namespace "${TEST_NAMESPACE}" --ignore-not-found --timeout=120s 2>/dev/null || true
  ok "Cleaned ${label}"
}

case "${TARGET}" in
  --primary) cleanup_cluster "${PRIMARY_CONTEXT}" "primary" ;;
  --dr)      cleanup_cluster "${DR_CONTEXT}" "dr" ;;
  --both|*)
    cleanup_cluster "${PRIMARY_CONTEXT}" "primary"
    cleanup_cluster "${DR_CONTEXT}" "dr"
    ;;
esac

rm -f "${SCRIPTS_ROOT}/results/.dr-marker-expected" \
      "${SCRIPTS_ROOT}/results/.last-backup-name" \
      "${SCRIPTS_ROOT}/results/.last-restore-name" \
      "${SCRIPTS_ROOT}/results/.last-backup-duration-sec" \
      "${SCRIPTS_ROOT}/results/.last-restore-duration-sec" 2>/dev/null || true

ok "Cleanup complete"
