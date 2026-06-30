#!/usr/bin/env bash
set -e

BASE_DIR="operators"

mkdir -p "$BASE_DIR"

create_operator() {
  local name=$1
  local namespace=$2
  local subscription_name=$3
  local channel=$4

  echo "➡ Creating $name"

  OP_DIR="$BASE_DIR/$name"
  mkdir -p "$OP_DIR"

  # Namespace
  cat <<EOF > "$OP_DIR/namespace.yaml"
apiVersion: v1
kind: Namespace
metadata:
  name: $namespace
EOF

  # OperatorGroup
  cat <<EOF > "$OP_DIR/operatorgroup.yaml"
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ${name}-og
  namespace: $namespace
spec:
  targetNamespaces:
  - $namespace
EOF

  # Subscription
  cat <<EOF > "$OP_DIR/subscription.yaml"
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: $subscription_name
  namespace: $namespace
spec:
  channel: $channel
  name: $subscription_name
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
}

# -------------------------
# Operators
# -------------------------

create_operator "pipelines" "openshift-operators" "openshift-pipelines-operator" "stable"
create_operator "rhtas" "openshift-operators" "trusted-artifact-signer-operator" "stable"
create_operator "acs" "rhacs-operator" "rhacs-operator" "stable"
create_operator "ai" "redhat-ods-operator" "rhods-operator" "stable"
create_operator "virtualization" "openshift-cnv" "kubevirt-hyperconverged" "stable"

# Root kustomization.yaml
cat <<EOF > "$BASE_DIR/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- pipelines
- rhtas
- acs
- ai
- virtualization
EOF

echo "✅ Operator GitOps structure created successfully"

