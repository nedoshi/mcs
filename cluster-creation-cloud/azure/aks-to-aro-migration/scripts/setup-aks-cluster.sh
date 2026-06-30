#!/bin/bash
set -e

# AKS Cluster Setup Script for Beginners
# This script automates the creation of an AKS cluster for migration testing

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${CYAN}[✓]${NC} $1"; }

# ASCII Banner
cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║         AKS Cluster Setup for Migration Testing          ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF

echo ""

# Check prerequisites
print_step "Checking prerequisites..."

# Check Azure CLI
if ! command -v az &> /dev/null; then
    print_error "Azure CLI not found. Please install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi
print_success "Azure CLI found: $(az version --query '\"azure-cli\"' -o tsv)"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi
print_success "kubectl found: $(kubectl version --client --short 2>/dev/null | head -1)"

# Check Azure login
print_info "Checking Azure login status..."
if ! az account show &> /dev/null; then
    print_warn "Not logged into Azure. Running 'az login'..."
    az login
fi

CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv)
print_success "Logged into Azure subscription: $CURRENT_SUBSCRIPTION"

echo ""
print_step "Configuration"
echo "=============="

# Get or set variables
RESOURCE_GROUP="${RESOURCE_GROUP:-aks-demo-rg}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-demo-cluster}"
LOCATION="${LOCATION:-eastus}"
ACR_NAME="${ACR_NAME:-aksdemoregistry${RANDOM}}"
NODE_COUNT="${NODE_COUNT:-3}"
NODE_SIZE="${NODE_SIZE:-Standard_D2s_v3}"

echo "Resource Group:    $RESOURCE_GROUP"
echo "Cluster Name:      $AKS_CLUSTER_NAME"
echo "Location:          $LOCATION"
echo "ACR Name:          $ACR_NAME"
echo "Node Count:        $NODE_COUNT"
echo "Node VM Size:      $NODE_SIZE"
echo ""

# Confirm
read -p "Continue with these settings? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" && "$CONFIRM" != "y" ]]; then
    print_info "Setup cancelled. You can set custom values:"
    echo "  export RESOURCE_GROUP=\"my-rg\""
    echo "  export AKS_CLUSTER_NAME=\"my-cluster\""
    echo "  export LOCATION=\"westus2\""
    echo "  ./scripts/setup-aks-cluster.sh"
    exit 0
fi

echo ""

# Step 1: Create Resource Group
print_step "Step 1: Creating Resource Group"
if az group show --name $RESOURCE_GROUP &> /dev/null; then
    print_warn "Resource group $RESOURCE_GROUP already exists, using existing"
else
    az group create \
        --name $RESOURCE_GROUP \
        --location $LOCATION \
        --output none
    print_success "Resource group created: $RESOURCE_GROUP"
fi

echo ""

# Step 2: Create AKS Cluster
print_step "Step 2: Creating AKS Cluster (this takes 5-10 minutes)"
print_info "Cluster name: $AKS_CLUSTER_NAME"

if az aks show --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME &> /dev/null; then
    print_warn "AKS cluster $AKS_CLUSTER_NAME already exists, skipping creation"
else
    print_info "Creating cluster with $NODE_COUNT x $NODE_SIZE nodes..."

    az aks create \
        --resource-group $RESOURCE_GROUP \
        --name $AKS_CLUSTER_NAME \
        --node-count $NODE_COUNT \
        --node-vm-size $NODE_SIZE \
        --enable-managed-identity \
        --generate-ssh-keys \
        --network-plugin azure \
        --location $LOCATION \
        --output none

    print_success "AKS cluster created: $AKS_CLUSTER_NAME"
fi

echo ""

# Step 3: Get Credentials
print_step "Step 3: Getting Cluster Credentials"

az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --overwrite-existing \
    --output none

print_success "Credentials downloaded"

# Verify connection
print_info "Verifying cluster connection..."
kubectl get nodes

NODE_COUNT_ACTUAL=$(kubectl get nodes --no-headers | wc -l | xargs)
print_success "Connected to cluster with $NODE_COUNT_ACTUAL nodes"

echo ""

# Step 4: Create ACR
print_step "Step 4: Creating Azure Container Registry"

if az acr show --name $ACR_NAME &> /dev/null 2>&1; then
    print_warn "ACR $ACR_NAME already exists, using existing"
else
    az acr create \
        --resource-group $RESOURCE_GROUP \
        --name $ACR_NAME \
        --sku Basic \
        --location $LOCATION \
        --output none

    print_success "ACR created: $ACR_NAME"
fi

# Enable admin (for easy testing)
az acr update \
    --name $ACR_NAME \
    --admin-enabled true \
    --output none

ACR_LOGIN_SERVER=$(az acr show \
    --name $ACR_NAME \
    --query loginServer \
    --output tsv)

print_success "ACR login server: $ACR_LOGIN_SERVER"

echo ""

# Step 5: Attach ACR to AKS
print_step "Step 5: Attaching ACR to AKS"

az aks update \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --attach-acr $ACR_NAME \
    --output none

