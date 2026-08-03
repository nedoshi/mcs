#!/usr/bin/env bash
# Deploy the shared-ALB (IngressGroup) demo on ROSA HCP.
# Builds catalog-service + checkout-service and applies Ingresses that share one ALB.
set -euo pipefail

NAMESPACE="${NAMESPACE:-shop-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES=(catalog-service checkout-service)

log() { printf '\n==> %s\n' "$*"; }

require_oc() {
  if ! command -v oc >/dev/null 2>&1; then
    echo "oc CLI is required"
    exit 1
  fi
  oc whoami >/dev/null 2>&1 || {
    echo "Not logged in. Run: oc login <api-url>"
    exit 1
  }
}

check_albo() {
  if ! oc get crd ingressclassparams.elbv2.k8s.aws >/dev/null 2>&1; then
    echo "IngressClassParams CRD missing — install ALBO first:"
    echo "  ./scripts/install-albo.sh"
    exit 1
  fi
  if ! oc get awsloadbalancercontroller cluster >/dev/null 2>&1; then
    echo "AWSLoadBalancerController 'cluster' not found — install ALBO first:"
    echo "  ./scripts/install-albo.sh"
    exit 1
  fi
}

build_services() {
  for svc in "${SERVICES[@]}"; do
    log "Building ${svc} (binary Docker build)"
    oc start-build "${svc}" \
      --from-dir="${SCRIPT_DIR}/apps/${svc}" \
      --wait --follow \
      -n "${NAMESPACE}"
  done
}

wait_rollouts() {
  for svc in "${SERVICES[@]}"; do
    log "Waiting for deployment/${svc}"
    oc rollout status "deployment/${svc}" -n "${NAMESPACE}" --timeout=300s
  done
}

print_endpoints() {
  log "Waiting for shared ALB hostname on Ingresses"
  local host=""
  for _ in $(seq 1 60); do
    host="$(oc get ingress catalog-ingress -n "${NAMESPACE}" \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    [[ -n "${host}" ]] && break
    sleep 10
  done

  echo ""
  if [[ -z "${host}" ]]; then
    echo "ALB hostname not ready yet. Check:"
    echo "  oc get ingress -n ${NAMESPACE}"
    echo "  oc -n aws-load-balancer-operator logs deploy/aws-load-balancer-controller-cluster"
    echo "  aws elbv2 describe-load-balancers --query \"LoadBalancers[?contains(LoadBalancerName, 'k8s-')].[LoadBalancerName,DNSName]\" --output table"
    return 0
  fi

  # Both Ingresses should report the SAME hostname (proof of ALB consolidation)
  local checkout_host
  checkout_host="$(oc get ingress checkout-ingress -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

  echo "  Shared ALB DNS : http://${host}"
  echo "  Catalog Ingress: ${host}"
  echo "  Checkout Ingress: ${checkout_host:-pending}"
  echo ""
  if [[ -n "${checkout_host}" && "${host}" == "${checkout_host}" ]]; then
    echo "  ✓ Both Ingresses share the same ALB hostname (IngressGroup working)"
  else
    echo "  ! Hostnames differ or checkout pending — wait and re-check oc get ingress -n ${NAMESPACE}"
  fi
  echo ""
  echo "  Try:"
  echo "    curl -s http://${host}/catalog/products | jq ."
  echo "    curl -s http://${host}/checkout/ | jq ."
  echo "    curl -s -X POST http://${host}/checkout/orders \\"
  echo "      -H 'Content-Type: application/json' \\"
  echo "      -d '{\"items\":[{\"sku\":\"sku-1001\",\"qty\":1}]}' | jq ."
  echo ""
  echo "  AWS console: EC2 → Load Balancers → look for tag ingress.k8s.aws/stack=shop-shared-alb"
}

main() {
  require_oc
  check_albo

  log "Applying namespace + IngressClassParams (shared group)"
  oc apply -f "${SCRIPT_DIR}/manifests/00-namespace.yaml"
  oc apply -f "${SCRIPT_DIR}/manifests/10-ingressclass.yaml"

  log "Applying BuildConfigs / ImageStreams / Deployments / Services"
  oc apply -f "${SCRIPT_DIR}/manifests/20-catalog-service.yaml"
  oc apply -f "${SCRIPT_DIR}/manifests/30-checkout-service.yaml"

  # Allow containers to run as non-root UBI defaults
  oc adm policy add-scc-to-user anyuid -z default -n "${NAMESPACE}" 2>/dev/null || true

  build_services

  log "Applying shared-ALB Ingresses"
  oc apply -f "${SCRIPT_DIR}/manifests/40-ingress-catalog.yaml"
  oc apply -f "${SCRIPT_DIR}/manifests/50-ingress-checkout.yaml"

  wait_rollouts
  print_endpoints
}

main "$@"
