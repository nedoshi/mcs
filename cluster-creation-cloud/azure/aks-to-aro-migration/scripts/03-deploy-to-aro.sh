#!/bin/bash
set -e

# AKS to ARO Migration - Deploy to ARO
# This script deploys converted manifests to ARO cluster

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check required environment variables
required_vars=("ARO_CLUSTER_NAME" "ARO_RESOURCE_GROUP" "ARO_NAMESPACE")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "Required environment variable not set: $var"
        echo "Set required variables:"
        echo "  export ARO_CLUSTER_NAME=\"your-aro-cluster\""
        echo "  export ARO_RESOURCE_GROUP=\"your-resource-group\""
        echo "  export ARO_NAMESPACE=\"your-namespace\""
        exit 1
    fi
done

# Get ARO credentials
print_step "Retrieving ARO cluster credentials..."
ARO_API_URL=$(az aro show \
    --resource-group "$ARO_RESOURCE_GROUP" \
    --name "$ARO_CLUSTER_NAME" \
    --query "apiserverProfile.url" -o tsv)

ARO_ADMIN_USER=$(az aro list-credentials \
    --resource-group "$ARO_RESOURCE_GROUP" \
    --name "$ARO_CLUSTER_NAME" \
    --query "kubeadminUsername" -o tsv)

ARO_ADMIN_PASSWORD=$(az aro list-credentials \
    --resource-group "$ARO_RESOURCE_GROUP" \
    --name "$ARO_CLUSTER_NAME" \
    --query "kubeadminPassword" -o tsv)

print_info "ARO API URL: $ARO_API_URL"

# Login to ARO
print_step "Logging into ARO cluster..."
oc login "$ARO_API_URL" -u "$ARO_ADMIN_USER" -p "$ARO_ADMIN_PASSWORD" --insecure-skip-tls-verify

# Verify connection
if ! oc get nodes > /dev/null 2>&1; then
    print_error "Failed to connect to ARO cluster"
    exit 1
fi
print_info "Successfully connected to ARO cluster"

# Show cluster info
print_info "Cluster version: $(oc get clusterversion -o jsonpath='{.items[0].status.desired.version}')"
print_info "Nodes: $(oc get nodes --no-headers | wc -l)"

# Create or verify namespace
print_step "Setting up namespace: $ARO_NAMESPACE"
if oc get project "$ARO_NAMESPACE" > /dev/null 2>&1; then
    print_info "Namespace $ARO_NAMESPACE already exists"
    oc project "$ARO_NAMESPACE"
else
    print_info "Creating namespace: $ARO_NAMESPACE"
    oc new-project "$ARO_NAMESPACE"
fi

# Deployment manifest directory
MANIFEST_DIR="${ARO_MANIFEST_DIR:-./manifests/aro}"
if [ ! -d "$MANIFEST_DIR" ]; then
    print_error "Manifest directory not found: $MANIFEST_DIR"
    print_info "Set ARO_MANIFEST_DIR or use default ./manifests/aro"
    exit 1
fi

print_info "Using manifest directory: $MANIFEST_DIR"

# Function to wait for deployment
wait_for_deployment() {
    local deployment=$1
    local namespace=$2
    local timeout=${3:-300}

    print_info "Waiting for deployment $deployment to be ready (timeout: ${timeout}s)..."

    if oc rollout status deployment/"$deployment" -n "$namespace" --timeout="${timeout}s"; then
        print_info "Deployment $deployment is ready"
        return 0
    else
        print_error "Deployment $deployment failed to become ready"
        return 1
    fi
}

# Deploy in order
print_step "Starting deployment to ARO..."

# 1. Service Account
print_info "1. Deploying Service Account..."
if [ -f "$MANIFEST_DIR/serviceaccount.yaml" ]; then
    oc apply -f "$MANIFEST_DIR/serviceaccount.yaml" -n "$ARO_NAMESPACE"
else
    print_warn "No serviceaccount.yaml found, skipping"
fi

# 2. Security Context Constraints (cluster-scoped)
print_info "2. Applying Security Context Constraints..."
if [ -f "$MANIFEST_DIR/scc.yaml" ]; then
    oc apply -f "$MANIFEST_DIR/scc.yaml"
    # Grant SCC to service account
    SCC_NAME=$(yq eval '.metadata.name' "$MANIFEST_DIR/scc.yaml" 2>/dev/null || echo "custom-app-scc")
    SA_NAME=$(yq eval '.metadata.name' "$MANIFEST_DIR/serviceaccount.yaml" 2>/dev/null || echo "sample-app-sa")
    oc adm policy add-scc-to-user "$SCC_NAME" -z "$SA_NAME" -n "$ARO_NAMESPACE" || true
else
    print_warn "No scc.yaml found, using default restricted SCC"
fi

# 3. ConfigMaps
print_info "3. Deploying ConfigMaps..."
if [ -f "$MANIFEST_DIR/configmap.yaml" ]; then
    oc apply -f "$MANIFEST_DIR/configmap.yaml" -n "$ARO_NAMESPACE"
else
    print_warn "No configmap.yaml found, skipping"
fi

# 4. Secrets or SecretProviderClass
print_info "4. Deploying Secrets..."
if [ -f "$MANIFEST_DIR/secretproviderclass.yaml" ]; then
    print_info "Using Azure Key Vault CSI SecretProviderClass"
    oc apply -f "$MANIFEST_DIR/secretproviderclass.yaml" -n "$ARO_NAMESPACE"
