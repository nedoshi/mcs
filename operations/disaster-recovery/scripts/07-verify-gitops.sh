#!/usr/bin/env bash
# Step 7: Verify GitOps / Argo CD on DR cluster.
# Usage: ./07-verify-gitops.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd oc jq

use_context "${DR_CONTEXT}"
log "Verifying GitOps on DR cluster"
record_result "verify-gitops" "START" ""

if ! oc get ns "${GITOPS_NAMESPACE}" >/dev/null 2>&1; then
  warn "Namespace ${GITOPS_NAMESPACE} not found — OpenShift GitOps may not be installed"
  record_result "verify-gitops" "WARN" "no gitops namespace"
  exit 0
fi

# Argo CD operator / instance
if oc get deployment openshift-gitops-server -n "${GITOPS_NAMESPACE}" >/dev/null 2>&1; then
  ready="$(oc get deployment openshift-gitops-server -n "${GITOPS_NAMESPACE}" -o jsonpath='{.status.readyReplicas}')"
  desired="$(oc get deployment openshift-gitops-server -n "${GITOPS_NAMESPACE}" -o jsonpath='{.status.replicas}')"
  if [[ "${ready}" == "${desired}" && "${ready}" != "0" ]]; then
    ok "openshift-gitops-server ready (${ready}/${desired})"
  else
    warn "openshift-gitops-server not fully ready (${ready}/${desired})"
  fi
else
  warn "openshift-gitops-server deployment not found"
fi

# Application health
apps="$(oc get applications.argoproj.io -n "${GITOPS_NAMESPACE}" -o json 2>/dev/null || echo '{"items":[]}')"
total="$(echo "${apps}" | jq '.items | length')"
synced="$(echo "${apps}" | jq '[.items[] | select(.status.sync.status=="Synced")] | length')"
healthy="$(echo "${apps}" | jq '[.items[] | select(.status.health.status=="Healthy")] | length')"

log "Applications: total=${total}, synced=${synced}, healthy=${healthy}"

if (( total > 0 )); then
  echo "${apps}" | jq -r '.items[] | "\(.metadata.name)\t\(.status.sync.status)\t\(.status.health.status)"' | column -t -s $'\t' || true

  degraded="$(echo "${apps}" | jq -r '.items[] | select(.status.sync.status!="Synced" or .status.health.status!="Healthy") | .metadata.name')"
  if [[ -n "${degraded}" ]]; then
    warn "Degraded applications:\n${degraded}"
    record_result "verify-gitops" "WARN" "degraded apps present"
  else
    ok "All applications Synced and Healthy"
    record_result "verify-gitops" "PASS" "all healthy"
  fi
else
  warn "No Argo CD Applications found — register cluster in ACM or bootstrap GitOps"
  record_result "verify-gitops" "WARN" "no applications"
fi

# Optional hub check
if [[ -n "${HUB_CONTEXT:-}" ]]; then
  use_context "${HUB_CONTEXT}"
  log "Checking ManagedCluster labels on hub"
  oc get managedcluster -o custom-columns=NAME:.metadata.name,DR-PAIR:.metadata.labels.dr-pair,DR-ROLE:.metadata.labels.dr-role 2>/dev/null || warn "Could not list ManagedClusters"
fi

ok "GitOps verification complete"
