#!/usr/bin/env bash
# Deploy IRSA demo workloads (identity-demo API + awscli helper).
# Run scripts/setup-iam.sh first.
set -euo pipefail

NAMESPACE="${NAMESPACE:-irsa-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\n==> %s\n' "$*"; }

require_oc() {
  command -v oc >/dev/null 2>&1 || { echo "oc required"; exit 1; }
  oc whoami >/dev/null 2>&1 || { echo "oc login required"; exit 1; }
}

check_prereqs() {
  if ! oc get sa s3-reader -n "${NAMESPACE}" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null | grep -q 'arn:aws:iam'; then
    echo "SA missing eks.amazonaws.com/role-arn annotation. Run: ./scripts/setup-iam.sh"
    exit 1
  fi
  if ! oc get configmap irsa-demo-config -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "ConfigMap irsa-demo-config missing. Run: ./scripts/setup-iam.sh"
    exit 1
  fi
  if ! oc get deploy -A 2>/dev/null | grep -qi pod-identity; then
    echo "WARN: pod-identity-webhook not found — IRSA mutation may fail on non-STS clusters"
  fi
}

main() {
  require_oc
  check_prereqs

  log "Applying manifests"
  oc apply -f "${SCRIPT_DIR}/manifests/00-namespace.yaml"
  oc apply -f "${SCRIPT_DIR}/manifests/10-serviceaccount.yaml"
  # Re-apply annotation if apply wiped it (SA yaml has no annotation)
  if [[ -f "${SCRIPT_DIR}/.demo-state.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/.demo-state.env"
    oc annotate serviceaccount "${SA_NAME}" -n "${NAMESPACE}" \
      "eks.amazonaws.com/role-arn=${ROLE_ARN}" --overwrite
  fi

  oc apply -f "${SCRIPT_DIR}/manifests/20-identity-demo.yaml"
  oc apply -f "${SCRIPT_DIR}/manifests/30-awscli.yaml"

  oc adm policy add-scc-to-user anyuid -z s3-reader -n "${NAMESPACE}" 2>/dev/null || true

  log "Building identity-demo"
  oc start-build identity-demo \
    --from-dir="${SCRIPT_DIR}/apps/identity-demo" \
    --wait --follow -n "${NAMESPACE}"

  log "Waiting for rollouts"
  oc rollout status deployment/identity-demo -n "${NAMESPACE}" --timeout=300s
  oc rollout status deployment/awscli -n "${NAMESPACE}" --timeout=300s

  log "Verify webhook injection (IRSA env vars)"
  POD="$(oc get pod -n "${NAMESPACE}" -l app=identity-demo -o jsonpath='{.items[0].metadata.name}')"
  echo "--- mutated env (expect AWS_ROLE_ARN + AWS_WEB_IDENTITY_TOKEN_FILE) ---"
  oc exec -n "${NAMESPACE}" "${POD}" -- printenv | grep -E '^AWS_' || true

  echo "--- EKS Pod Identity vars (should be empty on ROSA) ---"
  if oc exec -n "${NAMESPACE}" "${POD}" -- printenv AWS_CONTAINER_CREDENTIALS_FULL_URI >/dev/null 2>&1; then
    oc exec -n "${NAMESPACE}" "${POD}" -- printenv AWS_CONTAINER_CREDENTIALS_FULL_URI
  else
    echo "(unset — correct for ROSA IRSA)"
  fi

  URL="$(oc get route identity-demo -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
  echo ""
  echo "  Route:  https://${URL}"
  echo "  curl -s https://${URL}/whoami | jq ."
  echo "  curl -s https://${URL}/env | jq ."
  echo "  curl -s -X POST https://${URL}/s3/ping | jq ."
  echo "  oc rsh -n ${NAMESPACE} deploy/awscli"
  echo "    aws sts get-caller-identity"
  echo "    aws s3 ls \"s3://\$S3_BUCKET/\""
  echo ""
}

main "$@"
