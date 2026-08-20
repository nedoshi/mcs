#!/usr/bin/env bash
# Step 8: Smoke tests on DR cluster (login path, routes, cluster health).
# Usage: ./08-smoke-test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd oc curl

use_context "${DR_CONTEXT}"
log "Smoke tests on DR cluster"
record_result "smoke-test" "START" ""

failures=0

# API reachable
if oc whoami >/dev/null 2>&1; then
  ok "API reachable — logged in as $(oc whoami)"
  record_result "smoke-api" "PASS" "$(oc whoami)"
else
  warn "Not logged in to DR cluster"
  record_result "smoke-api" "FAIL" ""
  failures=$((failures + 1))
fi

# Console route exists
console_url="$(oc whoami --show-console 2>/dev/null || echo "")"
if [[ -n "${console_url}" ]]; then
  ok "Console URL: ${console_url}"
  record_result "smoke-console" "PASS" "${console_url}"
else
  warn "Could not determine console URL"
  record_result "smoke-console" "WARN" ""
fi

# Test app health
if oc get deployment dr-test-app -n "${TEST_NAMESPACE}" >/dev/null 2>&1; then
  ready="$(oc get deployment dr-test-app -n "${TEST_NAMESPACE}" -o jsonpath='{.status.readyReplicas}')"
  if [[ "${ready}" == "1" ]]; then
    ok "dr-test-app deployment ready"
    record_result "smoke-app" "PASS" ""
  else
    warn "dr-test-app not ready (readyReplicas=${ready})"
    record_result "smoke-app" "FAIL" ""
    failures=$((failures + 1))
  fi
fi

# OAuth route (informational — manual Entra login still required)
oauth_host="$(oc get route oauth-openshift -n openshift-authentication -o jsonpath='{.spec.host}' 2>/dev/null || echo "")"
if [[ -n "${oauth_host}" ]]; then
  ok "OAuth route: https://${oauth_host}"
  log "Manual check: open console and verify Entra ID login"
  record_result "smoke-oauth" "INFO" "${oauth_host}"
fi

# Ingress controller
if oc get ingresscontroller default -n openshift-ingress-operator >/dev/null 2>&1; then
  avail="$(oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')"
  [[ "${avail}" == "True" ]] && ok "Ingress controller Available" || warn "Ingress controller not Available"
fi

if (( failures > 0 )); then
  record_result "smoke-test" "FAIL" "${failures} checks failed"
  fail "Smoke tests failed"
fi

ok "Smoke tests passed"
record_result "smoke-test" "PASS" ""
