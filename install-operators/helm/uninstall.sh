#!/bin/bash
# Script to uninstall Helm release and optionally clean up resources
# Usage: ./uninstall.sh [--clean-all]

set -e

RELEASE_NAME=${RELEASE_NAME:-openshift-operators}
RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-operators}
CLEAN_ALL=false

if [[ "$1" == "--clean-all" ]]; then
  CLEAN_ALL=true
fi

echo "Uninstalling Helm release: $RELEASE_NAME"
echo "Release Namespace: $RELEASE_NAMESPACE"
echo ""

# Check if release exists
if ! helm list -n "$RELEASE_NAMESPACE" | grep -q "$RELEASE_NAME"; then
  echo "⚠️  Helm release '$RELEASE_NAME' not found in namespace '$RELEASE_NAMESPACE'"
  echo "   Checking all namespaces..."
  helm list -A | grep "$RELEASE_NAME" || echo "   No release found with name '$RELEASE_NAME'"
  echo ""
else
  echo "Found Helm release: $RELEASE_NAME"
  echo ""
fi

# Uninstall Helm release
echo "=== Uninstalling Helm Release ==="
if helm uninstall "$RELEASE_NAME" -n "$RELEASE_NAMESPACE" 2>/dev/null; then
  echo "✅ Helm release uninstalled successfully"
else
  echo "⚠️  Helm release may not exist or already uninstalled"
fi

echo ""

if [[ "$CLEAN_ALL" == "true" ]]; then
  echo "=== Cleaning Up Resources ==="
  echo "⚠️  WARNING: This will delete operator subscriptions, operatorgroups, and namespaces!"
  echo "   This may affect other installations using the same namespaces."
  echo ""
  read -p "Continue with full cleanup? (yes/no): " -r
  if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
  fi

  # List of operator namespaces and resources
  declare -A OPERATORS=(
    ["openshift-operators"]="pipelines-og:openshift-pipelines-operator rhtas-og:trusted-artifact-signer-operator"
    ["rhacs-operator"]="acs-og:rhacs-operator"
    ["redhat-ods-operator"]="ai-og:rhods-operator"
    ["openshift-cnv"]="virtualization-og:kubevirt-hyperconverged"
    ["rhdh-operator"]="developer-hub-og:rhdh"
    ["openshift-gitops-operator"]="openshift-gitops-operator:openshift-gitops-operator"
  )

  echo ""
  echo "Deleting Subscriptions..."
  for NS in "${!OPERATORS[@]}"; do
    RESOURCES="${OPERATORS[$NS]}"
    for RESOURCE in $RESOURCES; do
      SUB_NAME="${RESOURCE##*:}"
      if oc get subscription "$SUB_NAME" -n "$NS" &>/dev/null; then
        echo "  Deleting subscription $SUB_NAME in $NS"
        oc delete subscription "$SUB_NAME" -n "$NS" --ignore-not-found=true
      fi
    done
  done

  echo ""
  echo "Deleting OperatorGroups..."
  for NS in "${!OPERATORS[@]}"; do
    RESOURCES="${OPERATORS[$NS]}"
    for RESOURCE in $RESOURCES; do
      OG_NAME="${RESOURCE%%:*}"
      if oc get operatorgroup "$OG_NAME" -n "$NS" &>/dev/null; then
        echo "  Deleting operatorgroup $OG_NAME in $NS"
        oc delete operatorgroup "$OG_NAME" -n "$NS" --ignore-not-found=true
      fi
    done
  done

  echo ""
  echo "Waiting for operators to be removed (this may take a few minutes)..."
  sleep 10

  echo ""
  echo "Deleting Namespaces (if empty or safe to delete)..."
  echo "⚠️  Note: Some namespaces like 'openshift-operators' are system namespaces"
  echo "   and should NOT be deleted. Only operator-specific namespaces will be deleted."
  
  # Only delete operator-specific namespaces, not openshift-operators
  for NS in "${!OPERATORS[@]}"; do
    if [[ "$NS" != "openshift-operators" ]]; then
      if oc get namespace "$NS" &>/dev/null; then
        echo "  Checking namespace $NS..."
        # Check if namespace has resources other than what we created
        RESOURCE_COUNT=$(oc get all -n "$NS" 2>/dev/null | wc -l || echo "0")
        if [[ "$RESOURCE_COUNT" -le 1 ]]; then
          echo "    Deleting namespace $NS"
          oc delete namespace "$NS" --ignore-not-found=true --timeout=60s || echo "    ⚠️  Could not delete $NS (may have resources)"
        else
          echo "    ⚠️  Namespace $NS has resources, skipping deletion"
        fi
      fi
    fi
  done

  echo ""
  echo "✅ Cleanup completed"
else
  echo "=== Cleanup Options ==="
  echo "To remove operator resources (subscriptions, operatorgroups), run:"
  echo "  ./uninstall.sh --clean-all"
  echo ""
  echo "Or manually delete resources:"
  echo "  oc delete subscription <name> -n <namespace>"
  echo "  oc delete operatorgroup <name> -n <namespace>"
fi

echo ""
echo "=== Verification ==="
echo "Checking remaining Helm releases:"
helm list -A | grep -E "NAME|$RELEASE_NAME" || echo "No releases found"

echo ""
echo "Checking operator subscriptions:"
oc get subscription -A 2>/dev/null | head -10 || echo "No subscriptions found"

echo ""
echo "✅ Uninstall process completed"
echo ""
echo "Note: Operators installed via OLM may continue running until their"
echo "      ClusterServiceVersions (CSVs) are removed. To fully remove operators:"
echo "      oc delete csv <csv-name> -n <namespace>"

