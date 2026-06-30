# Pre-Migration Checklist

This comprehensive checklist ensures all prerequisites are met before beginning the AKS to ARO migration. Complete each section in order, checking off items as you verify them.

## Table of Contents

- [1. Azure Environment Prerequisites](#1-azure-environment-prerequisites)
- [2. ARO Cluster Provisioning](#2-aro-cluster-provisioning)
- [3. Network Connectivity](#3-network-connectivity)
- [4. Database Access Configuration](#4-database-access-configuration)
- [5. Container Registry Integration](#5-container-registry-integration)
- [6. Azure Key Vault Integration](#6-azure-key-vault-integration)
- [7. Application Assessment](#7-application-assessment)
- [8. Tooling and Access](#8-tooling-and-access)
- [9. Backup and Rollback Preparation](#9-backup-and-rollback-preparation)
- [10. Final Validation](#10-final-validation)

---

## 1. Azure Environment Prerequisites

### Azure Subscription and Quotas

- [ ] **Verify Azure subscription access**
  ```bash
  az account show
  az account list --output table
  ```

- [ ] **Check ARO resource provider registration**
  ```bash
  az provider register -n Microsoft.RedHatOpenShift --wait
  az provider show -n Microsoft.RedHatOpenShift --query "registrationState"
  ```

- [ ] **Verify sufficient quota for ARO**
  ```bash
  # Check vCPU quota (minimum 40 vCPUs required for ARO)
  az vm list-usage --location eastus --query "[?name.value=='cores'].{Name:name.localizedValue, CurrentValue:currentValue, Limit:limit}" --output table
  ```

- [ ] **Confirm resource group exists or create new one**
  ```bash
  export ARO_RESOURCE_GROUP="aro-migration-rg"
  export LOCATION="eastus"
  
  az group create --name $ARO_RESOURCE_GROUP --location $LOCATION
  ```

### Service Principal or Managed Identity

- [ ] **Create or identify service principal for ARO**
  ```bash
  # Option 1: Create new service principal
  az ad sp create-for-rbac --name "aro-cluster-sp" --role contributor --scopes /subscriptions/<subscription-id>
  
  # Save the output securely:
  # - appId (client ID)
  # - password (client secret)
  # - tenant
  ```

- [ ] **Assign required permissions to service principal**
  ```bash
  # Contributor on subscription or resource group
  az role assignment create \
    --assignee <service-principal-app-id> \
    --role Contributor \
    --scope /subscriptions/<subscription-id>/resourceGroups/$ARO_RESOURCE_GROUP
  ```

### Azure Active Directory (Optional for OAuth)

- [ ] **Plan for ARO authentication method**
  - [ ] Azure AD integration (recommended for enterprise)
  - [ ] Built-in kubeadmin (for testing/migration phase)
  - [ ] HTPasswd identity provider

---

## 2. ARO Cluster Provisioning

### Cluster Specifications

- [ ] **Define cluster sizing requirements**
  - [ ] Worker node count: ___________ (minimum 3)
  - [ ] Worker node VM size: ___________ (e.g., Standard_D8s_v3)
  - [ ] Master node VM size: ___________ (minimum Standard_D8s_v3)
  - [ ] OpenShift version: ___________ (e.g., 4.13, 4.14)

- [ ] **Determine cluster visibility**
  - [ ] Public cluster (API and Ingress publicly accessible)
  - [ ] Private cluster (API and Ingress on private network only)

### Network Planning

- [ ] **Define or create Virtual Network**
  ```bash
  export VNET_NAME="aro-vnet"
  export VNET_CIDR="10.0.0.0/16"
  export MASTER_SUBNET="master-subnet"
  export MASTER_SUBNET_CIDR="10.0.0.0/23"
  export WORKER_SUBNET="worker-subnet"
  export WORKER_SUBNET_CIDR="10.0.2.0/23"
  
  # Create VNet
  az network vnet create \
    --resource-group $ARO_RESOURCE_GROUP \
    --name $VNET_NAME \
    --address-prefixes $VNET_CIDR
  ```

- [ ] **Create master and worker subnets**
  ```bash
  # Create master subnet
  az network vnet subnet create \
    --resource-group $ARO_RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name $MASTER_SUBNET \
    --address-prefixes $MASTER_SUBNET_CIDR \
    --service-endpoints Microsoft.ContainerRegistry
  
  # Create worker subnet
  az network vnet subnet create \
    --resource-group $ARO_RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name $WORKER_SUBNET \
    --address-prefixes $WORKER_SUBNET_CIDR \
    --service-endpoints Microsoft.ContainerRegistry
  ```

- [ ] **Disable subnet private endpoint policies**
  ```bash
  az network vnet subnet update \
    --resource-group $ARO_RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name $MASTER_SUBNET \
    --disable-private-link-service-network-policies true
  ```

### ARO Cluster Creation

- [ ] **Create ARO cluster**
  ```bash
  export ARO_CLUSTER_NAME="aro-migration-cluster"
  export PULL_SECRET=$(cat ~/pull-secret.txt)  # Get from cloud.redhat.com
  
  az aro create \
    --resource-group $ARO_RESOURCE_GROUP \
    --name $ARO_CLUSTER_NAME \
    --vnet $VNET_NAME \
    --master-subnet $MASTER_SUBNET \
    --worker-subnet $WORKER_SUBNET \
    --client-id <service-principal-app-id> \
    --client-secret <service-principal-password> \
    --pull-secret "$PULL_SECRET" \
    --worker-count 3 \
    --worker-vm-size Standard_D8s_v3 \
    --location $LOCATION
  ```
  
  **Note**: Cluster creation takes 30-40 minutes.

- [ ] **Verify cluster creation**
  ```bash
  az aro show \
    --resource-group $ARO_RESOURCE_GROUP \
    --name $ARO_CLUSTER_NAME \
    --query "provisioningState" -o tsv
  ```

- [ ] **Retrieve cluster credentials**
  ```bash
  # Get API server URL
  ARO_API_URL=$(az aro show \
    --resource-group $ARO_RESOURCE_GROUP \
    --name $ARO_CLUSTER_NAME \
    --query "apiserverProfile.url" -o tsv)
  
  # Get console URL
  ARO_CONSOLE_URL=$(az aro show \
    --resource-group $ARO_RESOURCE_GROUP \
    --name $ARO_CLUSTER_NAME \
    --query "consoleProfile.url" -o tsv)
  
  # Get kubeadmin credentials
  ARO_ADMIN_USER=$(az aro list-credentials \
    --resource-group $ARO_RESOURCE_GROUP \
    --name $ARO_CLUSTER_NAME \
    --query "kubeadminUsername" -o tsv)
  
  ARO_ADMIN_PASSWORD=$(az aro list-credentials \
    --resource-group $ARO_RESOURCE_GROUP \
    --name $ARO_CLUSTER_NAME \
    --query "kubeadminPassword" -o tsv)
  
  echo "API URL: $ARO_API_URL"
  echo "Console URL: $ARO_CONSOLE_URL"
  echo "Username: $ARO_ADMIN_USER"
  echo "Password: $ARO_ADMIN_PASSWORD"
  ```

- [ ] **Test cluster access**
  ```bash
  oc login $ARO_API_URL -u $ARO_ADMIN_USER -p $ARO_ADMIN_PASSWORD
  oc get nodes
  oc get clusterversion
  ```

---

## 3. Network Connectivity

### VNET Peering (if AKS and ARO in different VNETs)

- [ ] **Identify AKS VNET details**
  ```bash
  export AKS_CLUSTER_NAME="my-aks-cluster"
  export AKS_RESOURCE_GROUP="aks-rg"
  
  AKS_VNET_ID=$(az aks show \
    --resource-group $AKS_RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query "nodeResourceGroup" -o tsv | xargs -I {} az network vnet list -g {} --query "[0].id" -o tsv)
  
  echo "AKS VNET ID: $AKS_VNET_ID"
  ```

- [ ] **Create VNET peering from ARO to AKS**
  ```bash
  ARO_VNET_ID=$(az network vnet show \
    --resource-group $ARO_RESOURCE_GROUP \
    --name $VNET_NAME \
    --query "id" -o tsv)
  
  # ARO to AKS peering
  az network vnet peering create \
    --resource-group $ARO_RESOURCE_GROUP \
    --name aro-to-aks-peering \
    --vnet-name $VNET_NAME \
    --remote-vnet $AKS_VNET_ID \
    --allow-vnet-access
  
  # AKS to ARO peering
  AKS_VNET_NAME=$(az network vnet list -g $(az aks show --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "nodeResourceGroup" -o tsv) --query "[0].name" -o tsv)
  AKS_VNET_RG=$(az aks show --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "nodeResourceGroup" -o tsv)
  
  az network vnet peering create \
    --resource-group $AKS_VNET_RG \
    --name aks-to-aro-peering \
    --vnet-name $AKS_VNET_NAME \
    --remote-vnet $ARO_VNET_ID \
    --allow-vnet-access
  ```

- [ ] **Verify peering status**
  ```bash
  az network vnet peering list \
    --resource-group $ARO_RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --output table
  ```

### Network Security Groups (NSGs)

- [ ] **Review and update NSG rules for ARO subnets**
  ```bash
  # List NSGs associated with ARO subnets
  az network nsg list \
    --resource-group $ARO_RESOURCE_GROUP \
    --output table
  ```

- [ ] **Ensure egress connectivity for container registry**
  - [ ] Allow HTTPS (443) to ACR endpoint
  - [ ] Allow HTTPS (443) to quay.io and registry.redhat.io (for OpenShift images)

### DNS Configuration

- [ ] **Plan DNS strategy**
  - [ ] Use Azure Private DNS zones (for private clusters)
  - [ ] Update public DNS records (for public clusters)
  - [ ] Verify custom domain requirements

- [ ] **Test DNS resolution from ARO cluster**
  ```bash
  oc debug node/<node-name>
  # Inside debug pod:
  chroot /host
  nslookup <your-database-fqdn>
  nslookup <your-acr-name>.azurecr.io
  ```

---

## 4. Database Access Configuration

### Azure Database for PostgreSQL

- [ ] **Identify database connection details**
  ```bash
  export DB_SERVER_NAME="my-postgres-server"
  export DB_RESOURCE_GROUP="database-rg"
  
  DB_FQDN=$(az postgres flexible-server show \
    --resource-group $DB_RESOURCE_GROUP \
    --name $DB_SERVER_NAME \
    --query "fullyQualifiedDomainName" -o tsv)
  
  echo "Database FQDN: $DB_FQDN"
  ```

- [ ] **Update firewall rules for ARO subnet**
  ```bash
  # Get ARO worker subnet CIDR
  WORKER_SUBNET_CIDR=$(az network vnet subnet show \
    --resource-group $ARO_RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name $WORKER_SUBNET \
    --query "addressPrefix" -o tsv)
  
  # Add firewall rule for ARO subnet
  az postgres flexible-server firewall-rule create \
    --resource-group $DB_RESOURCE_GROUP \
    --name $DB_SERVER_NAME \
    --rule-name "aro-worker-subnet" \
    --start-ip-address $(echo $WORKER_SUBNET_CIDR | cut -d'/' -f1) \
    --end-ip-address $(echo $WORKER_SUBNET_CIDR | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3".255"}')
  ```
  
  **Note**: For production, use VNET integration or Private Link instead of firewall rules.

- [ ] **Test database connectivity from ARO**
  ```bash
  # Create a test pod with PostgreSQL client
  oc run psql-test --image=postgres:15 --rm -it --restart=Never -- \
    psql -h $DB_FQDN -U <db-admin-user> -d postgres -c "SELECT version();"
  ```

- [ ] **Configure Private Endpoint (recommended for production)**
  ```bash
  # Create private endpoint for database
  az network private-endpoint create \
    --resource-group $ARO_RESOURCE_GROUP \
    --name postgres-private-endpoint \
    --vnet-name $VNET_NAME \
    --subnet $WORKER_SUBNET \
    --private-connection-resource-id $(az postgres flexible-server show -g $DB_RESOURCE_GROUP -n $DB_SERVER_NAME --query id -o tsv) \
    --group-id postgresqlServer \
    --connection-name postgres-connection
  ```

### Connection String Management

- [ ] **Verify existing connection string format**
  - [ ] Note authentication method (password, managed identity, Azure AD)
  - [ ] Identify SSL/TLS requirements
  - [ ] Document connection pooling settings

- [ ] **Test connection string from ARO context**

---

## 5. Container Registry Integration

### Azure Container Registry (ACR)

- [ ] **Identify ACR instance**
  ```bash
  export ACR_NAME="mycontainerregistry"
  
  ACR_LOGIN_SERVER=$(az acr show \
    --name $ACR_NAME \
    --query "loginServer" -o tsv)
  
  echo "ACR Login Server: $ACR_LOGIN_SERVER"
  ```

- [ ] **Choose ACR integration method**
  - [ ] Option A: Managed Identity (recommended)
  - [ ] Option B: Service Principal with pull secret
  - [ ] Option C: Admin credentials (not recommended for production)

### Option A: Managed Identity Integration

- [ ] **Attach ACR to ARO cluster (if supported)**
  ```bash
  # Note: ARO may require manual managed identity configuration
  # Get ARO service principal
  ARO_SP=$(az aro show -g $ARO_RESOURCE_GROUP -n $ARO_CLUSTER_NAME --query servicePrincipalProfile.clientId -o tsv)
  
  # Assign AcrPull role
  az role assignment create \
    --assignee $ARO_SP \
    --role AcrPull \
    --scope $(az acr show -n $ACR_NAME --query id -o tsv)
  ```

### Option B: Pull Secret Configuration

- [ ] **Create service principal for ACR access**
  ```bash
  ACR_REGISTRY_ID=$(az acr show --name $ACR_NAME --query id --output tsv)
  
  SP_APP_ID=$(az ad sp create-for-rbac \
    --name "aro-acr-pull" \
    --role acrpull \
    --scopes $ACR_REGISTRY_ID \
    --query appId -o tsv)
  
  SP_PASSWORD=$(az ad sp credential reset \
    --id $SP_APP_ID \
    --query password -o tsv)
  
  echo "Service Principal App ID: $SP_APP_ID"
  echo "Service Principal Password: $SP_PASSWORD"
  ```

- [ ] **Create Kubernetes pull secret in ARO**
  ```bash
  oc create secret docker-registry acr-pull-secret \
    --docker-server=$ACR_LOGIN_SERVER \
    --docker-username=$SP_APP_ID \
    --docker-password=$SP_PASSWORD \
    --namespace=default
  
  # For all namespaces, repeat or link the secret
  ```

- [ ] **Test image pull from ACR**
  ```bash
  oc run test-acr --image=$ACR_LOGIN_SERVER/sample-app:latest --dry-run=client -o yaml | \
    yq eval '.spec.imagePullSecrets = [{"name": "acr-pull-secret"}]' | \
    oc apply -f -
  
  oc get pods test-acr
  oc delete pod test-acr
  ```

### Registry Network Access

- [ ] **Update ACR firewall rules for ARO**
  ```bash
  # Allow ARO worker subnet
  az acr network-rule add \
    --name $ACR_NAME \
    --subnet $(az network vnet subnet show -g $ARO_RESOURCE_GROUP --vnet-name $VNET_NAME --name $WORKER_SUBNET --query id -o tsv)
  ```

---

## 6. Azure Key Vault Integration

### Azure Key Vault CSI Driver

- [ ] **Install Secrets Store CSI Driver on ARO**
  ```bash
  # ARO 4.13+ includes CSI driver, but may need to enable
  oc apply -f https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy/rbac-secretproviderclass.yaml
  oc apply -f https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy/csidriver.yaml
  oc apply -f https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy/secrets-store.csi.x-k8s.io_secretproviderclasses.yaml
  oc apply -f https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy/secrets-store.csi.x-k8s.io_secretproviderclasspodstatuses.yaml
  oc apply -f https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy/secrets-store-csi-driver.yaml
  ```

- [ ] **Install Azure Key Vault Provider**
  ```bash
  oc apply -f https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/deployment/provider-azure-installer.yaml
  ```

### Key Vault Access Configuration

- [ ] **Grant ARO service principal access to Key Vault**
  ```bash
  export KEY_VAULT_NAME="my-keyvault"
  
  # Get ARO service principal
  ARO_SP=$(az aro show -g $ARO_RESOURCE_GROUP -n $ARO_CLUSTER_NAME --query servicePrincipalProfile.clientId -o tsv)
  
  # Grant secret read permissions
  az keyvault set-policy \
    --name $KEY_VAULT_NAME \
    --object-id $(az ad sp show --id $ARO_SP --query id -o tsv) \
    --secret-permissions get list
  ```

- [ ] **Create SecretProviderClass for your application**
  ```yaml
  # Example - save as secretproviderclass.yaml
  apiVersion: secrets-store.csi.x-k8s.io/v1
  kind: SecretProviderClass
  metadata:
    name: azure-keyvault-secrets
    namespace: default
  spec:
    provider: azure
    parameters:
      usePodIdentity: "false"
      useVMManagedIdentity: "true"
      userAssignedIdentityID: "<service-principal-client-id>"
      keyvaultName: "<key-vault-name>"
      tenantId: "<tenant-id>"
      objects: |
        array:
          - |
            objectName: db-connection-string
            objectType: secret
            objectVersion: ""
  ```

- [ ] **Test Key Vault secret retrieval**
  ```bash
  # Deploy a test pod that mounts secrets
  oc apply -f secretproviderclass.yaml
  ```

---

## 7. Application Assessment

### Current AKS Application Inventory

- [ ] **Document all workloads in AKS**
  ```bash
  # List all deployments
  kubectl get deployments --all-namespaces -o wide > aks-deployments.txt
  
  # List all services
  kubectl get services --all-namespaces -o wide > aks-services.txt
  
  # List all ingresses
  kubectl get ingress --all-namespaces -o yaml > aks-ingresses.yaml
  
  # List all configmaps and secrets
  kubectl get configmaps,secrets --all-namespaces > aks-configs.txt
  ```

- [ ] **Identify custom resource definitions (CRDs)**
  ```bash
  kubectl get crd -o name > aks-crds.txt
  ```

- [ ] **Check for stateful applications**
  ```bash
  kubectl get statefulsets --all-namespaces
  kubectl get pvc --all-namespaces
  ```

### ARO Compatibility Assessment

- [ ] **Check for privileged containers**
  ```bash
  # Review security contexts in deployments
  kubectl get deployments --all-namespaces -o json | \
    jq '.items[] | select(.spec.template.spec.securityContext.privileged == true or .spec.template.spec.containers[].securityContext.privileged == true) | .metadata.name'
  ```

- [ ] **Identify hostPath or hostNetwork usage**
  ```bash
  kubectl get pods --all-namespaces -o json | \
    jq '.items[] | select(.spec.hostNetwork == true or .spec.volumes[]?.hostPath != null) | .metadata.name'
  ```

- [ ] **Review Ingress configurations for conversion to Routes**
  - [ ] Note TLS certificates and termination policies
  - [ ] Document path-based routing rules
  - [ ] Identify any custom annotations

### Application Dependencies

- [ ] **Map external service dependencies**
  - [ ] Azure Storage accounts
  - [ ] Azure Service Bus / Event Hubs
  - [ ] Third-party APIs
  - [ ] Other microservices

- [ ] **Document environment-specific configurations**
  - [ ] Environment variables
  - [ ] ConfigMaps
  - [ ] Secrets (note: export values from AKS, not from checklist)

---

## 8. Tooling and Access

### Required CLI Tools

- [ ] **Verify Azure CLI version**
  ```bash
  az version
  # Required: 2.50.0 or higher
  ```

- [ ] **Verify kubectl version**
  ```bash
  kubectl version --client
  # Required: 1.28.0 or higher
  ```

- [ ] **Install OpenShift CLI (oc)**
  ```bash
  # Download from https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
  # Or use package manager:
  # macOS:
  brew install openshift-cli
  
  # Linux:
  wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
  tar -xzf openshift-client-linux.tar.gz
  sudo mv oc /usr/local/bin/
  
  oc version
  ```

- [ ] **Install jq for JSON processing**
  ```bash
  # macOS:
  brew install jq
  
  # Linux:
  sudo apt-get install jq  # Debian/Ubuntu
  sudo yum install jq      # RHEL/CentOS
  ```

- [ ] **Install yq for YAML processing (optional)**
  ```bash
  brew install yq
  # Or download from https://github.com/mikefarah/yq
  ```

### Access Credentials

- [ ] **AKS cluster kubeconfig obtained**
  ```bash
  az aks get-credentials \
    --resource-group $AKS_RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --admin
  
  kubectl config current-context
  ```

- [ ] **ARO cluster credentials saved**
  ```bash
  # Save credentials to environment variables or secure storage
  export ARO_API_URL="<api-url>"
  export ARO_ADMIN_USER="<kubeadmin>"
  export ARO_ADMIN_PASSWORD="<password>"
  ```

- [ ] **Database admin credentials available**

- [ ] **Azure Key Vault access verified**

---

## 9. Backup and Rollback Preparation

### AKS Backup

- [ ] **Export all Kubernetes resources from AKS**
  ```bash
  # Create backup directory
  mkdir -p aks-backup/$(date +%Y%m%d)
  
  # Export all resources
  kubectl get all --all-namespaces -o yaml > aks-backup/$(date +%Y%m%d)/all-resources.yaml
  
  # Export specific resource types
  for resource in deployment service configmap secret ingress pvc; do
    kubectl get $resource --all-namespaces -o yaml > aks-backup/$(date +%Y%m%d)/$resource.yaml
  done
  ```

- [ ] **Document current application state**
  - [ ] Number of running pods per deployment
  - [ ] Service endpoints and health status
  - [ ] Current traffic patterns

### Database Backup

- [ ] **Create database backup before migration**
  ```bash
  # For Azure Database for PostgreSQL
  az postgres flexible-server backup create \
    --resource-group $DB_RESOURCE_GROUP \
    --name $DB_SERVER_NAME \
    --backup-name "pre-aro-migration-$(date +%Y%m%d)"
  ```

- [ ] **Verify backup completion and retention**

### Rollback Plan Documentation

- [ ] **DNS rollback procedure documented**
  - [ ] List of DNS records to update
  - [ ] TTL values for quick failback
  - [ ] Rollback time estimate

- [ ] **Traffic routing rollback plan**
  - [ ] Azure Traffic Manager / Front Door configuration
  - [ ] Application Gateway rules
  - [ ] Load balancer changes

- [ ] **Communication plan for rollback**
  - [ ] Stakeholder notification list
  - [ ] Escalation procedures
  - [ ] Success/failure criteria

---

## 10. Final Validation

### Pre-Migration Testing

- [ ] **Create test namespace in ARO**
  ```bash
  oc new-project migration-test
  ```

- [ ] **Deploy sample application to ARO**
  ```bash
  oc new-app --name test-app \
    --docker-image=$ACR_LOGIN_SERVER/sample-app:latest \
    --namespace=migration-test
  
  oc expose svc/test-app
  ```

- [ ] **Verify end-to-end connectivity**
  - [ ] Application starts successfully
  - [ ] Database connection established
  - [ ] Secrets loaded from Key Vault
  - [ ] External APIs accessible

### Monitoring and Observability

- [ ] **Configure ARO cluster monitoring**
  ```bash
  # Verify Prometheus and Grafana are available
  oc get routes -n openshift-monitoring
  ```

- [ ] **Set up Azure Monitor integration (optional)**
  ```bash
  # Install Azure Monitor agent
  # Refer to: https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-enable-arc-enabled-clusters
  ```

- [ ] **Configure log aggregation**
  - [ ] OpenShift cluster logging operator
  - [ ] Azure Log Analytics workspace

### Change Management

- [ ] **Migration runbook reviewed by team**

- [ ] **Migration window scheduled**
  - Migration date: _______________
  - Start time: _______________
  - Expected duration: _______________
  - Rollback deadline: _______________

- [ ] **Stakeholders notified**
  - [ ] Development team
  - [ ] Operations team
  - [ ] Business stakeholders
  - [ ] End users (if applicable)

- [ ] **Maintenance window announced**

### Final Checklist Review

- [ ] All items in sections 1-9 completed
- [ ] ARO cluster healthy and accessible
- [ ] Network connectivity validated
- [ ] Database access confirmed
- [ ] Container registry integration working
- [ ] Azure Key Vault accessible
- [ ] Application manifests converted and tested
- [ ] Backup and rollback plans in place
- [ ] Team alignment and readiness confirmed

---

## Next Steps

Once all checklist items are complete, proceed to the [Migration Runbook](02-MIGRATION-RUNBOOK.md) for detailed execution steps.

## Emergency Contacts

| Role | Name | Contact |
|------|------|---------|
| Migration Lead | _______________ | _______________ |
| Azure Administrator | _______________ | _______________ |
| Database Administrator | _______________ | _______________ |
| Application Owner | _______________ | _______________ |
| On-Call Engineer | _______________ | _______________ |

---

**Document Version**: 1.0  
**Last Updated**: 2026-06-02  
**Review Frequency**: Before each migration iteration
