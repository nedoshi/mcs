#!/usr/bin/env bash
# Remove Enterprise Retail Hub demo resources
set -euo pipefail

NAMESPACE="${NAMESPACE:-retail-hub}"

if oc get project "$NAMESPACE" >/dev/null 2>&1; then
  echo "Deleting project ${NAMESPACE} (all resources)..."
  oc delete project "$NAMESPACE" --wait=false
  echo "Project deletion initiated. Watch: oc get project ${NAMESPACE}"
else
  echo "Project ${NAMESPACE} not found — nothing to clean up."
fi
