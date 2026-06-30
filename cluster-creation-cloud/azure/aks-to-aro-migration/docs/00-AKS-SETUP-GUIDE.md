# AKS Cluster Setup Guide for Beginners

This guide will help you create an Azure Kubernetes Service (AKS) cluster and deploy the sample application. Perfect for testing the AKS to ARO migration workflow.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start (5 Minutes)](#quick-start-5-minutes)
- [Step-by-Step Setup](#step-by-step-setup)
- [Deploy Sample Application](#deploy-sample-application)
- [Verify Deployment](#verify-deployment)
- [Clean Up](#clean-up)

---

## Prerequisites

### Required Tools

Install these tools before starting:

```bash
# Check if Azure CLI is installed
az --version

# If not installed:
# macOS:
brew install azure-cli

# Windows:
# Download from: https://aka.ms/installazurecliwindows

# Linux:
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

```bash
# Install kubectl (Kubernetes CLI)
# macOS:
brew install kubectl

# Windows:
choco install kubernetes-cli

# Linux:
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify installation
kubectl version --client
```

### Azure Account

```bash
# Login to Azure
az login

# Set your subscription (if you have multiple)
az account list --output table
az account set --subscription "<your-subscription-id>"

# Verify
az account show
```

---

## Quick Start (5 Minutes)

Use this automated script to create everything:

```bash
# Set your preferences
export RESOURCE_GROUP="aks-demo-rg"
export AKS_CLUSTER_NAME="aks-demo-cluster"
export LOCATION="eastus"
export ACR_NAME="aksdemoregistry${RANDOM}"  # Must be globally unique

# Run the quick setup script
cd aks-to-aro-migration
./scripts/setup-aks-cluster.sh
```

The script will:
1. Create resource group
2. Create AKS cluster (3 nodes)
3. Create Azure Container Registry
4. Attach ACR to AKS
5. Get credentials
6. Deploy sample application

**Skip to [Verify Deployment](#verify-deployment) after the script completes.**

---

## Step-by-Step Setup

If you prefer to understand each step, follow this detailed guide.

### Step 1: Create Resource Group

```bash
# Set variables
export RESOURCE_GROUP="aks-demo-rg"
export LOCATION="eastus"  # Choose: eastus, westus2, westeurope, etc.

# Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Verify
az group show --name $RESOURCE_GROUP
```

**Expected output**: Resource group created successfully

---

### Step 2: Create AKS Cluster

```bash
# Set cluster name
export AKS_CLUSTER_NAME="aks-demo-cluster"

# Create AKS cluster (takes 5-10 minutes)
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --node-count 3 \
  --node-vm-size Standard_D2s_v3 \
  --enable-managed-identity \
  --generate-ssh-keys \
  --network-plugin azure \
  --location $LOCATION

# This creates:
# - 3 worker nodes
# - Standard_D2s_v3 VMs (2 vCPU, 8GB RAM each)
# - Managed identity for authentication
# - Azure CNI networking
```

**Wait for completion** (approximately 5-10 minutes). You'll see a JSON output when complete.

---

### Step 3: Get AKS Credentials

```bash
# Download kubectl credentials
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --overwrite-existing

# Verify connection
kubectl get nodes

# Expected output: 3 nodes in "Ready" status
```

**Expected output:**
```
NAME                                STATUS   ROLES   AGE   VERSION
aks-nodepool1-12345678-vmss000000   Ready    agent   5m    v1.28.3
aks-nodepool1-12345678-vmss000001   Ready    agent   5m    v1.28.3
aks-nodepool1-12345678-vmss000002   Ready    agent   5m    v1.28.3
```

---

### Step 4: Create Azure Container Registry (ACR)

```bash
# Set ACR name (must be globally unique, lowercase, no hyphens)
export ACR_NAME="aksdemoregistry${RANDOM}"

# Create ACR
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Basic \
  --location $LOCATION

# Enable admin access (for easy testing)
az acr update \
  --name $ACR_NAME \
  --admin-enabled true

# Get ACR login server
export ACR_LOGIN_SERVER=$(az acr show \
  --name $ACR_NAME \
  --query loginServer \
  --output tsv)

echo "ACR Login Server: $ACR_LOGIN_SERVER"
```

---

### Step 5: Attach ACR to AKS

This allows AKS to pull images from ACR without credentials:

```bash
# Attach ACR to AKS
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --attach-acr $ACR_NAME

# Verify attachment
az aks check-acr \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --acr ${ACR_LOGIN_SERVER}
```

**Expected output**: "Your cluster can pull images from..."

---

### Step 6: Create Azure Database for PostgreSQL (Optional)

For a complete setup with database:

```bash
# Set database variables
export DB_SERVER_NAME="aks-demo-db-${RANDOM}"
export DB_ADMIN_USER="dbadmin"
export DB_ADMIN_PASSWORD="YourSecurePassword123!"  # Change this!

# Create PostgreSQL Flexible Server
az postgres flexible-server create \
  --resource-group $RESOURCE_GROUP \
  --name $DB_SERVER_NAME \
  --location $LOCATION \
  --admin-user $DB_ADMIN_USER \
  --admin-password $DB_ADMIN_PASSWORD \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 32 \
  --version 15 \
  --public-access 0.0.0.0-255.255.255.255

# Get database FQDN
export DB_FQDN=$(az postgres flexible-server show \
  --resource-group $RESOURCE_GROUP \
  --name $DB_SERVER_NAME \
  --query fullyQualifiedDomainName \
  --output tsv)

echo "Database FQDN: $DB_FQDN"

# Create database
az postgres flexible-server db create \
  --resource-group $RESOURCE_GROUP \
  --server-name $DB_SERVER_NAME \
  --database-name appdb
```

---

## Deploy Sample Application

### Option 1: Deploy Using Sample Manifests (No Container Registry)

If you want to test with a public image first:

```bash
# Create namespace
kubectl create namespace production

# Deploy a simple NGINX application
kubectl create deployment nginx-demo \
  --image=nginx:latest \
  --replicas=3 \
  --namespace=production

# Expose as a service
kubectl expose deployment nginx-demo \
  --port=80 \
  --target-port=80 \
  --type=LoadBalancer \
  --namespace=production

# Wait for external IP (takes 1-2 minutes)
kubectl get service nginx-demo -n production --watch
# Press Ctrl+C when EXTERNAL-IP appears (not <pending>)

# Get the external IP
EXTERNAL_IP=$(kubectl get service nginx-demo -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Application available at: http://$EXTERNAL_IP"

# Test it
curl http://$EXTERNAL_IP
```

### Option 2: Deploy Using Our Sample Manifests

```bash
# Navigate to AKS manifests directory
cd aks-to-aro-migration/manifests/aks

# Create namespace
kubectl create namespace production

# Create ConfigMap
kubectl apply -f configmap.yaml -n production

# Create a secret for database credentials
kubectl create secret generic db-credentials \
  --from-literal=username=$DB_ADMIN_USER \
  --from-literal=password=$DB_ADMIN_PASSWORD \
  --namespace=production

# Note: You'll need to build and push your application image first
# For now, let's modify the deployment to use a public image

# Create a temporary deployment with public image
cat > deployment-demo.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: sample-app
        image: nginxdemos/hello:latest  # Public demo image
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
EOF

kubectl apply -f deployment-demo.yaml

# Apply service
kubectl apply -f service.yaml -n production

# Apply ingress (optional - requires ingress controller)
# kubectl apply -f ingress.yaml -n production
```

### Option 3: Build and Push Your Own Image to ACR

If you have a Dockerfile:

```bash
# Login to ACR
az acr login --name $ACR_NAME

# Tag your image
docker tag your-app:latest ${ACR_LOGIN_SERVER}/sample-app:v1.0.0

# Push to ACR
docker push ${ACR_LOGIN_SERVER}/sample-app:v1.0.0

# Update deployment.yaml with your ACR image
# Then deploy:
kubectl apply -f deployment.yaml -n production
kubectl apply -f service.yaml -n production
```

---

## Verify Deployment

### Check Pods

```bash
# View all pods in production namespace
kubectl get pods -n production

# Expected output: All pods in "Running" status
# NAME                          READY   STATUS    RESTARTS   AGE
# sample-app-7d5c4b9f8d-abc12   1/1     Running   0          2m
# sample-app-7d5c4b9f8d-def34   1/1     Running   0          2m
# sample-app-7d5c4b9f8d-ghi56   1/1     Running   0          2m

# Check pod details
kubectl describe pod <pod-name> -n production

# View pod logs
kubectl logs <pod-name> -n production
```

### Check Services

```bash
# View services
kubectl get services -n production

# Get service details
kubectl describe service sample-app -n production

# Check endpoints (should show pod IPs)
kubectl get endpoints sample-app -n production
```

### Check Deployments

```bash
# View deployments
kubectl get deployments -n production

# Check deployment status
kubectl rollout status deployment/sample-app -n production

# View deployment details
kubectl describe deployment sample-app -n production
```

### Access Application

#### If using LoadBalancer service:

```bash
# Get external IP
kubectl get service sample-app -n production

# Get the IP and test
EXTERNAL_IP=$(kubectl get service sample-app -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Application URL: http://$EXTERNAL_IP"

# Test with curl
curl http://$EXTERNAL_IP
```

#### If using ClusterIP (internal only):

```bash
# Port forward to local machine
kubectl port-forward service/sample-app 8080:80 -n production

# In another terminal or browser
curl http://localhost:8080
# Or open browser to: http://localhost:8080
```

---

## Troubleshooting

### Pods Not Starting

```bash
# Check pod events
kubectl get events -n production --sort-by='.lastTimestamp'

# Describe the pod
kubectl describe pod <pod-name> -n production

# Common issues:
# - ImagePullBackOff: Check image name and ACR access
# - CrashLoopBackOff: Check application logs
# - Pending: Check resource availability
```

### ImagePullBackOff Error

```bash
# Verify ACR is attached
az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "identity"

# Re-attach ACR
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --attach-acr $ACR_NAME
```

### Cannot Access Service

```bash
# Check if LoadBalancer got external IP
kubectl get service sample-app -n production

# Check Azure Load Balancer was created
az network lb list --resource-group MC_${RESOURCE_GROUP}_${AKS_CLUSTER_NAME}_${LOCATION}

# Check Network Security Group rules
az network nsg list --resource-group MC_${RESOURCE_GROUP}_${AKS_CLUSTER_NAME}_${LOCATION}
```

---

## Save Environment Variables

Save these for later use:

```bash
# Create environment file
cat > aks-environment.sh << EOF
# AKS Environment Variables
export RESOURCE_GROUP="$RESOURCE_GROUP"
export AKS_CLUSTER_NAME="$AKS_CLUSTER_NAME"
export LOCATION="$LOCATION"
export ACR_NAME="$ACR_NAME"
export ACR_LOGIN_SERVER="$ACR_LOGIN_SERVER"
export DB_SERVER_NAME="$DB_SERVER_NAME"
export DB_FQDN="$DB_FQDN"
export AKS_NAMESPACE="production"
EOF

echo "Environment saved to: aks-environment.sh"
echo "Load with: source aks-environment.sh"
```

---

## Next Steps

Now that you have a working AKS cluster:

1. **Test the Application**
   - Access via LoadBalancer IP
   - Check logs and metrics
   - Test database connectivity

2. **Prepare for Migration**
   - Review [Pre-Migration Checklist](01-PRE-MIGRATION-CHECKLIST.md)
   - Set up ARO cluster (see main README.md)
   - Run export script: `./scripts/01-export-aks-resources.sh`

3. **Start Migration**
   - Follow [QUICK-START.md](../QUICK-START.md) for express path
   - Or use [Migration Runbook](02-MIGRATION-RUNBOOK.md) for detailed steps

---

## Clean Up

When you're done testing:

### Delete Individual Resources

```bash
# Delete AKS cluster (keeps resource group)
az aks delete \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --yes --no-wait

# Delete ACR
az acr delete \
  --name $ACR_NAME \
  --yes

# Delete PostgreSQL
az postgres flexible-server delete \
  --resource-group $RESOURCE_GROUP \
  --name $DB_SERVER_NAME \
  --yes
```

### Delete Everything

```bash
# Delete entire resource group (deletes all resources)
az group delete \
  --name $RESOURCE_GROUP \
  --yes --no-wait

# Verify deletion (after a few minutes)
az group list --output table
```

---

## Quick Reference

### Common kubectl Commands

```bash
# View resources
kubectl get pods -n production
kubectl get services -n production
kubectl get deployments -n production
kubectl get all -n production

# Describe resources
kubectl describe pod <pod-name> -n production
kubectl describe service <service-name> -n production

# View logs
kubectl logs <pod-name> -n production
kubectl logs -f <pod-name> -n production  # Follow logs
kubectl logs <pod-name> -n production --previous  # Previous container logs

# Execute commands in pod
kubectl exec -it <pod-name> -n production -- /bin/bash
kubectl exec <pod-name> -n production -- env

# Port forwarding
kubectl port-forward <pod-name> 8080:80 -n production
kubectl port-forward service/<service-name> 8080:80 -n production

# Delete resources
kubectl delete pod <pod-name> -n production
kubectl delete deployment <deployment-name> -n production
kubectl delete service <service-name> -n production
```

### Common az aks Commands

```bash
# Get cluster credentials
az aks get-credentials -g $RESOURCE_GROUP -n $AKS_CLUSTER_NAME

# Show cluster info
az aks show -g $RESOURCE_GROUP -n $AKS_CLUSTER_NAME

# List clusters
az aks list --output table

# Scale cluster
az aks scale -g $RESOURCE_GROUP -n $AKS_CLUSTER_NAME --node-count 5

# Upgrade cluster
az aks upgrade -g $RESOURCE_GROUP -n $AKS_CLUSTER_NAME --kubernetes-version 1.28.5

# Start stopped cluster
az aks start -g $RESOURCE_GROUP -n $AKS_CLUSTER_NAME

# Stop cluster (saves costs)
az aks stop -g $RESOURCE_GROUP -n $AKS_CLUSTER_NAME
```

---

## Cost Optimization Tips

```bash
# Stop AKS cluster when not in use (deallocates VMs)
az aks stop -g $RESOURCE_GROUP -n $AKS_CLUSTER_NAME

# Start when needed
az aks start -g $RESOURCE_GROUP -n $AKS_CLUSTER_NAME

# Use cheaper VM sizes for testing
# Standard_B2s (2 vCPU, 4GB RAM) - cheapest
# Standard_D2s_v3 (2 vCPU, 8GB RAM) - recommended for testing

# Delete resources when done
az group delete -n $RESOURCE_GROUP --yes --no-wait
```

---

**You're now ready to start your AKS to ARO migration journey! 🚀**
