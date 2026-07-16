#!/usr/bin/env bash
# Remove IAM role + optional S3 bucket created by setup-iam.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_FILE="${ROOT_DIR}/.demo-state.env"

DELETE_BUCKET="${DELETE_BUCKET:-false}"

log() { printf '\n==> %s\n' "$*"; }

if [[ -f "${STATE_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
else
  echo "No ${STATE_FILE} — set ROLE_NAME / BUCKET env vars or re-run setup first"
  ROLE_NAME="${ROLE_NAME:-irsa-demo-s3-reader}"
fi

export AWS_PAGER=""

if [[ -n "${ROLE_NAME:-}" ]]; then
  log "Detaching inline policy + deleting role ${ROLE_NAME}"
  aws iam delete-role-policy --role-name "${ROLE_NAME}" --policy-name "${ROLE_NAME}-s3" 2>/dev/null || true
  aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null || true
fi

if [[ "${DELETE_BUCKET}" == "true" && -n "${BUCKET:-}" ]]; then
  log "Emptying + deleting bucket ${BUCKET}"
  aws s3 rm "s3://${BUCKET}" --recursive 2>/dev/null || true
  aws s3api delete-bucket --bucket "${BUCKET}" 2>/dev/null || true
else
  echo "Bucket retained (${BUCKET:-unknown}). Delete with: DELETE_BUCKET=true $0"
fi

rm -f "${STATE_FILE}"
log "IAM teardown done"
