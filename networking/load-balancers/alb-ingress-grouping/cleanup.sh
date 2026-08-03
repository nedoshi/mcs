#!/usr/bin/env bash
# Tear down the shared-ALB demo apps (keeps ALBO installed).
set -euo pipefail

NAMESPACE="${NAMESPACE:-shop-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\n==> %s\n' "$*"; }

log "Deleting Ingresses first so ALB can drain / delete"
oc delete -f "${SCRIPT_DIR}/manifests/50-ingress-checkout.yaml" --ignore-not-found || true
oc delete -f "${SCRIPT_DIR}/manifests/40-ingress-catalog.yaml" --ignore-not-found || true

log "Waiting briefly for ALB teardown"
sleep 15

log "Deleting workloads + IngressClass"
oc delete -f "${SCRIPT_DIR}/manifests/30-checkout-service.yaml" --ignore-not-found || true
oc delete -f "${SCRIPT_DIR}/manifests/20-catalog-service.yaml" --ignore-not-found || true
oc delete -f "${SCRIPT_DIR}/manifests/10-ingressclass.yaml" --ignore-not-found || true
oc delete -f "${SCRIPT_DIR}/manifests/00-namespace.yaml" --ignore-not-found || true

log "Done. ALBO remains in aws-load-balancer-operator (remove manually if desired)."
