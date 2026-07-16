#!/usr/bin/env bash
# Create IAM role + trust (OIDC) + scoped S3 bucket for the IRSA demo.
# Annotates ServiceAccount s3-reader with eks.amazonaws.com/role-arn.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_FILE="${ROOT_DIR}/.demo-state.env"

NAMESPACE="${NAMESPACE:-irsa-demo}"
SA_NAME="${SA_NAME:-s3-reader}"
ROLE_NAME="${ROLE_NAME:-irsa-demo-s3-reader}"

log() { printf '\n==> %s\n' "$*"; }

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }
}

require oc
require aws

oc whoami >/dev/null 2>&1 || { echo "oc login required"; exit 1; }

export AWS_PAGER=""
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGION="${REGION:-$(oc get infrastructure cluster -o=jsonpath='{.status.platformStatus.aws.region}')}"
OIDC_PROVIDER="$(oc get authentication.config.openshift.io cluster -o jsonpath='{.spec.serviceAccountIssuer}' | sed 's|^https://||')"
OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"

# Unique-ish bucket name (S3 global namespace)
SUFFIX="$(echo "${OIDC_PROVIDER}" | tr -cd 'a-z0-9' | tail -c 8)"
BUCKET="${BUCKET:-irsa-demo-${AWS_ACCOUNT_ID}-${SUFFIX}}"
BUCKET="$(echo "${BUCKET}" | tr '[:upper:]' '[:lower:]' | cut -c1-63)"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "${SCRATCH}"' EXIT

log "Account=${AWS_ACCOUNT_ID} Region=${REGION}"
echo "OIDC=${OIDC_PROVIDER}"
echo "BUCKET=${BUCKET}"

log "Ensuring namespace + ServiceAccount"
oc apply -f "${ROOT_DIR}/manifests/00-namespace.yaml"
oc apply -f "${ROOT_DIR}/manifests/10-serviceaccount.yaml"

log "Writing IAM trust policy (IRSA — NOT EKS Pod Identity)"
# Trust is Federated OIDC + sub=system:serviceaccount:ns:sa
# EKS Pod Identity would instead trust pods.eks.amazonaws.com — unsupported on ROSA.
cat > "${SCRATCH}/trust.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:${SA_NAME}",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

cat > "${SCRATCH}/policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::${BUCKET}"
    },
    {
      "Sid": "ObjectRW",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::${BUCKET}/*"
    }
  ]
}
EOF

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  log "Updating trust on existing role ${ROLE_NAME}"
  aws iam update-assume-role-policy --role-name "${ROLE_NAME}" \
    --policy-document "file://${SCRATCH}/trust.json"
else
  log "Creating role ${ROLE_NAME}"
  aws iam create-role --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "file://${SCRATCH}/trust.json" \
    --description "ROSA HCP IRSA demo — S3 reader for ${NAMESPACE}/${SA_NAME}" \
    >/dev/null
fi

ROLE_ARN="$(aws iam get-role --role-name "${ROLE_NAME}" --query Role.Arn --output text)"
aws iam put-role-policy --role-name "${ROLE_NAME}" \
  --policy-name "${ROLE_NAME}-s3" \
  --policy-document "file://${SCRATCH}/policy.json"

log "Ensuring S3 bucket ${BUCKET}"
if ! aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" >/dev/null
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  fi
fi
aws s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "demo $(date -u +%Y-%m-%dT%H:%M:%SZ)" | aws s3 cp - "s3://${BUCKET}/irsa-demo/README.txt"

log "Annotating SA (IRSA binding — equivalent of EKS association)"
oc annotate serviceaccount "${SA_NAME}" -n "${NAMESPACE}" \
  "eks.amazonaws.com/role-arn=${ROLE_ARN}" --overwrite

log "Writing ConfigMap + local state"
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: irsa-demo-config
  namespace: ${NAMESPACE}
data:
  S3_BUCKET: "${BUCKET}"
  AWS_REGION: "${REGION}"
  ROLE_ARN: "${ROLE_ARN}"
  MECHANISM: "IRSA"
EOF

cat > "${STATE_FILE}" <<EOF
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
REGION=${REGION}
OIDC_PROVIDER=${OIDC_PROVIDER}
ROLE_NAME=${ROLE_NAME}
ROLE_ARN=${ROLE_ARN}
BUCKET=${BUCKET}
NAMESPACE=${NAMESPACE}
SA_NAME=${SA_NAME}
EOF

echo ""
echo "  ROLE_ARN = ${ROLE_ARN}"
echo "  BUCKET   = ${BUCKET}"
echo "  Next     : ./deploy.sh"
echo ""
