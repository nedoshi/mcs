# AKS Environment Variables
# Load with: source aks-environment.sh

export SUBSCRIPTION_ID="c5545383-1a94-45fe-b501-7ebdf43e5d7a"
export RESOURCE_GROUP="aks-demo-rg"
export AKS_CLUSTER_NAME="aks-demo-cluster"
export LOCATION="eastus"
export ACR_NAME="aksdemoregistry27132"
export ACR_LOGIN_SERVER="aksdemoregistry27132.azurecr.io"
export AKS_NAMESPACE="production"

# For migration scripts
export APP_NAME="nginx-demo"

echo "AKS environment loaded:"
echo "  Cluster: $AKS_CLUSTER_NAME"
echo "  ACR: $ACR_LOGIN_SERVER"
echo "  Namespace: $AKS_NAMESPACE"
