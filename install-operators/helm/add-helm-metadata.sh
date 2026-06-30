#!/bin/bash
# Script to add Helm metadata to existing resources (namespaces, operatorgroups, subscriptions)
# Usage: ./add-helm-metadata.sh <release-name> <release-namespace>

set -e

RELEASE_NAME=${1:-openshift-operators}
RELEASE_NAMESPACE=${2:-operators}

echo "Adding Helm metadata to existing resources..."
echo "Release Name: $RELEASE_NAME"
echo "Release Namespace: $RELEASE_NAMESPACE"
echo ""

# Function to add Helm metadata to a resource
add_helm_metadata() {
  local KIND=$1
  local NAME=$2
  local NS=$3
  
  if oc get "$KIND" "$NAME" -n "$NS" &>/dev/null; then
    echo "  Processing $KIND $NAME in namespace $NS"
    
    # Add label
    oc label "$KIND" "$NAME" -n "$NS" app.kubernetes.io/managed-by=Helm --overwrite
    
    # Add annotations
    oc annotate "$KIND" "$NAME" -n "$NS" meta.helm.sh/release-name="$RELEASE_NAME" --overwrite
    oc annotate "$KIND" "$NAME" -n "$NS" meta.helm.sh/release-namespace="$RELEASE_NAMESPACE" --overwrite
    
    echo "    ✓ Added Helm metadata"
    return 0
  else
    echo "    ⊘ $KIND $NAME does not exist, skipping"
    return 1
  fi
}

# List of operator namespaces and their resources
declare -A OPERATORS=(
  ["openshift-operators:pipelines"]="pipelines-og:openshift-pipelines-operator"
  ["openshift-operators:rhtas"]="rhtas-og:trusted-artifact-signer-operator"
  ["rhacs-operator:acs"]="acs-og:rhacs-operator"
  ["redhat-ods-operator:ai"]="ai-og:rhods-operator"
  ["openshift-cnv:virtualization"]="virtualization-og:kubevirt-hyperconverged"
  ["rhdh-operator:developer-hub"]="developer-hub-og:rhdh"
  ["openshift-gitops-operator:gitops"]="openshift-gitops-operator:openshift-gitops-operator"
)

# Process namespaces
echo "=== Processing Namespaces ==="
for KEY in "${!OPERATORS[@]}"; do
  NS="${KEY%%:*}"
  if oc get namespace "$NS" &>/dev/null; then
    echo "Processing namespace: $NS"
    oc label namespace "$NS" app.kubernetes.io/managed-by=Helm --overwrite
    oc annotate namespace "$NS" meta.helm.sh/release-name="$RELEASE_NAME" --overwrite
    oc annotate namespace "$NS" meta.helm.sh/release-namespace="$RELEASE_NAMESPACE" --overwrite
    echo "  ✓ Added Helm metadata to namespace $NS"
  else
    echo "  ⊘ Namespace $NS does not exist, skipping"
  fi
done

echo ""
echo "=== Processing OperatorGroups ==="
for KEY in "${!OPERATORS[@]}"; do
  NS="${KEY%%:*}"
  OG_NAME="${OPERATORS[$KEY]%%:*}"
  add_helm_metadata "operatorgroup" "$OG_NAME" "$NS"
done

echo ""
echo "=== Processing Subscriptions ==="
for KEY in "${!OPERATORS[@]}"; do
  NS="${KEY%%:*}"
  SUB_NAME="${OPERATORS[$KEY]##*:}"
  add_helm_metadata "subscription" "$SUB_NAME" "$NS"
done

echo ""
echo "✅ Completed! You can now install the Helm chart:"
echo "   helm install $RELEASE_NAME . --namespace $RELEASE_NAMESPACE --create-namespace"