print_success "ACR attached to AKS"

# Verify
print_info "Verifying ACR access..."
if az aks check-acr \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --acr ${ACR_LOGIN_SERVER} &> /dev/null; then
    print_success "ACR access verified"
else
    print_warn "ACR access verification inconclusive (this is often fine)"
fi

echo ""

# Step 6: Deploy Sample Application
print_step "Step 6: Deploying Sample Application"

# Create namespace
kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
print_success "Namespace 'production' created"

# Deploy NGINX demo app
print_info "Deploying NGINX demo application..."

kubectl create deployment nginx-demo \
    --image=nginxdemos/hello:latest \
    --replicas=3 \
    --namespace=production \
    --dry-run=client -o yaml | kubectl apply -f -

print_success "Deployment created"

# Expose as LoadBalancer
kubectl expose deployment nginx-demo \
    --port=80 \
    --target-port=80 \
    --type=LoadBalancer \
    --namespace=production \
    --dry-run=client -o yaml | kubectl apply -f -

print_success "Service created (LoadBalancer)"

# Wait for pods
print_info "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod \
    -l app=nginx-demo \
    -n production \
    --timeout=120s || print_warn "Timeout waiting for pods (they may still be starting)"

# Wait for LoadBalancer IP
print_info "Waiting for LoadBalancer IP (this may take 1-2 minutes)..."
COUNTER=0
MAX_WAIT=60
while [ $COUNTER -lt $MAX_WAIT ]; do
    EXTERNAL_IP=$(kubectl get service nginx-demo -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -n "$EXTERNAL_IP" ]; then
        break
    fi
    sleep 2
    COUNTER=$((COUNTER + 1))
    echo -n "."
done
echo ""

if [ -n "$EXTERNAL_IP" ]; then
    print_success "LoadBalancer IP assigned: $EXTERNAL_IP"
else
    print_warn "LoadBalancer IP not assigned yet. Check with: kubectl get svc -n production"
fi

echo ""

# Step 7: Save Environment
print_step "Step 7: Saving Environment Variables"

ENV_FILE="aks-environment.sh"
cat > $ENV_FILE << EOF
# AKS Environment Variables
# Load with: source $ENV_FILE

export SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export RESOURCE_GROUP="$RESOURCE_GROUP"
export AKS_CLUSTER_NAME="$AKS_CLUSTER_NAME"
export LOCATION="$LOCATION"
export ACR_NAME="$ACR_NAME"
export ACR_LOGIN_SERVER="$ACR_LOGIN_SERVER"
export AKS_NAMESPACE="production"

# For migration scripts
export APP_NAME="nginx-demo"

echo "AKS environment loaded:"
echo "  Cluster: \$AKS_CLUSTER_NAME"
echo "  ACR: \$ACR_LOGIN_SERVER"
echo "  Namespace: \$AKS_NAMESPACE"
EOF

print_success "Environment saved to: $ENV_FILE"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║                    SETUP COMPLETE! ✓                      ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

print_info "Your AKS cluster is ready!"
echo ""
echo "📋 Cluster Information:"
echo "   Resource Group:  $RESOURCE_GROUP"
echo "   Cluster Name:    $AKS_CLUSTER_NAME"
echo "   ACR:             $ACR_LOGIN_SERVER"
echo "   Namespace:       production"
if [ -n "$EXTERNAL_IP" ]; then
    echo "   Application URL: http://$EXTERNAL_IP"
fi
echo ""

print_info "Quick Commands:"
echo ""
echo "  # View cluster resources"
echo "  kubectl get all -n production"
echo ""
echo "  # View application"
if [ -n "$EXTERNAL_IP" ]; then
    echo "  curl http://$EXTERNAL_IP"
fi
echo "  kubectl port-forward service/nginx-demo 8080:80 -n production"
echo "  # Then open: http://localhost:8080"
echo ""
echo "  # Load environment variables"
echo "  source $ENV_FILE"
echo ""
echo "  # Start migration to ARO"
echo "  ./scripts/01-export-aks-resources.sh"
echo ""

print_info "Next Steps:"
echo "  1. Test your application (see commands above)"
echo "  2. Review docs/00-AKS-SETUP-GUIDE.md for more details"
echo "  3. When ready, follow QUICK-START.md to migrate to ARO"
echo ""

print_info "To clean up later:"
echo "  az group delete --name $RESOURCE_GROUP --yes --no-wait"
echo ""

# Test application if IP is available
if [ -n "$EXTERNAL_IP" ]; then
    print_info "Testing application..."
    sleep 5  # Give it a moment to be ready

    if HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$EXTERNAL_IP --max-time 10 2>/dev/null); then
        if [ "$HTTP_CODE" == "200" ]; then
            print_success "Application is responding! ✓"
            echo ""
            echo "🎉 You can now access your application at: http://$EXTERNAL_IP"
        else
            print_warn "Application returned HTTP $HTTP_CODE (it may still be starting)"
        fi
    else
        print_warn "Could not connect to application yet (it may still be starting)"
    fi
fi

echo ""
print_success "Setup script completed successfully!"
