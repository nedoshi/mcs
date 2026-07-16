#!/usr/bin/env bash
# Remove cluster resources for the IRSA demo (IAM/S3 via scripts/teardown-iam.sh).
set -euo pipefail

NAMESPACE="${NAMESPACE:-irsa-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\n==> %s\n' "$*"; }

log "Deleting workloads + namespace"
oc delete -f "${SCRIPT_DIR}/manifests/30-awscli.yaml" --ignore-not-found || true
oc delete -f "${SCRIPT_DIR}/manifests/20-identity-demo.yaml" --ignore-not-found || true
oc delete configmap irsa-demo-config -n "${NAMESPACE}" --ignore-not-found || true
oc delete -f "${SCRIPT_DIR}/manifests/10-serviceaccount.yaml" --ignore-not-found || true
oc delete -f "${SCRIPT_DIR}/manifests/00-namespace.yaml" --ignore-not-found || true

log "Cluster cleanup done. IAM/S3: ./scripts/teardown-iam.sh  (add DELETE_BUCKET=true to drop bucket)"
