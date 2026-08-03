#!/usr/bin/env bash
# Tear down the db-migration lab project.
set -euo pipefail

NS="${NAMESPACE:-db-migration}"

command -v oc >/dev/null || { echo "Missing oc"; exit 1; }
oc whoami >/dev/null 2>&1 || { echo "oc login required"; exit 1; }

echo "==> Deleting project ${NS}"
oc delete project "${NS}" --wait=false 2>/dev/null || oc delete namespace "${NS}" --wait=false
echo "Delete issued. PVC reclaim may take a minute."
