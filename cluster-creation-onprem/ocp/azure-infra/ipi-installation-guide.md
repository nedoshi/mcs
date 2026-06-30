# Complete OpenShift Container Platform Installation Guide for Azure

This comprehensive guide covers installing both public and private OpenShift clusters on Azure with detailed networking configurations for ingress and egress traffic.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Common Setup](#common-setup)
3. [DNS Configuration](#dns-configuration)
4. [Public Cluster Installation](#public-cluster-installation)
5. [Private Cluster Installation](#private-cluster-installation)
6. [Networking Configuration](#networking-configuration)
7. [Ingress Configuration](#ingress-configuration)
8. [Egress Configuration](#egress-configuration)
9. [Post-Installation](#post-installation)
10. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools
```bash
# OpenShift installer
curl -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-install-linux.tar.gz
tar -xzf openshift-install-linux.tar.gz
sudo mv openshift-install /usr/local/bin/

# OpenShift CLI
curl -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
tar -xzf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin/

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# jq for JSON processing
sudo apt-get install jq -y  # Ubuntu/Debian
# or
sudo yum install jq -y      # RHEL/CentOS
```

### Azure Account Requirements
- Active Azure subscription
- Service Principal with appropriate permissions
- Sufficient resource quotas
- DNS zone management access

## Common Setup

### 1. Azure Authentication
```bash
# Login to Azure
az login

# Set subscription (if you have multiple)
az account set --subscription "your-subscription-id"

# Create service principal
az ad sp create-for-rbac \
  --role Contributor \
  --name openshift-installer \
  --scopes /subscriptions/$(az account show --query id -o tsv)

# Note the output for later use:
# - appId (AZURE_CLIENT_ID)
# - password (AZURE_CLIENT_SECRET)
# - tenant (AZURE_TENANT_ID)
```

### 2. Environment Variables
```bash
export AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export AZURE_CLIENT_ID="your-service-principal-app-id"
export AZURE_CLIENT_SECRET="your-service-principal-password"
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_REGION="eastus"  # or your preferred region
```

### 3. SSH Key Generation
```bash
# Generate SSH key for cluster access
ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/ocp-azure-key

# Get public key content
export SSH_PUBLIC_KEY="$(cat ~/.ssh/ocp-azure-key.pub)"
```

## DNS Configuration Deep Dive

### Understanding DNS Fundamentals for OpenShift

#### What is a Domain?
A **domain** is a human-readable name that points to resources on the internet. In our case:
- `mobb.cloud` - Top-level domain
- `azure-na.mobb.cloud` - Subdomain (your existing DNS zone)
- `nd.azure-na.mobb.cloud` - Cluster domain (what we're creating)

#### DNS Hierarchy Structure
```
                        Root (.)
                           |
                      .cloud (TLD)
                           |
                    mobb.cloud (Domain)
                           |
              azure-na.mobb.cloud (Your DNS Zone)
                           |
          nd.azure-na.mobb.cloud (Cluster Domain)
          /                    \
api.nd.azure-na.mobb.cloud  *.apps.nd.azure-na.mobb.cloud
```

#### What is a DNS Zone?
A **DNS Zone** is a container for DNS records for a particular domain. Think of it as a database that contains:
- **A Records**: Domain → IP Address mappings
- **CNAME Records**: Domain → Another Domain mappings  
- **NS Records**: Delegation to other DNS servers
- **MX Records**: Mail server information

#### DNS Record Types for OpenShift
OpenShift requires specific DNS records:

| Record Type | Name | Purpose | Example |
|-------------|------|---------|---------|
| A | api.clustername | API server access | api.nd.azure-na.mobb.cloud → 20.1.2.3 |
| A | api-int.clustername | Internal API access | api-int.nd.azure-na.mobb.cloud → 10.0.1.100 |
| A | *.apps.clustername | Application ingress | *.apps.nd.azure-na.mobb.cloud → 20.1.2.4 |
| A | console-openshift-console.apps.clustername | Web console | console-openshift-console.apps.nd.azure-na.mobb.cloud → 20.1.2.4 |

### Step-by-Step DNS Setup

#### Step 1: Find Your Existing DNS Zone
```bash
# Find your DNS zone and resource group
az network dns zone list --query "[?name=='azure-na.mobb.cloud'].{Name:name, ResourceGroup:resourceGroup}" -o table

# Example output:
# Name                    ResourceGroup
# ----------------------  ---------------
# azure-na.mobb.cloud     dns-production-rg

# Export the resource group name
export DNS_RESOURCE_GROUP="dns-production-rg"  # Replace with your actual RG
export PARENT_DOMAIN="azure-na.mobb.cloud"
export CLUSTER_NAME="nd"
export CLUSTER_DOMAIN="${CLUSTER_NAME}.${PARENT_DOMAIN}"
```

#### Step 2: Understand DNS Zone Authority
```bash
# Check who controls your DNS zone
az network dns zone show \
  --resource-group $DNS_RESOURCE_GROUP \
  --name $PARENT_DOMAIN \
  --query "nameServers" -o table

# Example output shows Azure DNS name servers:
# Result
# ------------------------
# ns1-05.azure-dns.com.
# ns2-05.azure-dns.net.
# ns3-05.azure-dns.org.
# ns4-05.azure-dns.info.
```

#### Step 3: DNS Record Management Options

**Option A: Direct Record Creation (Recommended)**
OpenShift installer creates records directly in your existing zone:

```bash
# Verify installer has access to create records
az network dns record-set a create \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --name test-record \
  --ttl 300

# Clean up test record
az network dns record-set a delete \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --name test-record \
  --yes

# This is what your install-config.yaml should use:
echo "baseDomainResourceGroupName: $DNS_RESOURCE_GROUP"
```

**Option B: Subdomain Delegation (Advanced)**
Create a separate DNS zone for the cluster:

```bash
# Create new DNS zone for cluster
az network dns zone create \
  --resource-group $DNS_RESOURCE_GROUP \
  --name $CLUSTER_DOMAIN

# Get name servers for the new zone
CLUSTER_NS=$(az network dns zone show \
  --resource-group $DNS_RESOURCE_GROUP \
  --name $CLUSTER_DOMAIN \
  --query "nameServers" -o tsv)

echo "Cluster DNS Zone Name Servers:"
echo "$CLUSTER_NS"

# Create NS records in parent zone to delegate
az network dns record-set ns create \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --name $CLUSTER_NAME \
  --ttl 300

# Add each name server
for ns in $CLUSTER_NS; do
  az network dns record-set ns add-record \
    --resource-group $DNS_RESOURCE_GROUP \
    --zone-name $PARENT_DOMAIN \
    --record-set-name $CLUSTER_NAME \
    --nsdname $ns
done
```

### DNS Verification and Testing

#### Test DNS Resolution
```bash
# Test parent domain resolution
nslookup $PARENT_DOMAIN

# Test if delegation works (Option B only)
nslookup ns $CLUSTER_DOMAIN

# Test specific records after installation
nslookup api.$CLUSTER_DOMAIN
nslookup console-openshift-console.apps.$CLUSTER_DOMAIN
```

#### Advanced DNS Testing
```bash
# Use dig for detailed DNS queries
dig $PARENT_DOMAIN NS
dig api.$CLUSTER_DOMAIN A
dig console-openshift-console.apps.$CLUSTER_DOMAIN A

# Trace DNS resolution path
dig +trace api.$CLUSTER_DOMAIN

# Check DNS propagation globally
# (Use online tools like dnschecker.org for this)
```

### Understanding DNS Record Sets

#### What is a Record Set?
A **Record Set** is a collection of DNS records with the same name and type. For example:
- All A records for "api.nd.azure-na.mobb.cloud"
- All NS records for "nd" in "azure-na.mobb.cloud"

#### Managing Record Sets
```bash
# List all record sets in a zone
az network dns record-set list \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --output table

# View specific record set
az network dns record-set a show \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --name api.$CLUSTER_NAME

# Create A record set
az network dns record-set a create \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --name api.$CLUSTER_NAME \
  --ttl 300

# Add IP to A record set
az network dns record-set a add-record \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --record-set-name api.$CLUSTER_NAME \
  --ipv4-address 20.1.2.3

# Create wildcard A record for apps
az network dns record-set a create \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --name "*.apps.$CLUSTER_NAME" \
  --ttl 300

az network dns record-set a add-record \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --record-set-name "*.apps.$CLUSTER_NAME" \
  --ipv4-address 20.1.2.4
```

## Public Cluster Installation

### 1. Create Installation Directory
```bash
mkdir ~/ocp-public-azure
cd ~/ocp-public-azure
```

### 2. Generate Base Install Config
```bash
openshift-install create install-config --dir .
```

### 3. Public Cluster Install Config
Create or edit `install-config.yaml`:

```yaml
apiVersion: v1
baseDomain: azure-na.mobb.cloud
metadata:
  name: public  # This will create public.azure-na.mobb.cloud
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    azure:
      type: Standard_D4s_v3
      osDisk:
        diskSizeGB: 128
        diskType: Premium_LRS
      zones:
      - "1"
      - "2"
      - "3"
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    azure:
      type: Standard_D8s_v3
      osDisk:
        diskSizeGB: 1024
        diskType: Premium_LRS
      zones:
      - "1"
      - "2"
      - "3"
  replicas: 3
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  azure:
    baseDomainResourceGroupName: YOUR_DNS_RESOURCE_GROUP_NAME
    cloudName: AzurePublicCloud
    outboundType: Loadbalancer
    region: eastus
    resourceGroupName: openshift-public-rg
    networkResourceGroupName: openshift-public-rg
publish: External  # This makes it a public cluster
pullSecret: 'YOUR_PULL_SECRET_HERE'
sshKey: 'YOUR_SSH_PUBLIC_KEY_HERE'
```

### 4. Install Public Cluster
```bash
# Backup config
cp install-config.yaml install-config.yaml.bak

# Start installation
openshift-install create cluster --dir . --log-level=info
```

## Private Cluster Installation

### 1. Create Installation Directory
```bash
mkdir ~/ocp-private-azure
cd ~/ocp-private-azure
```

### 2. Private Cluster Install Config
```yaml
apiVersion: v1
baseDomain: azure-na.mobb.cloud
metadata:
  name: private  # This will create private.azure-na.mobb.cloud
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    azure:
      type: Standard_D4s_v3
      osDisk:
        diskSizeGB: 128
        diskType: Premium_LRS
      zones:
      - "1"
      - "2"
      - "3"
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    azure:
      type: Standard_D8s_v3
      osDisk:
        diskSizeGB: 1024
        diskType: Premium_LRS
      zones:
      - "1"
      - "2"
      - "3"
  replicas: 3
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  azure:
    baseDomainResourceGroupName: YOUR_DNS_RESOURCE_GROUP_NAME
    cloudName: AzurePublicCloud
    outboundType: UserDefinedRouting  # For private clusters with custom egress
    region: eastus
    resourceGroupName: openshift-private-rg
    networkResourceGroupName: openshift-private-rg
publish: Internal  # This makes it a private cluster
pullSecret: 'YOUR_PULL_SECRET_HERE'
sshKey: 'YOUR_SSH_PUBLIC_KEY_HERE'
```

### 3. Install Private Cluster
```bash
# Backup config
cp install-config.yaml install-config.yaml.bak

# Start installation
openshift-install create cluster --dir . --log-level=info
```

## Networking Configuration

### DNS Troubleshooting Guide

#### Common DNS Issues and Solutions

**Issue 1: "ParentResourceNotFound" Error**
```bash
# Error: DNS zone not found in expected resource group
# Solution: Find actual resource group
az network dns zone list --query "[].{Name:name, ResourceGroup:resourceGroup}" -o table

# Update install-config.yaml with correct resource group
# baseDomainResourceGroupName: actual-resource-group-name
```

**Issue 2: DNS Records Not Resolving**
```bash
# Check if records exist in Azure
az network dns record-set list \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --query "[?name=='api.$CLUSTER_NAME' || name=='*.apps.$CLUSTER_NAME']"

# If records don't exist, create manually:
# Get load balancer IPs from cluster
export KUBECONFIG=~/ocp-cluster/auth/kubeconfig
API_IP=$(oc get svc kubernetes -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
INGRESS_IP=$(oc get svc router-default -n openshift-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Create API record
az network dns record-set a create \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --name api.$CLUSTER_NAME \
  --ttl 300

az network dns record-set a add-record \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --record-set-name api.$CLUSTER_NAME \
  --ipv4-address $API_IP

# Create Apps wildcard record
az network dns record-set a create \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --name "*.apps.$CLUSTER_NAME" \
  --ttl 300

az network dns record-set a add-record \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --record-set-name "*.apps.$CLUSTER_NAME" \
  --ipv4-address $INGRESS_IP
```

**Issue 3: DNS Propagation Delays**
```bash
# Check local DNS cache
systemctl flush-dns  # Ubuntu/systemd
sudo dscacheutil -flushcache  # macOS

# Test with different DNS servers
nslookup api.$CLUSTER_DOMAIN 8.8.8.8
nslookup api.$CLUSTER_DOMAIN 1.1.1.1

# Check TTL values
dig api.$CLUSTER_DOMAIN | grep -i ttl
```

**Issue 4: Wildcard DNS Not Working**
```bash
# Test wildcard resolution
nslookup test.apps.$CLUSTER_DOMAIN
nslookup console-openshift-console.apps.$CLUSTER_DOMAIN

# Check wildcard record format
az network dns record-set a show \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --name "*.apps.$CLUSTER_NAME"

# Wildcard should be: *.apps.nd (not *.apps.nd.azure-na.mobb.cloud)
```

### DNS Security Considerations

#### DNS Zone Access Control
```bash
# Check who has access to DNS zone
az role assignment list \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$DNS_RESOURCE_GROUP/providers/Microsoft.Network/dnszones/$PARENT_DOMAIN" \
  --output table

# Grant minimal DNS access to service principal
az role assignment create \
  --assignee $AZURE_CLIENT_ID \
  --role "DNS Zone Contributor" \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$DNS_RESOURCE_GROUP/providers/Microsoft.Network/dnszones/$PARENT_DOMAIN"
```

#### DNS Monitoring
```bash
# Monitor DNS queries (if enabled)
az monitor metrics list \
  --resource "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$DNS_RESOURCE_GROUP/providers/Microsoft.Network/dnszones/$PARENT_DOMAIN" \
  --metric "QueryVolume"

# Set up DNS health checks
az network traffic-manager endpoint create \
  --resource-group $DNS_RESOURCE_GROUP \
  --profile-name openshift-health \
  --name api-health \
  --type externalEndpoints \
  --target api.$CLUSTER_DOMAIN \
  --endpoint-status enabled
```

### Complete DNS Workflow Example

Let's walk through a complete example with domain `nd.azure-na.mobb.cloud`:

#### Pre-Installation DNS Setup
```bash
# 1. Verify existing DNS zone
export DNS_RESOURCE_GROUP="dns-prod-rg"
export PARENT_DOMAIN="azure-na.mobb.cloud"
export CLUSTER_NAME="nd"

# 2. Test DNS zone access
az network dns zone show \
  --resource-group $DNS_RESOURCE_GROUP \
  --name $PARENT_DOMAIN

# 3. Verify service principal permissions
az role assignment list \
  --assignee $AZURE_CLIENT_ID \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$DNS_RESOURCE_GROUP" \
  --query "[].roleDefinitionName"

# 4. Create install-config.yaml with correct DNS settings
cat > install-config.yaml << EOF
apiVersion: v1
baseDomain: $PARENT_DOMAIN
metadata:
  name: $CLUSTER_NAME
platform:
  azure:
    baseDomainResourceGroupName: $DNS_RESOURCE_GROUP
    # ... other settings
EOF
```

#### Post-Installation DNS Verification
```bash
# 1. Check created DNS records
az network dns record-set list \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name $PARENT_DOMAIN \
  --query "[?contains(name, '$CLUSTER_NAME')]" \
  --output table

# 2. Test DNS resolution
for record in "api.$CLUSTER_NAME" "console-openshift-console.apps.$CLUSTER_NAME"; do
  echo "Testing $record.$PARENT_DOMAIN"
  nslookup $record.$PARENT_DOMAIN
  echo "---"
done

# 3. Verify cluster access
export KUBECONFIG=~/ocp-cluster/auth/kubeconfig
oc get nodes
curl -k https://api.$CLUSTER_NAME.$PARENT_DOMAIN:6443/version
```

### DNS Best Practices for OpenShift

#### Record Management
- **TTL Values**: Use short TTL (300s) during installation, increase (3600s+) for production
- **Record Types**: Use A records for better performance over CNAME where possible
- **Monitoring**: Set up DNS monitoring and alerting for critical records
- **Backup**: Document all DNS records for disaster recovery

#### Security
- **Access Control**: Use minimal permissions for DNS zone access
- **Monitoring**: Log DNS changes and unusual query patterns  
- **Validation**: Always test DNS changes in non-production first

#### Automation
```bash
# Script to validate DNS before installation
#!/bin/bash
validate_dns() {
  local domain=$1
  local rg=$2
  
  echo "Validating DNS for $domain in resource group $rg"
  
  # Check zone exists
  if ! az network dns zone show --resource-group $rg --name $domain &>/dev/null; then
    echo "ERROR: DNS zone $domain not found in $rg"
    return 1
  fi
  
  # Check permissions
  if ! az network dns record-set a create --resource-group $rg --zone-name $domain --name test-validation --ttl 300 --dry-run &>/dev/null; then
    echo "ERROR: No permission to create DNS records in $domain"
    return 1
  fi
  
  echo "DNS validation passed"
  return 0
}

# Usage
validate_dns "azure-na.mobb.cloud" "dns-prod-rg"
```

```bash
# Create resource group
az group create --name openshift-network-rg --location $AZURE_REGION

# Create VNet
az network vnet create \
  --resource-group openshift-network-rg \
  --name openshift-vnet \
  --address-prefixes 10.0.0.0/16 \
  --location $AZURE_REGION

# Create master subnet
az network vnet subnet create \
  --resource-group openshift-network-rg \
  --vnet-name openshift-vnet \
  --name master-subnet \
  --address-prefixes 10.0.1.0/24 \
  --service-endpoints Microsoft.ContainerRegistry

# Create worker subnet
az network vnet subnet create \
  --resource-group openshift-network-rg \
  --vnet-name openshift-vnet \
  --name worker-subnet \
  --address-prefixes 10.0.2.0/24 \
  --service-endpoints Microsoft.ContainerRegistry

# For private clusters, create NAT Gateway for outbound connectivity
az network public-ip create \
  --resource-group openshift-network-rg \
  --name nat-gateway-ip \
  --sku Standard \
  --allocation-method Static

az network nat gateway create \
  --resource-group openshift-network-rg \
  --name openshift-nat-gateway \
  --public-ip-addresses nat-gateway-ip \
  --idle-timeout 4

# Associate NAT Gateway with subnets
az network vnet subnet update \
  --resource-group openshift-network-rg \
  --vnet-name openshift-vnet \
  --name master-subnet \
  --nat-gateway openshift-nat-gateway

az network vnet subnet update \
  --resource-group openshift-network-rg \
  --vnet-name openshift-vnet \
  --name worker-subnet \
  --nat-gateway openshift-nat-gateway
```

### Update Install Config for Custom Networking
Add to your install-config.yaml:

```yaml
platform:
  azure:
    networkResourceGroupName: openshift-network-rg
    virtualNetwork: openshift-vnet
    controlPlaneSubnet: master-subnet
    computeSubnet: worker-subnet
```

## Ingress Configuration

### Default Ingress Controller
OpenShift creates a default ingress controller. Check its status:

```bash
# Check ingress controller
oc get ingresscontroller default -n openshift-ingress-operator

# Check ingress service
oc get svc router-default -n openshift-ingress

# For private clusters, check internal load balancer
oc get svc router-default -n openshift-ingress -o jsonpath='{.metadata.annotations.service\.beta\.kubernetes\.io/azure-load-balancer-internal}'
```

### Custom Ingress Controllers

#### Public Ingress Controller
```yaml
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: public-ingress
  namespace: openshift-ingress-operator
spec:
  domain: apps-public.private.azure-na.mobb.cloud
  endpointPublishingStrategy:
    type: LoadBalancerService
    loadBalancer:
      scope: External
      providerParameters:
        type: Azure
        azure:
          resourceGroup: openshift-private-rg
  replicas: 2
  routeSelector:
    matchLabels:
      ingress: public
```

#### Internal Ingress Controller
```yaml
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: internal-ingress
  namespace: openshift-ingress-operator
spec:
  domain: apps-internal.private.azure-na.mobb.cloud
  endpointPublishingStrategy:
    type: LoadBalancerService
    loadBalancer:
      scope: Internal
      providerParameters:
        type: Azure
        azure:
          resourceGroup: openshift-private-rg
  replicas: 2
  routeSelector:
    matchLabels:
      ingress: internal
```

### Apply Ingress Controllers
```bash
# Apply public ingress
oc apply -f public-ingress-controller.yaml

# Apply internal ingress
oc apply -f internal-ingress-controller.yaml

# Verify ingress controllers
oc get ingresscontroller -n openshift-ingress-operator
```

### Create Routes with Specific Ingress
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: public-app-route
  labels:
    ingress: public  # This routes through public ingress
spec:
  host: myapp-public.apps-public.private.azure-na.mobb.cloud
  to:
    kind: Service
    name: my-app-service
  port:
    targetPort: 8080
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: internal-app-route
  labels:
    ingress: internal  # This routes through internal ingress
spec:
  host: myapp-internal.apps-internal.private.azure-na.mobb.cloud
  to:
    kind: Service
    name: my-app-service
  port:
    targetPort: 8080
```

## Egress Configuration

### Network Policies for Egress Control

#### Allow All Egress (Default)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-egress
  namespace: my-app-namespace
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - {}  # Allow all egress
```

#### Restricted Egress
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restricted-egress
  namespace: my-app-namespace
spec:
  podSelector:
    matchLabels:
      app: restricted-app
  policyTypes:
  - Egress
  egress:
  # Allow DNS
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  # Allow HTTPS to external services
  - ports:
    - protocol: TCP
      port: 443
    to: []
  # Allow internal cluster communication
  - to:
    - namespaceSelector: {}
```

#### Egress to Specific External Services
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-specific-egress
  namespace: my-app-namespace
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes:
  - Egress
  egress:
  # Allow DNS
  - ports:
    - protocol: UDP
      port: 53
  # Allow access to specific external IP
  - to:
    - ipBlock:
        cidr: 52.226.139.0/24  # Example: Azure service IP range
    ports:
    - protocol: TCP
      port: 443
  # Allow access to external services by FQDN (requires additional setup)
  - ports:
    - protocol: TCP
      port: 443
```

### Azure NAT Gateway for Egress (Private Clusters)

For private clusters, configure NAT Gateway for controlled egress:

```bash
# Create public IP for NAT Gateway
az network public-ip create \
  --resource-group openshift-private-rg \
  --name cluster-nat-ip \
  --sku Standard \
  --allocation-method Static

# Create NAT Gateway
az network nat gateway create \
  --resource-group openshift-private-rg \
  --name cluster-nat-gateway \
  --public-ip-addresses cluster-nat-ip \
  --idle-timeout 10

# Get the worker subnet ID
WORKER_SUBNET_ID=$(az network vnet subnet show \
  --resource-group openshift-private-rg \
  --vnet-name private-xyz-vnet \
  --name private-xyz-worker-subnet \
  --query id -o tsv)

# Associate NAT Gateway with worker subnet
az network vnet subnet update \
  --ids $WORKER_SUBNET_ID \
  --nat-gateway cluster-nat-gateway
```

### Azure Firewall for Advanced Egress Control

```bash
# Create Azure Firewall subnet
az network vnet subnet create \
  --resource-group openshift-network-rg \
  --vnet-name openshift-vnet \
  --name AzureFirewallSubnet \
  --address-prefixes 10.0.100.0/24

# Create public IP for firewall
az network public-ip create \
  --resource-group openshift-network-rg \
  --name firewall-ip \
  --sku Standard \
  --allocation-method Static

# Create Azure Firewall
az network firewall create \
  --resource-group openshift-network-rg \
  --name openshift-firewall \
  --location $AZURE_REGION

# Configure firewall IP
az network firewall ip-config create \
  --resource-group openshift-network-rg \
  --firewall-name openshift-firewall \
  --name firewall-config \
  --public-ip-address firewall-ip \
  --vnet-name openshift-vnet

# Create route table for egress through firewall
az network route-table create \
  --resource-group openshift-network-rg \
  --name firewall-route-table

# Add route to send traffic through firewall
FIREWALL_PRIVATE_IP=$(az network firewall show \
  --resource-group openshift-network-rg \
  --name openshift-firewall \
  --query "ipConfigurations[0].privateIPAddress" -o tsv)

az network route-table route create \
  --resource-group openshift-network-rg \
  --route-table-name firewall-route-table \
  --name internet-route \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address $FIREWALL_PRIVATE_IP

# Associate route table with subnets
az network vnet subnet update \
  --resource-group openshift-network-rg \
  --vnet-name openshift-vnet \
  --name worker-subnet \
  --route-table firewall-route-table
```

### Firewall Rules for OpenShift
```bash
# Allow OpenShift required outbound traffic
az network firewall application-rule create \
  --resource-group openshift-network-rg \
  --firewall-name openshift-firewall \
  --collection-name openshift-rules \
  --name allow-openshift-external \
  --protocols Https=443 Http=80 \
  --source-addresses 10.0.0.0/16 \
  --target-fqdns \
    "*.redhat.io" \
    "*.openshift.com" \
    "*.fedoraproject.org" \
    "*.cloudfront.net" \
    "*.amazonaws.com" \
    "quay.io" \
    "*.quay.io" \
    "registry.redhat.io" \
    "*.microsoft.com" \
    "*.azure.com" \
  --priority 100 \
  --action Allow
```

## Post-Installation

### Verify Cluster Access
```bash
# Set KUBECONFIG
export KUBECONFIG=~/ocp-public-azure/auth/kubeconfig  # or private cluster path

# Test cluster access
oc get nodes
oc get co
oc version

# Get cluster info
oc cluster-info
```

### Access Web Console
```bash
# Get console URL
echo "Console URL: $(oc whoami --show-console)"

# Get admin password
echo "Admin password: $(cat ~/ocp-public-azure/auth/kubeadmin-password)"
```

### Test Application Deployment
```bash
# Create test project
oc new-project test-networking

# Deploy test application
cat << EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: test-networking
spec:
  replicas: 2
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: test-app-service
  namespace: test-networking
spec:
  selector:
    app: test-app
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: test-app-route
  namespace: test-networking
spec:
  to:
    kind: Service
    name: test-app-service
  port:
    targetPort: 8080
EOF

# Test the route
oc get route test-app-route -n test-networking
curl $(oc get route test-app-route -n test-networking -o jsonpath='{.spec.host}')
```

## Troubleshooting

```bash
az network dns zone list --query "[?name=='nd.azure-na.mobb.cloud'].{Name:name, ResourceGroup:resourceGroup}" -o table
```



### Common DNS Issues
```bash
# Check DNS resolution
nslookup api.public.azure-na.mobb.cloud
nslookup console-openshift-console.apps.public.azure-na.mobb.cloud

# Check DNS records in Azure
az network dns record-set list \
  --resource-group $DNS_RESOURCE_GROUP \
  --zone-name azure-na.mobb.cloud \
  --query "[?contains(name, 'public') || contains(name, 'private')]" \
  --output table

# Test DNS propagation
dig +trace api.public.azure-na.mobb.cloud
dig +short api.public.azure-na.mobb.cloud

# Manually create missing DNS records if needed
# Get load balancer IPs
export KUBECONFIG=~/ocp-public-azure/auth/kubeconfig
API_IP=$(oc get svc kubernetes -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
INGRESS_IP=$(oc get svc router-default -n openshift-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "API IP: $API_IP"
echo "Ingress IP: $INGRESS_IP"

# Create records if they don't exist
if [ ! -z "$API_IP" ]; then
  az network dns record-set a create \
    --resource-group $DNS_RESOURCE_GROUP \
    --zone-name azure-na.mobb.cloud \
    --name api.public \
    --ttl 300 || true
    
  az network dns record-set a add-record \
    --resource-group $DNS_RESOURCE_GROUP \
    --zone-name azure-na.mobb.cloud \
    --record-set-name api.public \
    --ipv4-address $API_IP
fi

if [ ! -z "$INGRESS_IP" ]; then
  az network dns record-set a create \
    --resource-group $DNS_RESOURCE_GROUP \
    --zone-name azure-na.mobb.cloud \
    --name "*.apps.public" \
    --ttl 300 || true
    
  az network dns record-set a add-record \
    --resource-group $DNS_RESOURCE_GROUP \
    --zone-name azure-na.mobb.cloud \
    --record-set-name "*.apps.public" \
    --ipv4-address $INGRESS_IP
fi
```

### Network Connectivity Issues
```bash
# Test pod to external connectivity
oc debug node/worker-node-name
# Inside the debug pod:
curl -I https://www.google.com
nslookup google.com

# Check ingress controller logs
oc logs -n openshift-ingress-operator deployment/ingress-operator

# Check cluster network operator
oc logs -n openshift-cluster-network-operator deployment/network-operator
```

### Ingress Issues
```bash
# Check ingress controller status
oc get ingresscontroller -n openshift-ingress-operator

# Check ingress services
oc get svc -n openshift-ingress

# Check route status
oc describe route your-route-name

# Test ingress with curl
curl -H "Host: your-app.apps.cluster.domain.com" http://load-balancer-ip
```

### Resource and Quota Issues
```bash
# Check Azure resource usage
az vm list-usage --location $AZURE_REGION --query "[?currentValue > 0]"

# Check OpenShift resource usage
oc adm top nodes
oc adm top pods --all-namespaces

# Check cluster operators status
oc get co
oc describe co storage
```

### Performance Optimization
```bash
# Check node performance
oc debug node/node-name
# Inside debug pod:
top
iostat -x 1
free -h

# Optimize ingress for performance
oc patch ingresscontroller default -n openshift-ingress-operator --type='merge' \
  -p='{"spec":{"replicas":4,"tuningOptions":{"reloadInterval":"5s"}}}'
```

## Security Best Practices

### Network Security
- Use private clusters for production workloads
- Implement network policies for micro-segmentation
- Use Azure NSGs for additional network protection
- Consider Azure Firewall for advanced threat protection

### Access Control
- Remove default kubeadmin user after setting up proper RBAC
- Integrate with Azure AD for authentication
- Use least-privilege access principles
- Regularly audit cluster permissions

### Monitoring and Logging
- Enable Azure Monitor integration
- Set up centralized logging
- Monitor network traffic patterns
- Implement security scanning for container images

This guide provides comprehensive coverage for both public and private OpenShift installations on Azure with detailed networking configurations. Adjust the configurations based on your specific security and networking requirements.