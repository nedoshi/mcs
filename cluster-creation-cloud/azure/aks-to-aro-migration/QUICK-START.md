# Quick Start Guide - AKS to ARO Migration

## Prerequisites Checklist

Before you begin, ensure you have:

- [ ] Azure CLI installed and logged in (`az login`)
- [ ] `kubectl` CLI installed
- [ ] `oc` (OpenShift CLI) installed
- [ ] Access to both AKS and ARO clusters
- [ ] ARO cluster already provisioned
- [ ] Database firewall rules configured for ARO

## Environment Setup

```bash
# Set your environment variables
export SUBSCRIPTION_ID="<your-subscription-id>"
export AKS_CLUSTER_NAME="my-aks-cluster"
export AKS_RESOURCE_GROUP="aks-rg"
export AKS_NAMESPACE="production"
export ARO_CLUSTER_NAME="my-aro-cluster"
export ARO_RESOURCE_GROUP="aro-rg"
export ARO_NAMESPACE="production"
export ACR_NAME="mycontainerregistry"
export DB_SERVER_NAME="my-postgres-server"
export DB_RESOURCE_GROUP="database-rg"
export KEY_VAULT_NAME="my-keyvault"
export APP_NAME="sample-app"
export MIGRATION_DIR="$HOME/aks-to-aro-migration"

# Set Azure subscription
az account set --subscription $SUBSCRIPTION_ID
```

## Migration Steps (30-Minute Express Path)

### Step 1: Export AKS Resources (5 minutes)

```bash
cd aks-to-aro-migration
./scripts/01-export-aks-resources.sh
```

**What it does:**
- Exports deployments, services, ingresses, configmaps, secrets
- Documents current application state
- Creates backup of AKS configuration

**Output:** `$MIGRATION_DIR/exports/<timestamp>/`

---

### Step 2: Convert Manifests (10 minutes)

```bash
./scripts/02-convert-manifests.sh
```

**What it does:**
- Cleans Kubernetes metadata
- Creates templates for OpenShift Routes
- Generates SecretProviderClass for Azure Key Vault
- Adds security context configurations

**Output:** `$MIGRATION_DIR/manifests/converted/<timestamp>/`

**Manual steps required:**
1. Review `deployment-notes.txt` for security context requirements
2. Update `routes.yaml` with your specific hostnames and services
3. Choose secrets migration strategy (see `secrets-migration-guide.txt`)

---

### Step 3: Prepare ARO Environment (5 minutes)

```bash
# Login to ARO
ARO_API_URL=$(az aro show -g $ARO_RESOURCE_GROUP -n $ARO_CLUSTER_NAME --query "apiserverProfile.url" -o tsv)
ARO_PASSWORD=$(az aro list-credentials -g $ARO_RESOURCE_GROUP -n $ARO_CLUSTER_NAME --query "kubeadminPassword" -o tsv)

oc login $ARO_API_URL -u kubeadmin -p $ARO_PASSWORD

# Create namespace
oc new-project $ARO_NAMESPACE

# Create ACR pull secret (if using ACR)
export ACR_SP_APP_ID="<your-sp-app-id>"
export ACR_SP_PASSWORD="<your-sp-password>"

oc create secret docker-registry acr-pull-secret \
  --docker-server="${ACR_NAME}.azurecr.io" \
  --docker-username="$ACR_SP_APP_ID" \
  --docker-password="$ACR_SP_PASSWORD" \
  --namespace=$ARO_NAMESPACE
```

---

### Step 4: Deploy to ARO (5 minutes)

```bash
# Point to your converted manifests
export ARO_MANIFEST_DIR="$MIGRATION_DIR/manifests/aro"

# Deploy
./scripts/03-deploy-to-aro.sh
```

**What it does:**
- Creates service accounts
- Applies security context constraints
- Deploys ConfigMaps and Secrets
- Deploys application
- Creates Routes

**Expected output:**
- All pods running
- Services have endpoints
- Routes are created

---

### Step 5: Validate Deployment (5 minutes)

```bash
./scripts/04-validate-deployment.sh
```

**What it checks:**
- ✅ Cluster connectivity
- ✅ Namespace status
- ✅ Pod health
- ✅ Deployment status
- ✅ Service endpoints
- ✅ Route accessibility
- ✅ Resource usage

---

## Post-Migration Checklist

After successful deployment to ARO:

- [ ] All pods are running and ready
- [ ] Application responds to health checks
- [ ] Database connectivity verified
- [ ] Routes are accessible
- [ ] Monitoring configured
- [ ] DNS records updated (for production cutover)
- [ ] AKS application still running (for rollback if needed)

## Common Issues

### ImagePullBackOff
```bash
# Verify pull secret
oc get secret acr-pull-secret -n $ARO_NAMESPACE

# Link to service account
oc secrets link <service-account-name> acr-pull-secret --for=pull -n $ARO_NAMESPACE
```

### CrashLoopBackOff / SCC Violation
```bash
# Check SCC assignment
oc describe pod <pod-name> -n $ARO_NAMESPACE | grep scc

# Add required security context to deployment
```

### Database Connection Failed
```bash
# Test connectivity
oc run db-test --image=postgres:15 --rm -it --restart=Never -n $ARO_NAMESPACE -- \
  psql -h ${DB_SERVER_NAME}.postgres.database.azure.com -U <user> -d <dbname>

# Check firewall rules
az postgres flexible-server firewall-rule list -g $DB_RESOURCE_GROUP -n $DB_SERVER_NAME
```

### Route Not Accessible
```bash
# Check route status
oc get route -n $ARO_NAMESPACE

# Verify service has endpoints
oc get endpoints -n $ARO_NAMESPACE

# Check router logs
oc logs -n openshift-ingress <router-pod>
```

## Rollback Procedure

If you need to rollback to AKS:

```bash
# 1. Revert DNS to point back to AKS
# (Depends on your DNS provider)

# 2. Verify AKS is still running
kubectl config use-context ${AKS_CLUSTER_NAME}-admin
kubectl get pods -n $AKS_NAMESPACE

# 3. Scale up AKS if scaled down
kubectl scale deployment $APP_NAME -n $AKS_NAMESPACE --replicas=3
```

## Next Steps

1. **Review full documentation:**
   - [Pre-Migration Checklist](docs/01-PRE-MIGRATION-CHECKLIST.md)
   - [Detailed Migration Runbook](docs/02-MIGRATION-RUNBOOK.md)
   - [Troubleshooting Guide](docs/03-TROUBLESHOOTING.md)

2. **Production cutover:**
   - Plan maintenance window
   - Update DNS records
   - Monitor application health
   - Keep AKS running for 7-14 days for rollback

3. **Post-migration optimization:**
   - Set up monitoring and alerting
   - Configure autoscaling (HPA)
   - Implement OpenShift GitOps (ArgoCD)
   - Security hardening

## Support

- **Issues?** See [Troubleshooting Guide](docs/03-TROUBLESHOOTING.md)
- **Questions?** Review the [full documentation](README.md)
- **Bugs/Enhancements?** Open a GitHub issue

---

**Migration time:** ~30-60 minutes for express path  
**Production-ready time:** 2-3 hours with full validation
