#!/bin/bash
set -e

# AKS to ARO Migration - Export AKS Resources
# This script exports Kubernetes resources from AKS for migration to ARO

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check required environment variables
if [ -z "$AKS_CLUSTER_NAME" ] || [ -z "$AKS_RESOURCE_GROUP" ] || [ -z "$AKS_NAMESPACE" ]; then
    print_error "Required environment variables not set:"
    echo "  export AKS_CLUSTER_NAME=\"your-aks-cluster\""
    echo "  export AKS_RESOURCE_GROUP=\"your-resource-group\""
    echo "  export AKS_NAMESPACE=\"your-namespace\""
    exit 1
fi

# Create export directory
EXPORT_DIR="${MIGRATION_DIR:-./migration}/exports/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EXPORT_DIR"
print_info "Export directory: $EXPORT_DIR"

# Get AKS credentials
print_info "Getting AKS credentials..."
az aks get-credentials \
    --resource-group "$AKS_RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --admin \
    --overwrite-existing

# Switch to AKS context
kubectl config use-context "${AKS_CLUSTER_NAME}-admin"

# Verify connection
print_info "Verifying AKS connection..."
if ! kubectl get nodes > /dev/null 2>&1; then
    print_error "Failed to connect to AKS cluster"
    exit 1
fi
print_info "Connected to AKS cluster: $AKS_CLUSTER_NAME"

# Export deployments
print_info "Exporting deployments..."
kubectl get deployments -n "$AKS_NAMESPACE" -o yaml > "$EXPORT_DIR/deployments.yaml"
kubectl get deployments -n "$AKS_NAMESPACE" -o json | \
    jq -r '.items[] | .metadata.name' > "$EXPORT_DIR/deployment-list.txt"
print_info "Exported $(wc -l < "$EXPORT_DIR/deployment-list.txt") deployments"

# Export services
print_info "Exporting services..."
kubectl get services -n "$AKS_NAMESPACE" -o yaml > "$EXPORT_DIR/services.yaml"
kubectl get services -n "$AKS_NAMESPACE" -o json | \
    jq -r '.items[] | .metadata.name' > "$EXPORT_DIR/service-list.txt"
print_info "Exported $(wc -l < "$EXPORT_DIR/service-list.txt") services"

# Export ingresses
print_info "Exporting ingresses..."
kubectl get ingress -n "$AKS_NAMESPACE" -o yaml > "$EXPORT_DIR/ingresses.yaml" 2>/dev/null || \
    print_warn "No ingresses found or ingress API not available"

# Export configmaps
print_info "Exporting configmaps..."
kubectl get configmaps -n "$AKS_NAMESPACE" -o yaml > "$EXPORT_DIR/configmaps.yaml"
# Exclude default configmaps
kubectl get configmaps -n "$AKS_NAMESPACE" -o json | \
    jq -r '.items[] | select(.metadata.name | startswith("kube-") | not) | .metadata.name' > "$EXPORT_DIR/configmap-list.txt"
print_info "Exported $(wc -l < "$EXPORT_DIR/configmap-list.txt") configmaps (excluding system configmaps)"

# Export secrets (WARNING: sensitive data)
print_info "Exporting secrets..."
kubectl get secrets -n "$AKS_NAMESPACE" -o yaml > "$EXPORT_DIR/secrets.yaml"
# Exclude default secrets
kubectl get secrets -n "$AKS_NAMESPACE" -o json | \
    jq -r '.items[] | select(.type != "kubernetes.io/service-account-token") | .metadata.name' > "$EXPORT_DIR/secret-list.txt"
print_warn "Secrets exported. Handle with care - contains sensitive data!"
print_info "Exported $(wc -l < "$EXPORT_DIR/secret-list.txt") secrets (excluding service account tokens)"

# Export persistent volume claims
print_info "Exporting persistent volume claims..."
kubectl get pvc -n "$AKS_NAMESPACE" -o yaml > "$EXPORT_DIR/pvcs.yaml" 2>/dev/null || \
    print_warn "No PVCs found"

# Export service accounts
print_info "Exporting service accounts..."
kubectl get serviceaccounts -n "$AKS_NAMESPACE" -o yaml > "$EXPORT_DIR/serviceaccounts.yaml"
kubectl get serviceaccounts -n "$AKS_NAMESPACE" -o json | \
    jq -r '.items[] | select(.metadata.name != "default") | .metadata.name' > "$EXPORT_DIR/serviceaccount-list.txt"

