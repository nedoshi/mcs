#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-rosa-demo}"
DEPLOY="${2:-}"

if [[ -z "${DEPLOY}" ]]; then
  DEPLOY="$(oc get deploy -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | rg -v 'loadgen' | head -1)"
fi

if [[ -z "${DEPLOY}" ]]; then
  echo "No deployment found in ${NAMESPACE}. Pass namespace and deployment name."
  exit 1
fi

SVC="$(oc get svc -n "${NAMESPACE}" -l "app=${DEPLOY}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "${SVC}" ]]; then
  SVC="$(oc get svc -n "${NAMESPACE}" -o jsonpath="{.items[?(@.spec.selector.app=='${DEPLOY}')].metadata.name}" 2>/dev/null || true)"
fi
if [[ -z "${SVC}" ]]; then
  SVC="${DEPLOY}"
fi

ROUTE="$(oc get route -n "${NAMESPACE}" -o jsonpath="{.items[?(@.spec.to.name=='${SVC}')].spec.host}" 2>/dev/null || true)"
if [[ -z "${ROUTE}" ]]; then
  ROUTE="$(oc get route -n "${NAMESPACE}" -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)"
fi

echo "== HPA preflight (${NAMESPACE} / ${DEPLOY}) =="
echo "Service: ${SVC}"
echo "Route:   ${ROUTE:-none}"

echo
echo "-- CPU requests (required for HPA) --"
RESOURCES="$(oc get deploy "${DEPLOY}" -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')"
if [[ -z "${RESOURCES}" ]]; then
  echo "FAIL: no CPU request set"
  echo "Fix:  oc set resources deployment/${DEPLOY} --requests=cpu=50m,memory=128Mi --limits=cpu=200m,memory=256Mi -n ${NAMESPACE}"
else
  echo "OK:   cpu request = ${RESOURCES}"
fi

echo
echo "-- metrics-server --"
if oc get apiservice v1beta1.metrics.k8s.io >/dev/null 2>&1; then
  echo "OK:   metrics-server API registered"
else
  echo "FAIL: metrics-server not available"
fi

echo
echo "-- /api/load endpoint (required for demo load) --"
if [[ -n "${ROUTE}" ]]; then
  LOAD_CODE="$(curl -sk -o /tmp/load.out -w '%{http_code}' "https://${ROUTE}/api/load?ms=50" || true)"
  if [[ "${LOAD_CODE}" == "200" ]]; then
    echo "OK:   https://${ROUTE}/api/load"
    cat /tmp/load.out
    echo
  else
    echo "FAIL: /api/load returned HTTP ${LOAD_CODE}"
    echo "Fix:  push latest code, then: oc start-build ${DEPLOY} -n ${NAMESPACE} --wait"
    echo "      oc rollout restart deployment/${DEPLOY} -n ${NAMESPACE}"
  fi
else
  echo "SKIP: no route found"
fi

echo
echo "-- HPA --"
if oc get hpa "${DEPLOY}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  oc get hpa "${DEPLOY}" -n "${NAMESPACE}"
else
  echo "WARN: no HPA named ${DEPLOY}"
  echo "Fix:  oc apply -f kubernetes/hpa.yaml -n ${NAMESPACE}"
  echo "      (edit scaleTargetRef.name to ${DEPLOY} if needed)"
fi

echo
echo "== Suggested demo setup =="
cat <<EOF
oc set resources deployment/${DEPLOY} \\
  --requests=cpu=50m,memory=128Mi \\
  --limits=cpu=200m,memory=256Mi -n ${NAMESPACE}

oc scale deployment/${DEPLOY} --replicas=1 -n ${NAMESPACE}

# patch HPA/loadgen to target your deployment if names differ
oc set env deployment/rosa-101-loadgen TARGET_URL=http://${SVC}:8080/api/load?ms=300 -n ${NAMESPACE} 2>/dev/null || true
EOF
