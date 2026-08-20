#!/usr/bin/env bash
# Shared helpers for cross-cloud DR validation scripts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DR_ROOT="$(cd "${SCRIPTS_ROOT}/.." && pwd)"
REPO_ROOT="$(cd "${DR_ROOT}/../.." && pwd)"

# shellcheck source=/dev/null
[[ -f "${SCRIPTS_ROOT}/config.env" ]] && source "${SCRIPTS_ROOT}/config.env"

: "${PRIMARY_CONTEXT:=}"
: "${DR_CONTEXT:=}"
: "${TEST_NAMESPACE:=dr-validation}"
: "${OADP_NAMESPACE:=openshift-adp}"
: "${GITOPS_NAMESPACE:=openshift-gitops}"
: "${BACKUP_NAME_PREFIX:=dr-validation}"
: "${STORAGE_CLASS_MAPPINGS:=managed-csi=gp3-csi-kms,managed-premium=gp3-csi-kms}"
: "${RESULTS_FILE:=${SCRIPTS_ROOT}/results/dr-validation-$(date +%Y%m%d-%H%M%S).log}"

log()  { printf '\n==> %s\n' "$*"; }
ok()   { printf 'OK  %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*" >&2; }
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || fail "Missing required command: ${cmd}"
  done
}

use_context() {
  local ctx="$1"
  [[ -n "${ctx}" ]] || fail "Context not set. Copy config.env.example to config.env and set PRIMARY_CONTEXT / DR_CONTEXT"
  oc config use-context "${ctx}" >/dev/null
  ok "Using context: ${ctx} ($(oc whoami --show-server 2>/dev/null || echo unknown))"
}

current_context() {
  oc config current-context 2>/dev/null || echo ""
}

wait_for_backup() {
  local name="$1"
  local timeout="${2:-600}"
  local elapsed=0

  log "Waiting for backup ${name} (timeout ${timeout}s)"
  while (( elapsed < timeout )); do
    local phase
    phase="$(velero backup get "${name}" -o json 2>/dev/null | jq -r '.status.phase // "Unknown"')" || phase="Unknown"
    case "${phase}" in
      Completed) ok "Backup ${name} completed"; return 0 ;;
      Failed|PartiallyFailed)
        velero backup describe "${name}" --details 2>/dev/null || true
        fail "Backup ${name} ended in phase: ${phase}"
        ;;
    esac
    sleep 10
    elapsed=$((elapsed + 10))
  done
  fail "Timeout waiting for backup ${name}"
}

wait_for_restore() {
  local name="$1"
  local timeout="${2:-900}"
  local elapsed=0

  log "Waiting for restore ${name} (timeout ${timeout}s)"
  while (( elapsed < timeout )); do
    local phase
    phase="$(velero restore get "${name}" -o json 2>/dev/null | jq -r '.status.phase // "Unknown"')" || phase="Unknown"
    case "${phase}" in
      Completed) ok "Restore ${name} completed"; return 0 ;;
      Failed|PartiallyFailed)
        velero restore describe "${name}" --details 2>/dev/null || true
        fail "Restore ${name} ended in phase: ${phase}"
        ;;
    esac
    sleep 10
    elapsed=$((elapsed + 10))
  done
  fail "Timeout waiting for restore ${name}"
}

record_result() {
  local step="$1"
  local status="$2"
  local detail="${3:-}"
  mkdir -p "$(dirname "${RESULTS_FILE}")"
  printf '%s | %s | %s | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${step}" "${status}" "${detail}" >> "${RESULTS_FILE}"
}

check_cluster_operators() {
  local bad
  bad="$(oc get co -o json | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Available" and .status!="True")) | .metadata.name' | head -5)"
  if [[ -n "${bad}" ]]; then
    warn "Some ClusterOperators not Available: ${bad}"
    return 1
  fi
  ok "All ClusterOperators Available"
  return 0
}

check_nodes_ready() {
  local not_ready
  not_ready="$(oc get nodes -o json | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status!="True")) | .metadata.name' | head -5)"
  if [[ -n "${not_ready}" ]]; then
    warn "Some nodes not Ready: ${not_ready}"
    return 1
  fi
  ok "All nodes Ready"
  return 0
}

get_openshift_version() {
  oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown"
}

check_version_match() {
  local primary_ver dr_ver
  use_context "${PRIMARY_CONTEXT}"
  primary_ver="$(get_openshift_version)"
  use_context "${DR_CONTEXT}"
  dr_ver="$(get_openshift_version)"
  log "OpenShift versions — primary: ${primary_ver}, DR: ${dr_ver}"
  if [[ "${primary_ver}" != "${dr_ver}" ]]; then
    warn "Version mismatch — cross-cloud restore may fail. Align minor versions before production DR."
    return 1
  fi
  ok "OpenShift versions match"
  return 0
}

velero_available() {
  command -v velero >/dev/null 2>&1
}
