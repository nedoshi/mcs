#!/usr/bin/env bash
# Step 3: Verify OADP configuration on primary and DR clusters.
# Usage: ./03-verify-oadp.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd oc jq

failures=0

verify_oadp_on_cluster() {
  local label="$1"
  local ctx="$2"
  use_context "${ctx}"
  log "Verifying OADP on ${label}"

  oc get ns "${OADP_NAMESPACE}" >/dev/null 2>&1 || { warn "Missing ${OADP_NAMESPACE}"; return 1; }

  local dpa_count
  dpa_count="$(oc get dpa -n "${OADP_NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  [[ "${dpa_count}" -ge 1 ]] || { warn "No DPA on ${label}"; return 1; }
  ok "DPA count on ${label}: ${dpa_count}"

  local node_agent
  node_agent="$(oc get dpa -n "${OADP_NAMESPACE}" -o json | jq -r '.items[0].spec.configuration.nodeAgent.enable // false')"
  if [[ "${node_agent}" == "true" ]]; then
    ok "nodeAgent (Kopia) enabled on ${label}"
  else
    warn "nodeAgent not enabled on ${label} — cross-cloud PV restore requires Kopia"
    return 1
  fi

  local bsl_phase
  bsl_phase="$(oc get backupstoragelocation -n "${OADP_NAMESPACE}" -o json | jq -r '.items[] | select(.spec.default==true) | .status.phase' | head -1)"
  [[ "${bsl_phase}" == "Available" ]] || { warn "Default BSL phase on ${label}: ${bsl_phase}"; return 1; }
  ok "Default BackupStorageLocation Available on ${label}"

  oc get pods -n "${OADP_NAMESPACE}" -l app.kubernetes.io/name=velero --no-headers 2>/dev/null | grep -q Running && ok "Velero pod Running on ${label}" || warn "Velero pod not Running on ${label}"

  return 0
}

verify_oadp_on_cluster "primary" "${PRIMARY_CONTEXT}" && record_result "oadp-primary" "PASS" "" || { record_result "oadp-primary" "FAIL" ""; failures=$((failures + 1)); }
verify_oadp_on_cluster "dr" "${DR_CONTEXT}" && record_result "oadp-dr" "PASS" "" || { record_result "oadp-dr" "FAIL" ""; failures=$((failures + 1)); }

# Confirm both clusters point at same bucket prefix (best effort)
use_context "${PRIMARY_CONTEXT}"
primary_bucket="$(oc get backupstoragelocation -n "${OADP_NAMESPACE}" -o json 2>/dev/null | jq -r '.items[] | select(.spec.default==true) | .spec.objectStorage.bucket // .spec.config.bucket // empty' | head -1)"
use_context "${DR_CONTEXT}"
dr_bucket="$(oc get backupstoragelocation -n "${OADP_NAMESPACE}" -o json 2>/dev/null | jq -r '.items[] | select(.spec.default==true) | .spec.objectStorage.bucket // .spec.config.bucket // empty' | head -1)"

log "Backup buckets — primary: ${primary_bucket:-unknown}, DR: ${dr_bucket:-unknown}"
if [[ -n "${primary_bucket}" && -n "${dr_bucket}" && "${primary_bucket}" == "${dr_bucket}" ]]; then
  ok "Both clusters use same backup bucket"
  record_result "shared-bucket" "PASS" "${primary_bucket}"
else
  warn "Could not confirm shared S3 bucket — verify manually"
  record_result "shared-bucket" "WARN" "${primary_bucket} vs ${dr_bucket}"
fi

(( failures == 0 )) || fail "OADP verification failed"
ok "OADP verification passed"
record_result "verify-oadp" "PASS" ""
