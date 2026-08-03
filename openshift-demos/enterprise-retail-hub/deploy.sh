#!/usr/bin/env bash
# Enterprise Retail Hub — one-command deploy for ROSA / ARO
# Builds all microservices via OpenShift BuildConfigs and applies manifests.
set -euo pipefail

NAMESPACE="${NAMESPACE:-retail-hub}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES=(catalog-service cart-service order-service api-gateway frontend)

log() { printf '\n==> %s\n' "$*"; }

require_oc() {
  if ! command -v oc >/dev/null 2>&1; then
    echo "oc CLI is required. Install from https://docs.openshift.com/cli-reference/openshift-cli/getting-started-cli.html"
    exit 1
  fi
  oc whoami >/dev/null 2>&1 || {
    echo "Not logged in. Run: oc login <cluster-url>"
    exit 1
  }
}

wait_for_postgres() {
  log "Waiting for PostgreSQL to be ready"
  oc wait --for=condition=available deployment/postgres -n "$NAMESPACE" --timeout=300s
  oc wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=120s
}

run_db_init() {
  log "Running idempotent database schema job"
  oc delete job db-init -n "$NAMESPACE" --ignore-not-found
  oc apply -f "${SCRIPT_DIR}/openshift/postgres.yaml"
  oc wait --for=condition=complete job/db-init -n "$NAMESPACE" --timeout=180s
}

build_services() {
  log "Starting OpenShift builds (UBI9 Node.js + Docker strategy)"
  for svc in "${SERVICES[@]}"; do
    log "Building ${svc}..."
    oc start-build "$svc" --from-dir="$SCRIPT_DIR" --wait --follow -n "$NAMESPACE"
  done
}

rollout_services() {
  log "Waiting for microservice rollouts"
  for svc in "${SERVICES[@]}"; do
    oc rollout status "deployment/${svc}" -n "$NAMESPACE" --timeout=300s
  done
}

print_route() {
  log "Deployment complete"
  local url
  url="$(oc get route frontend -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
  if [[ -n "$url" ]]; then
    echo ""
    echo "  Storefront:  https://${url}"
    echo "  Topology:    OpenShift Console → Developer → retail-hub project"
    echo ""
    echo "  Demo flow: browse catalog → add to cart → checkout → verify inventory decrement"
  else
    echo "Route not found. Check: oc get route -n ${NAMESPACE}"
  fi
}

main() {
  require_oc

  log "Creating project ${NAMESPACE}"
  oc new-project "$NAMESPACE" 2>/dev/null || oc project "$NAMESPACE"

  log "Applying PostgreSQL and configuration"
  oc apply -f "${SCRIPT_DIR}/openshift/postgres.yaml"
  oc apply -f "${SCRIPT_DIR}/openshift/config.yaml"

  wait_for_postgres
  run_db_init

  log "Applying BuildConfigs"
  oc apply -f "${SCRIPT_DIR}/openshift/buildconfigs.yaml"

  build_services

  log "Applying Deployments, Services, and Route"
  oc apply -f "${SCRIPT_DIR}/openshift/microservices.yaml"

  # HPA requires metrics-server (available on ROSA/ARO by default)
  if oc get --raw /apis/metrics.k8s.io/v1beta1/nodes >/dev/null 2>&1; then
    oc apply -f "${SCRIPT_DIR}/openshift/hpa.yaml" || true
  else
    log "Skipping HPA — metrics API not available"
  fi

  rollout_services
  print_route
}

main "$@"
