#!/usr/bin/env bash
# Install AWS Load Balancer Operator + Controller on ROSA (STS / HCP-compatible).
# Adapted from: https://cloud.redhat.com/experts/rosa/aws-load-balancer-operator/
#
# Prerequisites: oc logged in as cluster-admin, aws CLI configured, jq optional.
set -euo pipefail

log() { printf '\n==> %s\n' "$*"; }

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required binary: $1"
    exit 1
  }
}

require oc
require aws

oc whoami >/dev/null 2>&1 || {
  echo "Not logged in. Run: oc login ..."
  exit 1
}

export AWS_PAGER=""
ROSA_CLUSTER_NAME="${ROSA_CLUSTER_NAME:-$(oc get infrastructure cluster -o=jsonpath='{.status.infrastructureName}' | sed 's/-[a-z0-9]\{5\}$//')}"
REGION="${REGION:-$(oc get infrastructure cluster -o=jsonpath='{.status.platformStatus.aws.region}')}"
OIDC_ENDPOINT="${OIDC_ENDPOINT:-$(oc get authentication.config.openshift.io cluster -o jsonpath='{.spec.serviceAccountIssuer}' | sed 's|^https://||')}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
SCRATCH="${SCRATCH:-/tmp/${ROSA_CLUSTER_NAME}/alb-operator}"
POLICY_NAME="${POLICY_NAME:-aws-load-balancer-operator-policy}"
ROLE_NAME="${ROLE_NAME:-${ROSA_CLUSTER_NAME}-alb-operator}"

mkdir -p "${SCRATCH}"
log "Cluster=${ROSA_CLUSTER_NAME} Region=${REGION} Account=${AWS_ACCOUNT_ID}"
echo "OIDC=${OIDC_ENDPOINT}"

# Optional: tag BYO VPC subnets (skip if ROSA created the VPC with correct tags)
if [[ -n "${VPC_ID:-}" && -n "${PUBLIC_SUBNET_IDS:-}" ]]; then
  log "Tagging VPC/subnets for ALB discovery"
  CLUSTER_INFRA="$(oc get infrastructure cluster -o=jsonpath='{.status.infrastructureName}')"
  aws ec2 create-tags --resources "${VPC_ID}" \
    --tags "Key=kubernetes.io/cluster/${CLUSTER_INFRA},Value=owned" --region "${REGION}"
  # shellcheck disable=SC2086
  aws ec2 create-tags --resources ${PUBLIC_SUBNET_IDS} \
    --tags "Key=kubernetes.io/role/elb,Value=" --region "${REGION}"
  if [[ -n "${PRIVATE_SUBNET_IDS:-}" ]]; then
    # shellcheck disable=SC2086
    aws ec2 create-tags --resources ${PRIVATE_SUBNET_IDS} \
      --tags "Key=kubernetes.io/role/internal-elb,Value=" --region "${REGION}"
  fi
fi

log "Ensuring IAM policy ${POLICY_NAME}"
POLICY_ARN="$(aws iam list-policies --scope Local --query \
  "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text 2>/dev/null || true)"
if [[ -z "${POLICY_ARN}" || "${POLICY_ARN}" == "None" ]]; then
  curl -fsSL -o "${SCRATCH}/load-balancer-operator-policy.json" \
    https://raw.githubusercontent.com/rh-mobb/documentation/main/content/rosa/aws-load-balancer-operator/load-balancer-operator-policy.json
  POLICY_ARN="$(aws --region "${REGION}" --query Policy.Arn --output text iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document "file://${SCRATCH}/load-balancer-operator-policy.json")"
fi
echo "POLICY_ARN=${POLICY_ARN}"

log "Creating / updating IAM role ${ROLE_NAME}"
cat > "${SCRATCH}/trust-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ENDPOINT}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_ENDPOINT}:sub": [
            "system:serviceaccount:aws-load-balancer-operator:aws-load-balancer-operator-controller-manager",
            "system:serviceaccount:aws-load-balancer-operator:aws-load-balancer-controller-cluster"
          ]
        }
      }
    }
  ]
}
EOF

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  ROLE_ARN="$(aws iam get-role --role-name "${ROLE_NAME}" --query Role.Arn --output text)"
  aws iam update-assume-role-policy --role-name "${ROLE_NAME}" \
    --policy-document "file://${SCRATCH}/trust-policy.json"
else
  ROLE_ARN="$(aws iam create-role --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "file://${SCRATCH}/trust-policy.json" \
    --query Role.Arn --output text)"
fi
aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${POLICY_ARN}" || true
echo "ROLE_ARN=${ROLE_ARN}"

log "Creating project + credentials secret"
oc new-project aws-load-balancer-operator 2>/dev/null || oc project aws-load-balancer-operator

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: aws-load-balancer-operator
  namespace: aws-load-balancer-operator
stringData:
  credentials: |
    [default]
    role_arn = ${ROLE_ARN}
    web_identity_token_file = /var/run/secrets/openshift/serviceaccount/token
EOF

log "Installing AWS Load Balancer Operator (OLM Subscription)"
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: aws-load-balancer-operator
  namespace: aws-load-balancer-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: aws-load-balancer-operator
  namespace: aws-load-balancer-operator
spec:
  channel: stable-v1
  installPlanApproval: Automatic
  name: aws-load-balancer-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

log "Waiting for Operator CSV to succeed"
for _ in $(seq 1 60); do
  PHASE="$(oc get csv -n aws-load-balancer-operator \
    -l operators.coreos.com/aws-load-balancer-operator.aws-load-balancer-operator \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)"
  [[ "${PHASE}" == "Succeeded" ]] && break
  sleep 10
done
echo "CSV phase=${PHASE:-unknown}"

log "Creating AWSLoadBalancerController (default IngressClass: alb)"
cat <<EOF | oc apply -f -
apiVersion: networking.olm.openshift.io/v1
kind: AWSLoadBalancerController
metadata:
  name: cluster
spec:
  subnetTagging: Auto
  credentials:
    name: aws-load-balancer-operator
  ingressClass: alb
EOF

log "Waiting for controller pod"
oc wait --for=condition=available \
  deployment/aws-load-balancer-operator-controller-manager \
  -n aws-load-balancer-operator --timeout=300s || true

for _ in $(seq 1 36); do
  if oc get pods -n aws-load-balancer-operator -l app.kubernetes.io/name=aws-load-balancer-controller \
    --no-headers 2>/dev/null | grep -q Running; then
    break
  fi
  # Controller deployment name pattern used by ALBO
  if oc get deploy -n aws-load-balancer-operator 2>/dev/null | grep -q aws-load-balancer-controller; then
    oc wait --for=condition=available \
      -n aws-load-balancer-operator \
      deploy -l app.kubernetes.io/name=aws-load-balancer-controller \
      --timeout=30s 2>/dev/null && break || true
  fi
  sleep 10
done

oc get pods -n aws-load-balancer-operator
log "ALBO install complete. Next: ./deploy.sh"
