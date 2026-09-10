#!/bin/bash
# ARO HCP validation harness — run after external auth is configured.
# Records pass/fail to stdout; use with README pass/fail matrix.
#
# Prerequisites:
#   export KUBECONFIG=/path/to/aro-cluster.kubeconfig  (admin credential)
#   export OPENSHIFT_API_URL=...                       (optional cross-check)
#   export EXTERNAL_AUTH_NAME=aro-hcp-auth             (default)

set -euo pipefail

EXTERNAL_AUTH_NAME="${EXTERNAL_AUTH_NAME:-aro-hcp-auth}"
PASS=0
FAIL=0
BLOCKED=0

pass() { echo "[PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $*"; FAIL=$((FAIL + 1)); }
blocked() { echo "[BLOCKED] $*"; BLOCKED=$((BLOCKED + 1)); }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    blocked "Missing required command: $1"
    return 1
  fi
  return 0
}

echo "=== ARO HCP validation harness ==="
echo "Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "KUBECONFIG: ${KUBECONFIG:-not set}"
echo

for cmd in oc jq az; do
  require_cmd "$cmd" || exit 1
done

if [ -z "${KUBECONFIG:-}" ] || [ ! -f "${KUBECONFIG}" ]; then
  blocked "KUBECONFIG not set or file missing — run request-aro-admin-credential.sh first"
  echo
  echo "Summary: PASS=${PASS} FAIL=${FAIL} BLOCKED=${BLOCKED}"
  exit 2
fi

# 1. Cluster API reachable
if oc cluster-info >/dev/null 2>&1; then
  pass "Cluster API reachable (oc cluster-info)"
else
  fail "Cluster API not reachable"
fi

# 2. Cluster operators
if unavailable=$(oc get clusteroperators -o json | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Available" and .status!="True")) | .metadata.name' | head -5); then
  if [ -z "${unavailable}" ]; then
    pass "All ClusterOperators Available"
  else
    fail "Unavailable ClusterOperators: ${unavailable}"
  fi
fi

# 3. Nodes
node_count=$(oc get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${node_count}" -gt 0 ]; then
  pass "Worker nodes present (count=${node_count})"
else
  fail "No worker nodes reported"
fi

# 4. Console route
if console_host=$(oc get route console -n openshift-console -o jsonpath='{.spec.host}' 2>/dev/null) && [ -n "${console_host}" ]; then
  pass "Console route exists: https://${console_host}"
  export OCP_CONSOLE="https://${console_host}"
else
  fail "Console route not found in openshift-console namespace"
fi

# 5. External auth console secret naming convention
secret_name="${EXTERNAL_AUTH_NAME}-console-openshift-console"
if oc get secret "${secret_name}" -n openshift-config >/dev/null 2>&1; then
  pass "Console client secret exists: openshift-config/${secret_name}"
else
  fail "Missing secret openshift-config/${secret_name} — see 03-external-auth-rhbk.md"
fi

# 6. ARM cluster provisioning state (requires az + env vars)
if [ -n "${ARO_CLUSTER_NAME:-}" ] && [ -n "${ARO_RESOURCE_GROUP:-}" ]; then
  sub_id="${ARO_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
  state=$(az rest --method GET \
    --uri "/subscriptions/${sub_id}/resourceGroups/${ARO_RESOURCE_GROUP}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${ARO_CLUSTER_NAME}?api-version=2024-06-10-preview" \
    -o json 2>/dev/null | jq -r '.properties.provisioningState // .properties.clusterState // "unknown"') || state="unknown"
  if [ "${state}" = "Succeeded" ]; then
    pass "ARM provisioningState=Succeeded"
  else
    fail "ARM cluster state: ${state} (expected Succeeded)"
  fi
else
  blocked "ARO_CLUSTER_NAME / ARO_RESOURCE_GROUP not set — skipping ARM state check"
fi

# 7. MachineSets (day-2 scaling prerequisite)
if oc get machinesets -A --no-headers 2>/dev/null | grep -q .; then
  pass "MachineSets present (scaling smoke test prerequisite)"
else
  blocked "No MachineSets found — scaling tests may differ on HCP"
fi

echo
echo "=== Summary: PASS=${PASS} FAIL=${FAIL} BLOCKED=${BLOCKED} ==="
if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi
exit 0
