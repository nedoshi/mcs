#!/usr/bin/env bash
# Rebuild and restart DB-backed microservices after code changes.
set -euo pipefail

NAMESPACE="${NAMESPACE:-retail-hub}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES=(catalog-service cart-service order-service)

echo "Rebuilding ${SERVICES[*]} in ${NAMESPACE}..."
for svc in "${SERVICES[@]}"; do
  echo "==> ${svc}"
  oc start-build "$svc" --from-dir="$SCRIPT_DIR" --wait --follow -n "$NAMESPACE"
  oc rollout restart "deployment/${svc}" -n "$NAMESPACE"
  oc rollout status "deployment/${svc}" -n "$NAMESPACE" --timeout=300s
done

echo "Done. Verify:"
echo "  oc logs deployment/catalog-service -n ${NAMESPACE} --tail=5"
echo "  # expect: catalog-service listening on 8081"
