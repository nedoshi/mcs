#!/usr/bin/env bash
#
# ROSA 101 resource limits demo for rosa-101-welcome.
# Based on Red Hat / OpenShift resource management workshop flow:
#   https://github.com/bcgov/devops-platform-workshops/blob/master/openshift-201/resource-mgmt.md
#
# Usage:
#   ./scripts/demo-resource-limits.sh [namespace] [deployment]
#
# Example:
#   ./scripts/demo-resource-limits.sh rosa-demo rosa-demo
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NAMESPACE="${1:-rosa-demo}"
DEPLOY="${2:-rosa-demo}"

step() {
  echo
  echo "==> $1"
  echo
}

pause() {
  read -r -p "Press Enter to continue (Ctrl+C to stop)..."
}

SVC="$(oc get svc -n "${NAMESPACE}" -o jsonpath="{.items[?(@.spec.selector.app=='${DEPLOY}')].metadata.name}" 2>/dev/null || true)"
if [[ -z "${SVC}" ]]; then
  SVC="${DEPLOY}"
fi

ROUTE="$(oc get route -n "${NAMESPACE}" -o jsonpath="{.items[?(@.spec.to.name=='${SVC}')].spec.host}" 2>/dev/null || true)"
if [[ -z "${ROUTE}" ]]; then
  ROUTE="$(oc get route -n "${NAMESPACE}" -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)"
fi

step "1. Confirm deployment and route"
echo "Namespace:   ${NAMESPACE}"
echo "Deployment:  ${DEPLOY}"
echo "Service:     ${SVC}"
echo "Route:       ${ROUTE:-not found}"
oc get deploy,svc,route -n "${NAMESPACE}" 2>/dev/null | rg "${DEPLOY}|NAME" || oc get deploy,svc,route -n "${NAMESPACE}"
pause

step "2. Set initial requests and limits (workshop baseline)"
echo "requests: cpu=50m  memory=128Mi"
echo "limits:   cpu=200m memory=256Mi"
oc set resources deployment/"${DEPLOY}" \
  --requests=cpu=50m,memory=128Mi \
  --limits=cpu=200m,memory=256Mi \
  -n "${NAMESPACE}"
oc rollout status deployment/"${DEPLOY}" -n "${NAMESPACE}"
oc describe deploy/"${DEPLOY}" -n "${NAMESPACE}" | rg -A6 "Limits|Requests|QoS"
pause

step "3. Tighten CPU limit to show throttling under load"
echo "requests: cpu=50m  memory=128Mi  (unchanged)"
echo "limits:   cpu=100m memory=200Mi  (tighter)"
oc set resources deployment/"${DEPLOY}" \
  --requests=cpu=50m,memory=128Mi \
  --limits=cpu=100m,memory=200Mi \
  -n "${NAMESPACE}"
oc rollout status deployment/"${DEPLOY}" -n "${NAMESPACE}"
POD="$(oc get pod -n "${NAMESPACE}" -l "app=${DEPLOY}" -o jsonpath='{.items[0].metadata.name}')"
echo "QoS class: $(oc get pod "${POD}" -n "${NAMESPACE}" -o jsonpath='{.status.qosClass}')"
pause

step "4. Run load test Job"
if [[ -z "${ROUTE}" ]]; then
  echo "No route found. Expose the service first:"
  echo "  oc expose svc/${SVC} -n ${NAMESPACE}"
  echo "  oc create route edge --service=${SVC} -n ${NAMESPACE}"
  exit 1
fi

oc delete job rosa-101-load-test -n "${NAMESPACE}" --ignore-not-found
sed "s/REPLACE_WITH_ROUTE_HOST/${ROUTE}/" "${APP_DIR}/kubernetes/load-test-job.yaml" | oc apply -n "${NAMESPACE}" -f -
echo "Watch load test:"
echo "  oc logs -f job/rosa-101-load-test -n ${NAMESPACE}"
pause
oc logs -f job/rosa-101-load-test -n "${NAMESPACE}" || true
pause

step "5. View requests, limits, and actual usage"
oc describe pod -l "app=${DEPLOY}" -n "${NAMESPACE}" | rg -A4 "Limits|Requests|QoS"
echo
oc adm top pods -l "app=${DEPLOY}" -n "${NAMESPACE}" || echo "Metrics not ready yet — wait 30s and retry"
pause

step "6. Optional — Guaranteed QoS (requests == limits)"
echo "Setting requests and limits to the same values -> Guaranteed QoS"
oc set resources deployment/"${DEPLOY}" \
  --requests=cpu=100m,memory=200Mi \
  --limits=cpu=100m,memory=200Mi \
  -n "${NAMESPACE}"
oc rollout status deployment/"${DEPLOY}" -n "${NAMESPACE}"
POD="$(oc get pod -n "${NAMESPACE}" -l "app=${DEPLOY}" -o jsonpath='{.items[0].metadata.name}')"
echo "QoS class: $(oc get pod "${POD}" -n "${NAMESPACE}" -o jsonpath='{.status.qosClass}')"
pause

step "7. Optional — apply LimitRange and ResourceQuota"
oc apply -f "${APP_DIR}/kubernetes/limit-range.yaml" -n "${NAMESPACE}"
oc apply -f "${APP_DIR}/kubernetes/resource-quota.yaml" -n "${NAMESPACE}"
oc describe limitrange rosa-101-limits -n "${NAMESPACE}"
oc describe quota rosa-101-quota -n "${NAMESPACE}"
pause

step "8. Restore comfortable limits for day-to-day demo"
oc set resources deployment/"${DEPLOY}" \
  --requests=cpu=50m,memory=128Mi \
  --limits=cpu=200m,memory=256Mi \
  -n "${NAMESPACE}"
oc rollout status deployment/"${DEPLOY}" -n "${NAMESPACE}"

echo
echo "Demo complete."
echo
echo "Cleanup (optional):"
echo "  oc delete job rosa-101-load-test -n ${NAMESPACE}"
echo "  oc delete -f ${APP_DIR}/kubernetes/limit-range.yaml -n ${NAMESPACE}"
echo "  oc delete -f ${APP_DIR}/kubernetes/resource-quota.yaml -n ${NAMESPACE}"