elif [ -f "$MANIFEST_DIR/secrets.yaml" ]; then
    print_warn "Deploying secrets from file (ensure this is secure)"
    oc apply -f "$MANIFEST_DIR/secrets.yaml" -n "$ARO_NAMESPACE"
else
    print_warn "No secrets or secretproviderclass found, you may need to create secrets manually"
fi

# 5. ACR Pull Secret (if needed)
if [ -n "$ACR_NAME" ] && [ -n "$ACR_SP_APP_ID" ] && [ -n "$ACR_SP_PASSWORD" ]; then
    print_info "5. Creating ACR pull secret..."
    ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"

    oc create secret docker-registry acr-pull-secret \
        --docker-server="$ACR_LOGIN_SERVER" \
        --docker-username="$ACR_SP_APP_ID" \
        --docker-password="$ACR_SP_PASSWORD" \
        --namespace="$ARO_NAMESPACE" \
        --dry-run=client -o yaml | oc apply -f -

    # Link to service account
    SA_NAME=$(yq eval '.metadata.name' "$MANIFEST_DIR/serviceaccount.yaml" 2>/dev/null || echo "default")
    oc secrets link "$SA_NAME" acr-pull-secret --for=pull -n "$ARO_NAMESPACE" || true
else
    print_warn "5. ACR credentials not provided, skipping pull secret creation"
    print_info "Set ACR_NAME, ACR_SP_APP_ID, ACR_SP_PASSWORD to create pull secret"
fi

# 6. Services
print_info "6. Deploying Services..."
if [ -f "$MANIFEST_DIR/service.yaml" ]; then
    oc apply -f "$MANIFEST_DIR/service.yaml" -n "$ARO_NAMESPACE"
else
    print_warn "No service.yaml found, skipping"
fi

# 7. Deployments
print_info "7. Deploying Applications..."
if [ -f "$MANIFEST_DIR/deployment.yaml" ]; then
    oc apply -f "$MANIFEST_DIR/deployment.yaml" -n "$ARO_NAMESPACE"

    # Get deployment name
    DEPLOYMENT_NAME=$(yq eval '.metadata.name' "$MANIFEST_DIR/deployment.yaml" 2>/dev/null || echo "sample-app")

    # Wait for deployment to be ready
    wait_for_deployment "$DEPLOYMENT_NAME" "$ARO_NAMESPACE" 300
else
    print_error "No deployment.yaml found!"
    exit 1
fi

# 8. Routes
print_info "8. Creating Routes..."
if [ -f "$MANIFEST_DIR/route.yaml" ]; then
    oc apply -f "$MANIFEST_DIR/route.yaml" -n "$ARO_NAMESPACE"

    # Get route URL
    ROUTE_NAME=$(yq eval '.metadata.name' "$MANIFEST_DIR/route.yaml" 2>/dev/null || echo "sample-app")
    ROUTE_HOST=$(oc get route "$ROUTE_NAME" -n "$ARO_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

    if [ -n "$ROUTE_HOST" ]; then
        print_info "Route created: https://$ROUTE_HOST"
    fi
else
    print_warn "No route.yaml found, skipping"
fi

# 9. Additional resources (HPA, PDB, etc.)
if [ -f "$MANIFEST_DIR/hpa.yaml" ]; then
    print_info "9. Deploying Horizontal Pod Autoscaler..."
    oc apply -f "$MANIFEST_DIR/hpa.yaml" -n "$ARO_NAMESPACE"
fi

# Deployment summary
print_step "Deployment Summary"
echo "===================="

print_info "Pods:"
oc get pods -n "$ARO_NAMESPACE" -o wide

print_info "Services:"
oc get svc -n "$ARO_NAMESPACE"

print_info "Routes:"
oc get routes -n "$ARO_NAMESPACE"

print_info "Deployments:"
oc get deployments -n "$ARO_NAMESPACE"

# Check pod status
READY_PODS=$(oc get pods -n "$ARO_NAMESPACE" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
TOTAL_PODS=$(oc get pods -n "$ARO_NAMESPACE" --no-headers 2>/dev/null | wc -l)

echo ""
print_info "Pod Status: $READY_PODS/$TOTAL_PODS running"

# Show recent events
print_info "Recent Events:"
oc get events -n "$ARO_NAMESPACE" --sort-by='.lastTimestamp' | tail -10

# Check for errors
ERROR_PODS=$(oc get pods -n "$ARO_NAMESPACE" --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)

if [ "$ERROR_PODS" -gt 0 ]; then
    print_warn "Found $ERROR_PODS pod(s) not in Running state"
    print_info "Check pod logs with: oc logs <pod-name> -n $ARO_NAMESPACE"
    print_info "Describe pod with: oc describe pod <pod-name> -n $ARO_NAMESPACE"
fi

# Final status
echo ""
if [ "$READY_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
    print_info "✅ Deployment completed successfully!"
else
    print_warn "⚠️  Deployment completed with warnings. Please review pod status."
fi

# Next steps
echo ""
print_step "Next Steps"
echo "==========="
echo "1. Verify application health:"
echo "   oc logs deployment/$DEPLOYMENT_NAME -n $ARO_NAMESPACE"
echo ""
echo "2. Test application endpoint:"
echo "   curl -k https://$ROUTE_HOST/health"
echo ""
echo "3. Monitor pods:"
echo "   watch oc get pods -n $ARO_NAMESPACE"
echo ""
echo "4. Run validation script:"
echo "   ./scripts/04-validate-deployment.sh"
