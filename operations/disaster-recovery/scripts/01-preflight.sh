#!/usr/bin/env bash
# Step 1: Preflight checks for cross-cloud DR validation.
# Usage: ./01-preflight.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd oc jq

log "Cross-cloud DR preflight"
record_result "preflight" "START" ""

failures=0

# Primary cluster
use_context "${PRIMARY_CONTEXT}"
if check_cluster_operators; then record_result "primary-co" "PASS" ""; else record_result "primary-co" "FAIL" ""; failures=$((failures + 1)); fi
if check_nodes_ready; then record_result "primary-nodes" "PASS" ""; else record_result "primary-nodes" "FAIL" ""; failures=$((failures + 1)); fi

primary_ver="$(get_openshift_version)"
record_result "primary-version" "INFO" "${primary_ver}"

# DR cluster
use_context "${DR_CONTEXT}"
if check_cluster_operators; then record_result "dr-co" "PASS" ""; else record_result "dr-co" "FAIL" ""; failures=$((failures + 1)); fi
if check_nodes_ready; then record_result "dr-nodes" "PASS" ""; else record_result "dr-nodes" "FAIL" ""; failures=$((failures + 1)); fi

dr_ver="$(get_openshift_version)"
record_result "dr-version" "INFO" "${dr_ver}"

if check_version_match; then record_result "version-match" "PASS" ""; else record_result "version-match" "WARN" "${primary_ver} vs ${dr_ver}"; fi

# OADP on both clusters
for label ctx in "primary:${PRIMARY_CONTEXT}" "dr:${DR_CONTEXT}"; do
  name="${label%%:*}"
  ctx_name="${label##*:}"
  use_context "${ctx_name}"
  if oc get ns "${OADP_NAMESPACE}" >/dev/null 2>&1; then
    ok "OADP namespace exists on ${name}"
    record_result "oadp-ns-${name}" "PASS" ""
    if oc get dpa -n "${OADP_NAMESPACE}" -o name 2>/dev/null | grep -q dpa; then
      bsl_phase="$(oc get backupstoragelocation -n "${OADP_NAMESPACE}" -o json 2>/dev/null | jq -r '.items[0].status.phase // "Unknown"')"
      if [[ "${bsl_phase}" == "Available" ]]; then
        ok "BackupStorageLocation Available on ${name}"
        record_result "bsl-${name}" "PASS" "${bsl_phase}"
      else
        warn "BackupStorageLocation not Available on ${name}: ${bsl_phase}"
        record_result "bsl-${name}" "FAIL" "${bsl_phase}"
        failures=$((failures + 1))
      fi
    else
      warn "No DPA found on ${name} — install OADP before backup/restore test"
      record_result "dpa-${name}" "FAIL" "missing"
      failures=$((failures + 1))
    fi
  else
    warn "Namespace ${OADP_NAMESPACE} missing on ${name}"
    record_result "oadp-ns-${name}" "FAIL" "missing"
    failures=$((failures + 1))
  fi
done

# Velero CLI
if velero_available; then
  ok "velero CLI found: $(velero version --client-only 2>/dev/null | head -1 || velero version 2>/dev/null | head -1)"
  record_result "velero-cli" "PASS" ""
else
  warn "velero CLI not found — backup/restore scripts need velero or install from https://velero.io/docs"
  record_result "velero-cli" "WARN" "not installed"
fi

log "Results written to ${RESULTS_FILE}"

if (( failures > 0 )); then
  fail "Preflight failed with ${failures} error(s). Fix issues before continuing."
fi

ok "Preflight passed"
record_result "preflight" "PASS" ""