# Export network policies (if any)
print_info "Exporting network policies..."
kubectl get networkpolicies -n "$AKS_NAMESPACE" -o yaml > "$EXPORT_DIR/networkpolicies.yaml" 2>/dev/null || \
    print_warn "No network policies found"

# Export horizontal pod autoscalers
print_info "Exporting horizontal pod autoscalers..."
kubectl get hpa -n "$AKS_NAMESPACE" -o yaml > "$EXPORT_DIR/hpa.yaml" 2>/dev/null || \
    print_warn "No HPAs found"

# Export pod disruption budgets
print_info "Exporting pod disruption budgets..."
kubectl get pdb -n "$AKS_NAMESPACE" -o yaml > "$EXPORT_DIR/pdb.yaml" 2>/dev/null || \
    print_warn "No PDBs found"

# Document current state
print_info "Documenting current application state..."
cat > "$EXPORT_DIR/current-state.txt" << EOF
AKS Cluster Export Report
=========================
Date: $(date)
AKS Cluster: $AKS_CLUSTER_NAME
Resource Group: $AKS_RESOURCE_GROUP
Namespace: $AKS_NAMESPACE

Cluster Version:
$(kubectl version --short 2>/dev/null || kubectl version)

Nodes:
$(kubectl get nodes -o wide)

Deployments:
$(kubectl get deployments -n "$AKS_NAMESPACE" -o wide)

Replica Counts:
$(kubectl get deployments -n "$AKS_NAMESPACE" -o json | jq -r '.items[] | "\(.metadata.name): \(.spec.replicas) replicas, \(.status.readyReplicas // 0) ready"')

Container Images:
$(kubectl get deployments -n "$AKS_NAMESPACE" -o json | jq -r '.items[] | "\(.metadata.name): \(.spec.template.spec.containers[0].image)"')

Services and Endpoints:
$(kubectl get svc,endpoints -n "$AKS_NAMESPACE" -o wide)

Ingresses:
$(kubectl get ingress -n "$AKS_NAMESPACE" -o wide 2>/dev/null || echo "No ingresses found")

Resource Usage:
$(kubectl top pods -n "$AKS_NAMESPACE" 2>/dev/null || echo "Metrics not available")

Events (last 1 hour):
$(kubectl get events -n "$AKS_NAMESPACE" --sort-by='.lastTimestamp' --field-selector involvedObject.kind!=Pod | tail -20)
EOF

print_info "Current state documented in: $EXPORT_DIR/current-state.txt"

# Create summary
DEPLOYMENT_COUNT=$(wc -l < "$EXPORT_DIR/deployment-list.txt")
SERVICE_COUNT=$(wc -l < "$EXPORT_DIR/service-list.txt")
CONFIGMAP_COUNT=$(wc -l < "$EXPORT_DIR/configmap-list.txt")
SECRET_COUNT=$(wc -l < "$EXPORT_DIR/secret-list.txt")

cat > "$EXPORT_DIR/export-summary.txt" << EOF
AKS Resource Export Summary
===========================
Export Date: $(date)
Export Directory: $EXPORT_DIR

Resources Exported:
  - Deployments: $DEPLOYMENT_COUNT
  - Services: $SERVICE_COUNT
  - ConfigMaps: $CONFIGMAP_COUNT
  - Secrets: $SECRET_COUNT
  - Ingresses: $([ -f "$EXPORT_DIR/ingresses.yaml" ] && echo "Yes" || echo "No")
  - PVCs: $([ -f "$EXPORT_DIR/pvcs.yaml" ] && echo "Yes" || echo "No")

Files Created:
$(ls -lh "$EXPORT_DIR" | tail -n +2)

Next Steps:
1. Review exported manifests in: $EXPORT_DIR
2. Run conversion script: ./scripts/02-convert-manifests.sh
3. Secure and backup secrets: $EXPORT_DIR/secrets.yaml
EOF

cat "$EXPORT_DIR/export-summary.txt"

print_info "Export completed successfully!"
print_info "Export location: $EXPORT_DIR"
print_warn "Remember to secure secrets.yaml - it contains sensitive data!"

# Set environment variable for next script
export AKS_EXPORT_DIR="$EXPORT_DIR"
echo "export AKS_EXPORT_DIR=\"$EXPORT_DIR\"" > "$EXPORT_DIR/../latest-export.env"
