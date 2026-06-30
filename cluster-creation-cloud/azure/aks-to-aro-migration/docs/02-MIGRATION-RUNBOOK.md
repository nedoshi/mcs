# AKS to ARO Migration Runbook

This runbook provides step-by-step execution instructions for migrating your application from Azure Kubernetes Service (AKS) to Azure Red Hat OpenShift (ARO). Follow each phase sequentially, validating success criteria before proceeding.

## Table of Contents

- [Overview](#overview)
- [Phase 1: Pre-Migration Validation](#phase-1-pre-migration-validation)
- [Phase 2: Export AKS Resources](#phase-2-export-aks-resources)
- [Phase 3: Convert Manifests for ARO](#phase-3-convert-manifests-for-aro)
- [Phase 4: Deploy to ARO Staging](#phase-4-deploy-to-aro-staging)
- [Phase 5: Production Cutover](#phase-5-production-cutover)
- [Phase 6: Post-Migration Validation](#phase-6-post-migration-validation)
- [Rollback Procedures](#rollback-procedures)

---

## Overview

### Migration Strategy

This runbook follows a **blue-green deployment** approach:

1. ARO cluster (green) is prepared while AKS (blue) continues serving production traffic
2. Application is deployed and validated on ARO
3. Traffic is switched from AKS to ARO
4. AKS cluster remains available for immediate rollback if needed

### Estimated Timeline

| Phase | Duration | Can Run in Parallel |
|-------|----------|---------------------|
| Phase 1: Pre-Migration Validation | 30 minutes | No |
| Phase 2: Export AKS Resources | 15 minutes | No |
| Phase 3: Convert Manifests | 30 minutes | No |
| Phase 4: Deploy to ARO Staging | 45 minutes | No |
| Phase 5: Production Cutover | 15 minutes | No |
| Phase 6: Post-Migration Validation | 30 minutes | No |
| **Total** | **2.5 - 3 hours** | |

### Prerequisites

Before starting, ensure:
- [ ] All items in [Pre-Migration Checklist](01-PRE-MIGRATION-CHECKLIST.md) are complete
- [ ] ARO cluster is provisioned and accessible
- [ ] Backup of AKS resources and database is completed
- [ ] Rollback plan is documented and reviewed
- [ ] All stakeholders are notified

### Environment Variables

Set these variables at the beginning of your migration session:

```bash
# Azure Subscription
export SUBSCRIPTION_ID="<your-subscription-id>"
az account set --subscription $SUBSCRIPTION_ID

# AKS Configuration
export AKS_CLUSTER_NAME="my-aks-cluster"
export AKS_RESOURCE_GROUP="aks-rg"
export AKS_NAMESPACE="production"

# ARO Configuration
export ARO_CLUSTER_NAME="my-aro-cluster"
export ARO_RESOURCE_GROUP="aro-rg"
export ARO_NAMESPACE="production"

# Database Configuration
export DB_SERVER_NAME="my-postgres-server"
export DB_RESOURCE_GROUP="database-rg"
export DB_NAME="appdb"

# Container Registry
export ACR_NAME="mycontainerregistry"
export ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"

# Azure Key Vault
export KEY_VAULT_NAME="my-keyvault"

# Application Configuration
export APP_NAME="sample-app"
export APP_VERSION="v1.2.3"

# Working Directory
export MIGRATION_DIR="$HOME/aks-to-aro-migration"
mkdir -p $MIGRATION_DIR/{exports,manifests,logs}
```

---

## Phase 1: Pre-Migration Validation

**Objective**: Verify all prerequisites and perform final health checks.

### Step 1.1: Verify AKS Cluster Access

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group $AKS_RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --admin \
  --overwrite-existing

# Verify connectivity
kubectl config use-context $AKS_CLUSTER_NAME-admin
kubectl get nodes
kubectl get pods -n $AKS_NAMESPACE
```

**Success Criteria**:
- ✅ All nodes in Ready state
- ✅ All application pods in Running state
- ✅ No pending or failed pods

### Step 1.2: Verify ARO Cluster Access

```bash
# Get ARO API URL and credentials
ARO_API_URL=$(az aro show \
  --resource-group $ARO_RESOURCE_GROUP \
  --name $ARO_CLUSTER_NAME \
  --query "apiserverProfile.url" -o tsv)

ARO_ADMIN_USER=$(az aro list-credentials \
  --resource-group $ARO_RESOURCE_GROUP \
  --name $ARO_CLUSTER_NAME \
  --query "kubeadminUsername" -o tsv)

ARO_ADMIN_PASSWORD=$(az aro list-credentials \
  --resource-group $ARO_RESOURCE_GROUP \
  --name $ARO_CLUSTER_NAME \
  --query "kubeadminPassword" -o tsv)

# Login to ARO
oc login $ARO_API_URL -u $ARO_ADMIN_USER -p $ARO_ADMIN_PASSWORD

# Verify cluster health
oc get nodes
oc get clusterversion
oc get co  # cluster operators
```

**Success Criteria**:
- ✅ All nodes in Ready state
- ✅ Cluster version shows desired OpenShift version
- ✅ All cluster operators available and not degraded

### Step 1.3: Verify Network Connectivity

```bash
# Test database connectivity from ARO
oc run db-test --image=postgres:15 --rm -it --restart=Never -- \
  bash -c "apt-get update && apt-get install -y postgresql-client && \
  psql -h ${DB_SERVER_NAME}.postgres.database.azure.com -U <db-admin-user> -d $DB_NAME -c 'SELECT version();'"

# Test ACR connectivity
oc run acr-test --image=${ACR_LOGIN_SERVER}/hello-world:latest --dry-run=client -o yaml
```

**Success Criteria**:
- ✅ Database connection successful
- ✅ ACR image pull works (or appropriate pull secret configured)

### Step 1.4: Verify Azure Key Vault Access

```bash
# Test Key Vault connectivity
az keyvault secret show \
  --vault-name $KEY_VAULT_NAME \
  --name db-connection-string \
  --query "value" -o tsv

# Verify CSI driver installation on ARO
oc get pods -n kube-system | grep csi
```

**Success Criteria**:
- ✅ Key Vault secrets accessible
- ✅ CSI driver pods running

### Step 1.5: Create ARO Namespace and RBAC

```bash
# Create namespace for application
oc new-project $ARO_NAMESPACE

# Create service account (if needed)
oc create serviceaccount ${APP_NAME}-sa -n $ARO_NAMESPACE

# Configure pull secret for ACR (if using pull secrets)
ACR_SP_APP_ID="<service-principal-app-id>"
ACR_SP_PASSWORD="<service-principal-password>"

oc create secret docker-registry acr-pull-secret \
  --docker-server=$ACR_LOGIN_SERVER \
  --docker-username=$ACR_SP_APP_ID \
  --docker-password=$ACR_SP_PASSWORD \
  --namespace=$ARO_NAMESPACE

# Link pull secret to service account
oc secrets link ${APP_NAME}-sa acr-pull-secret --for=pull -n $ARO_NAMESPACE
```

**Success Criteria**:
- ✅ Namespace created
- ✅ Service account created
- ✅ Pull secret configured and linked

---

## Phase 2: Export AKS Resources

**Objective**: Extract all application configurations, manifests, and settings from AKS.

### Step 2.1: Export Deployments

```bash
# Export all deployments in the namespace
kubectl get deployments -n $AKS_NAMESPACE -o yaml > $MIGRATION_DIR/exports/deployments.yaml

# Export specific deployment
kubectl get deployment $APP_NAME -n $AKS_NAMESPACE -o yaml > $MIGRATION_DIR/exports/${APP_NAME}-deployment.yaml
```

### Step 2.2: Export Services

```bash
# Export all services
kubectl get services -n $AKS_NAMESPACE -o yaml > $MIGRATION_DIR/exports/services.yaml

# Export specific service
kubectl get service $APP_NAME -n $AKS_NAMESPACE -o yaml > $MIGRATION_DIR/exports/${APP_NAME}-service.yaml
```

### Step 2.3: Export Ingress Resources

```bash
# Export all ingresses
kubectl get ingress -n $AKS_NAMESPACE -o yaml > $MIGRATION_DIR/exports/ingresses.yaml

# Export specific ingress
kubectl get ingress ${APP_NAME}-ingress -n $AKS_NAMESPACE -o yaml > $MIGRATION_DIR/exports/${APP_NAME}-ingress.yaml
```

### Step 2.4: Export ConfigMaps and Secrets

```bash
# Export ConfigMaps
kubectl get configmaps -n $AKS_NAMESPACE -o yaml > $MIGRATION_DIR/exports/configmaps.yaml

# Export Secrets (be careful with sensitive data)
kubectl get secrets -n $AKS_NAMESPACE -o yaml > $MIGRATION_DIR/exports/secrets.yaml

# Export specific ConfigMap
kubectl get configmap ${APP_NAME}-config -n $AKS_NAMESPACE -o yaml > $MIGRATION_DIR/exports/${APP_NAME}-configmap.yaml
```

**Note**: Ensure exported secrets are stored securely and not committed to version control.

### Step 2.5: Export Persistent Volume Claims (if applicable)

```bash
# Export PVCs
kubectl get pvc -n $AKS_NAMESPACE -o yaml > $MIGRATION_DIR/exports/pvcs.yaml
```

### Step 2.6: Document Current Application State

```bash
# Get current replica counts
kubectl get deployments -n $AKS_NAMESPACE -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.spec.replicas) replicas"' > $MIGRATION_DIR/logs/current-state.txt

# Get current image versions
kubectl get deployments -n $AKS_NAMESPACE -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.spec.template.spec.containers[0].image)"' >> $MIGRATION_DIR/logs/current-state.txt

# Get service endpoints
kubectl get endpoints -n $AKS_NAMESPACE -o wide >> $MIGRATION_DIR/logs/current-state.txt
```

**Success Criteria**:
- ✅ All deployments exported
- ✅ All services exported
- ✅ All ingresses exported
- ✅ All ConfigMaps and Secrets exported
- ✅ Current state documented

---

## Phase 3: Convert Manifests for ARO

**Objective**: Modify Kubernetes manifests for ARO/OpenShift compatibility.

### Step 3.1: Clean Up Kubernetes Metadata

```bash
# Remove cluster-specific metadata from exported manifests
# This script removes: status, uid, resourceVersion, creationTimestamp, etc.

cat > $MIGRATION_DIR/scripts/clean-manifest.sh << 'EOF'
#!/bin/bash
# Clean Kubernetes manifest for re-deployment

INPUT_FILE=$1
OUTPUT_FILE=$2

yq eval 'del(.metadata.uid,
           .metadata.resourceVersion,
           .metadata.creationTimestamp,
           .metadata.generation,
           .metadata.selfLink,
           .metadata.managedFields,
           .status)' $INPUT_FILE > $OUTPUT_FILE
EOF

chmod +x $MIGRATION_DIR/scripts/clean-manifest.sh

# Clean deployment manifest
$MIGRATION_DIR/scripts/clean-manifest.sh \
  $MIGRATION_DIR/exports/${APP_NAME}-deployment.yaml \
  $MIGRATION_DIR/manifests/${APP_NAME}-deployment-cleaned.yaml
```

### Step 3.2: Convert Ingress to OpenShift Route

Kubernetes Ingress resources need to be converted to OpenShift Routes.

**Example AKS Ingress**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sample-app-ingress
  namespace: production
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  tls:
  - hosts:
    - app.example.com
    secretName: tls-secret
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sample-app
            port:
              number: 80
```

**Equivalent ARO Route**:
```bash
cat > $MIGRATION_DIR/manifests/${APP_NAME}-route.yaml << EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${APP_NAME}
  namespace: ${ARO_NAMESPACE}
spec:
  host: app.example.com
  to:
    kind: Service
    name: ${APP_NAME}
    weight: 100
  port:
    targetPort: 8080
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
EOF
```

**Key Changes**:
- `Ingress` → `Route`
- `spec.rules` → `spec.to` (direct service reference)
- TLS configuration moved to `spec.tls`
- OpenShift Routes use edge, passthrough, or reencrypt termination

### Step 3.3: Update Deployment for Security Context Constraints

ARO uses Security Context Constraints (SCCs) which are stricter than Kubernetes Pod Security Standards.

```bash
# Create ARO-compatible deployment
cat > $MIGRATION_DIR/manifests/${APP_NAME}-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${ARO_NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
  replicas: 3
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      serviceAccountName: ${APP_NAME}-sa
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: ${APP_NAME}
        image: ${ACR_LOGIN_SERVER}/${APP_NAME}:${APP_VERSION}
        ports:
        - containerPort: 8080
          protocol: TCP
        env:
        - name: DATABASE_HOST
          value: "${DB_SERVER_NAME}.postgres.database.azure.com"
        - name: DATABASE_NAME
          value: "${DB_NAME}"
        - name: DATABASE_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
        - name: DATABASE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          runAsNonRoot: true
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
      imagePullSecrets:
      - name: acr-pull-secret
EOF
```

**Key Changes for ARO**:
- Added `runAsNonRoot: true`
- Added `allowPrivilegeEscalation: false`
- Dropped all capabilities with `capabilities.drop: [ALL]`
- Added `seccompProfile: RuntimeDefault`
- Specified `serviceAccountName`

### Step 3.4: Create Service Manifest

```bash
cat > $MIGRATION_DIR/manifests/${APP_NAME}-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${ARO_NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
  type: ClusterIP
  selector:
    app: ${APP_NAME}
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
    name: http
EOF
```

### Step 3.5: Create ConfigMap

```bash
cat > $MIGRATION_DIR/manifests/${APP_NAME}-configmap.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${APP_NAME}-config
  namespace: ${ARO_NAMESPACE}
data:
  APP_ENV: "production"
  LOG_LEVEL: "info"
  API_TIMEOUT: "30"
EOF
```

### Step 3.6: Create Secret for Database Credentials

```bash
# Option 1: Create from Key Vault values
DB_USERNAME=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name db-username --query value -o tsv)
DB_PASSWORD=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name db-password --query value -o tsv)

oc create secret generic db-credentials \
  --from-literal=username=$DB_USERNAME \
  --from-literal=password=$DB_PASSWORD \
  --namespace=$ARO_NAMESPACE \
  --dry-run=client -o yaml > $MIGRATION_DIR/manifests/db-credentials-secret.yaml

# Option 2: Use Azure Key Vault CSI Driver (recommended)
cat > $MIGRATION_DIR/manifests/secretproviderclass.yaml << EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-keyvault-${APP_NAME}
  namespace: ${ARO_NAMESPACE}
spec:
  provider: azure
  secretObjects:
  - secretName: db-credentials
    type: Opaque
    data:
    - objectName: db-username
      key: username
    - objectName: db-password
      key: password
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "<service-principal-client-id>"
    keyvaultName: "${KEY_VAULT_NAME}"
    tenantId: "<tenant-id>"
    objects: |
      array:
        - |
          objectName: db-username
          objectType: secret
        - |
          objectName: db-password
          objectType: secret
EOF
```

### Step 3.7: Handle Security Context Constraints

If your application requires privileges beyond the default `restricted` SCC:

```bash
# Option 1: Use a less restrictive SCC (evaluate carefully)
oc adm policy add-scc-to-user anyuid -z ${APP_NAME}-sa -n $ARO_NAMESPACE

# Option 2: Create custom SCC (for specific needs)
cat > $MIGRATION_DIR/manifests/custom-scc.yaml << EOF
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: ${APP_NAME}-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegedContainer: false
allowedCapabilities: []
defaultAddCapabilities: []
fsGroup:
  type: MustRunAs
  ranges:
  - min: 1000
    max: 65535
readOnlyRootFilesystem: false
requiredDropCapabilities:
- ALL
runAsUser:
  type: MustRunAsNonRoot
seLinuxContext:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
EOF

# Apply and grant to service account
oc apply -f $MIGRATION_DIR/manifests/custom-scc.yaml
oc adm policy add-scc-to-user ${APP_NAME}-scc -z ${APP_NAME}-sa -n $ARO_NAMESPACE
```

**Success Criteria**:
- ✅ All manifests cleaned and ready for ARO
- ✅ Ingress converted to Route
- ✅ Deployment updated with proper security contexts
- ✅ Service, ConfigMap, and Secrets prepared
- ✅ SCC requirements identified and configured

---

## Phase 4: Deploy to ARO Staging

**Objective**: Deploy application to ARO and validate functionality before production cutover.

### Step 4.1: Create Staging Namespace (Optional)

```bash
# Create staging namespace for pre-production testing
export ARO_STAGING_NAMESPACE="staging"
oc new-project $ARO_STAGING_NAMESPACE
```

### Step 4.2: Apply Manifests to ARO

```bash
# Switch to ARO context
oc config use-context $ARO_CLUSTER_NAME

# Apply in order: namespace, service account, secrets, configmap, deployment, service, route

# 1. Service Account
oc apply -f - << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_NAME}-sa
  namespace: ${ARO_NAMESPACE}
EOF

# 2. Link pull secret
oc secrets link ${APP_NAME}-sa acr-pull-secret --for=pull -n $ARO_NAMESPACE

# 3. ConfigMap
oc apply -f $MIGRATION_DIR/manifests/${APP_NAME}-configmap.yaml

# 4. Secrets (if using plain secrets, not CSI)
oc apply -f $MIGRATION_DIR/manifests/db-credentials-secret.yaml

# 5. SecretProviderClass (if using Azure Key Vault CSI)
oc apply -f $MIGRATION_DIR/manifests/secretproviderclass.yaml

# 6. Deployment
oc apply -f $MIGRATION_DIR/manifests/${APP_NAME}-deployment.yaml

# 7. Service
oc apply -f $MIGRATION_DIR/manifests/${APP_NAME}-service.yaml

# 8. Route
oc apply -f $MIGRATION_DIR/manifests/${APP_NAME}-route.yaml
```

### Step 4.3: Monitor Deployment Progress

```bash
# Watch deployment rollout
oc rollout status deployment/${APP_NAME} -n $ARO_NAMESPACE

# Check pod status
oc get pods -n $ARO_NAMESPACE -l app=${APP_NAME}

# View pod logs
oc logs -f deployment/${APP_NAME} -n $ARO_NAMESPACE

# Check events for issues
oc get events -n $ARO_NAMESPACE --sort-by='.lastTimestamp'
```

### Step 4.4: Troubleshoot Common Issues

**Issue: ImagePullBackOff**
```bash
# Check pull secret
oc get secret acr-pull-secret -n $ARO_NAMESPACE -o yaml

# Verify service account has pull secret linked
oc describe sa ${APP_NAME}-sa -n $ARO_NAMESPACE

# Test manual image pull
oc run test-pull --image=${ACR_LOGIN_SERVER}/${APP_NAME}:${APP_VERSION} \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"acr-pull-secret"}]}}' \
  -n $ARO_NAMESPACE
```

**Issue: CrashLoopBackOff or SCC Violation**
```bash
# Check pod security context
oc get pod <pod-name> -n $ARO_NAMESPACE -o yaml | grep -A 20 securityContext

# View SCC assigned to pod
oc describe pod <pod-name> -n $ARO_NAMESPACE | grep scc

# Check SCC for service account
oc get scc --as=system:serviceaccount:${ARO_NAMESPACE}:${APP_NAME}-sa
```

**Issue: Database Connection Failed**
```bash
# Check database connectivity from pod
oc exec -it deployment/${APP_NAME} -n $ARO_NAMESPACE -- \
  sh -c 'nc -zv $DATABASE_HOST 5432'

# Verify environment variables
oc exec deployment/${APP_NAME} -n $ARO_NAMESPACE -- env | grep DATABASE

# Check secret mounting
oc describe pod <pod-name> -n $ARO_NAMESPACE | grep -A 5 Mounts
```

### Step 4.5: Verify Application Health

```bash
# Check deployment status
oc get deployment ${APP_NAME} -n $ARO_NAMESPACE

# Verify all replicas are ready
REPLICAS=$(oc get deployment ${APP_NAME} -n $ARO_NAMESPACE -o jsonpath='{.spec.replicas}')
READY=$(oc get deployment ${APP_NAME} -n $ARO_NAMESPACE -o jsonpath='{.status.readyReplicas}')

if [ "$REPLICAS" == "$READY" ]; then
  echo "✅ All replicas ready: $READY/$REPLICAS"
else
  echo "❌ Not all replicas ready: $READY/$REPLICAS"
fi

# Check service endpoints
oc get endpoints ${APP_NAME} -n $ARO_NAMESPACE

# Get route URL
ROUTE_URL=$(oc get route ${APP_NAME} -n $ARO_NAMESPACE -o jsonpath='{.spec.host}')
echo "Application URL: https://$ROUTE_URL"
```

### Step 4.6: Test Application Functionality

```bash
# Test HTTP endpoint (if route is accessible)
curl -k https://$ROUTE_URL/health

# Port-forward for local testing (if route not public yet)
oc port-forward service/${APP_NAME} 8080:80 -n $ARO_NAMESPACE &
curl http://localhost:8080/health

# Test database connectivity through application
curl -k https://$ROUTE_URL/api/db-status

# Check application logs for errors
oc logs -l app=${APP_NAME} -n $ARO_NAMESPACE --tail=100 | grep -i error
```

**Success Criteria**:
- ✅ All pods running and ready
- ✅ Service has endpoints
- ✅ Route is created and accessible
- ✅ Application health checks passing
- ✅ Database connectivity confirmed
- ✅ No errors in application logs

---

## Phase 5: Production Cutover

**Objective**: Switch production traffic from AKS to ARO.

### Step 5.1: Final Pre-Cutover Validation

```bash
# Verify ARO application is fully functional
oc get all -n $ARO_NAMESPACE

# Check metrics and resource usage
oc adm top pods -n $ARO_NAMESPACE

# Ensure database connection pool is stable
oc logs deployment/${APP_NAME} -n $ARO_NAMESPACE --tail=50 | grep -i "database\|connection"

# Verify monitoring and alerting
oc get routes -n openshift-monitoring
```

### Step 5.2: Update DNS Records

This step depends on your DNS provider. Common scenarios:

**Scenario A: Azure Traffic Manager**
```bash
# Update Traffic Manager endpoint
az network traffic-manager endpoint update \
  --resource-group <traffic-manager-rg> \
  --profile-name <profile-name> \
  --name aro-endpoint \
  --type azureEndpoints \
  --target-resource-id $(az network public-ip show \
    --resource-group <aro-lb-rg> \
    --name <aro-lb-ip> \
    --query id -o tsv) \
  --endpoint-status Enabled

# Disable AKS endpoint (after validation)
az network traffic-manager endpoint update \
  --resource-group <traffic-manager-rg> \
  --profile-name <profile-name> \
  --name aks-endpoint \
  --endpoint-status Disabled
```

**Scenario B: Azure DNS Zone**
```bash
# Get ARO route IP/hostname
ARO_ROUTE_HOST=$(oc get route ${APP_NAME} -n $ARO_NAMESPACE -o jsonpath='{.spec.host}')
ARO_ROUTE_TARGET=$(oc get route ${APP_NAME} -n $ARO_NAMESPACE -o jsonpath='{.status.ingress[0].routerCanonicalHostname}')

# Update A record or CNAME
az network dns record-set cname set-record \
  --resource-group <dns-rg> \
  --zone-name example.com \
  --record-set-name app \
  --cname $ARO_ROUTE_TARGET \
  --ttl 300
```

**Scenario C: Manual DNS Update**
```bash
# Note the ARO route target for manual DNS update
echo "Update your DNS provider to point app.example.com to:"
echo "CNAME: $ARO_ROUTE_TARGET"
echo "or use the IP address from:"
oc get route ${APP_NAME} -n $ARO_NAMESPACE
```

### Step 5.3: Gradual Traffic Shift (Optional)

For zero-downtime migration, use a gradual traffic shift:

```bash
# Using Azure Front Door or Traffic Manager with weighted routing
# Start with 10% traffic to ARO
az network traffic-manager endpoint update \
  --resource-group <tm-rg> \
  --profile-name <profile-name> \
  --name aro-endpoint \
  --weight 10

az network traffic-manager endpoint update \
  --resource-group <tm-rg> \
  --profile-name <profile-name> \
  --name aks-endpoint \
  --weight 90

# Monitor for 15 minutes, then increase to 50%
# Then 100% after validation
```

### Step 5.4: Monitor Cutover

```bash
# Monitor ARO pod logs
oc logs -f deployment/${APP_NAME} -n $ARO_NAMESPACE

# Watch pod resource usage
watch oc adm top pods -n $ARO_NAMESPACE

# Check for errors
oc logs deployment/${APP_NAME} -n $ARO_NAMESPACE --since=10m | grep -i "error\|exception\|fatal"

# Monitor request rate increase
# Use OpenShift monitoring or Azure Monitor
```

### Step 5.5: Verify Production Traffic

```bash
# Test application from external client
curl -I https://app.example.com

# Verify response headers show ARO routing
curl -v https://app.example.com 2>&1 | grep -i "x-forwarded\|server"

# Check database connection count increase
# Connect to database and run:
# SELECT count(*) FROM pg_stat_activity WHERE application_name = 'sample-app';

# Validate end-to-end transaction
curl -X POST https://app.example.com/api/test-transaction \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

**Success Criteria**:
- ✅ DNS resolves to ARO route
- ✅ Application responding to external requests
- ✅ Database queries succeeding
- ✅ No increase in error rate
- ✅ Response times within acceptable range

---

## Phase 6: Post-Migration Validation

**Objective**: Confirm system stability and prepare for AKS decommissioning.

### Step 6.1: Comprehensive Health Check

```bash
# Application health
oc get deployment ${APP_NAME} -n $ARO_NAMESPACE -o wide

# All pods healthy
oc get pods -n $ARO_NAMESPACE -l app=${APP_NAME}

# Service endpoints populated
oc get endpoints ${APP_NAME} -n $ARO_NAMESPACE

# Route accessible
oc get route ${APP_NAME} -n $ARO_NAMESPACE

# Check resource utilization
oc adm top pods -n $ARO_NAMESPACE
oc adm top nodes
```

### Step 6.2: Verify Monitoring and Alerting

```bash
# Access OpenShift monitoring
oc get routes -n openshift-monitoring

# Check Prometheus targets
# Navigate to Prometheus UI and verify application metrics are being scraped

# Verify alerts are configured
oc get prometheusrules -n $ARO_NAMESPACE

# Test alert firing (optional)
```

### Step 6.3: Run End-to-End Tests

```bash
# Run automated test suite
# Example using a test job:
oc create job ${APP_NAME}-e2e-test --image=${ACR_LOGIN_SERVER}/${APP_NAME}-tests:latest -n $ARO_NAMESPACE

# Monitor test job
oc logs -f job/${APP_NAME}-e2e-test -n $ARO_NAMESPACE

# Check test results
oc get job ${APP_NAME}-e2e-test -n $ARO_NAMESPACE
```

### Step 6.4: Performance Validation

```bash
# Run load test (example with Apache Bench)
ab -n 1000 -c 10 https://app.example.com/api/endpoint

# Or use K6, JMeter, etc.
# Monitor pod autoscaling (if HPA configured)
oc get hpa -n $ARO_NAMESPACE

# Check cluster resource headroom
oc adm top nodes
```

### Step 6.5: Document Migration Completion

```bash
# Capture final state
cat > $MIGRATION_DIR/logs/migration-summary.txt << EOF
Migration Completed: $(date)
ARO Cluster: $ARO_CLUSTER_NAME
Namespace: $ARO_NAMESPACE
Application: $APP_NAME
Version: $APP_VERSION

Deployment Status:
$(oc get deployment ${APP_NAME} -n $ARO_NAMESPACE)

Pods:
$(oc get pods -n $ARO_NAMESPACE -l app=${APP_NAME})

Route:
$(oc get route ${APP_NAME} -n $ARO_NAMESPACE)

DNS: app.example.com -> ARO
Database: Connected via $(oc get pods -n $ARO_NAMESPACE -o jsonpath='{.items[0].spec.containers[0].env[?(@.name=="DATABASE_HOST")].value}')

Issues Encountered: None (or list issues)
Rollback Required: No
EOF

cat $MIGRATION_DIR/logs/migration-summary.txt
```

### Step 6.6: AKS Decommissioning Plan

**Do NOT delete AKS immediately.** Keep for rollback window (typically 7-14 days).

```bash
# Scale down AKS deployment (after 24-48 hours of stable ARO operation)
kubectl scale deployment ${APP_NAME} -n $AKS_NAMESPACE --replicas=0

# Monitor for 7-14 days before full decommission

# After successful validation period:
# 1. Remove DNS entries pointing to AKS
# 2. Delete AKS application resources
# 3. Schedule AKS cluster decommissioning with stakeholders
```

**Success Criteria**:
- ✅ Application stable for 24+ hours on ARO
- ✅ No critical incidents
- ✅ Performance meets SLAs
- ✅ Monitoring and alerting operational
- ✅ Backup and disaster recovery verified
- ✅ Team trained on ARO operations

---

## Rollback Procedures

### When to Rollback

Trigger rollback if:
- Critical application errors after cutover
- Database connectivity issues
- Unacceptable performance degradation
- Security vulnerabilities discovered
- Stakeholder decision to abort

### Rollback Steps

#### Immediate Rollback (within 1 hour of cutover)

```bash
# 1. Revert DNS to AKS
az network dns record-set cname set-record \
  --resource-group <dns-rg> \
  --zone-name example.com \
  --record-set-name app \
  --cname <aks-original-target> \
  --ttl 300

# 2. Verify AKS application is still running
kubectl config use-context $AKS_CLUSTER_NAME-admin
kubectl get pods -n $AKS_NAMESPACE

# 3. If AKS was scaled down, scale back up
kubectl scale deployment ${APP_NAME} -n $AKS_NAMESPACE --replicas=3

# 4. Verify AKS health
kubectl get deployment ${APP_NAME} -n $AKS_NAMESPACE
curl -I https://app.example.com  # After DNS propagates
```

#### Delayed Rollback (after 1+ hour)

If DNS TTL has not expired yet, you may need to wait or use Traffic Manager immediate switch.

```bash
# Using Azure Traffic Manager for immediate switch
az network traffic-manager endpoint update \
  --resource-group <tm-rg> \
  --profile-name <profile-name> \
  --name aks-endpoint \
  --endpoint-status Enabled

az network traffic-manager endpoint update \
  --resource-group <tm-rg> \
  --profile-name <profile-name> \
  --name aro-endpoint \
  --endpoint-status Disabled
```

### Post-Rollback Actions

```bash
# 1. Investigate root cause on ARO
oc logs deployment/${APP_NAME} -n $ARO_NAMESPACE --since=2h > $MIGRATION_DIR/logs/rollback-logs.txt

# 2. Document rollback reason
echo "Rollback performed at $(date). Reason: <fill in>" >> $MIGRATION_DIR/logs/migration-summary.txt

# 3. Plan remediation and retry
```

---

## Post-Migration Checklist

- [ ] Application running stable on ARO for 24+ hours
- [ ] All monitoring and alerts configured
- [ ] Performance validated and within SLAs
- [ ] End-to-end tests passing
- [ ] Team trained on ARO operations
- [ ] Documentation updated (runbooks, architecture diagrams)
- [ ] AKS scaled down or scheduled for decommission
- [ ] Stakeholders notified of successful migration
- [ ] Post-mortem conducted (lessons learned)
- [ ] Cost analysis completed

---

## Next Steps

- Review [Post-Migration Guide](05-POST-MIGRATION.md) for optimization
- Set up continuous monitoring and alerting
- Plan for AKS cluster decommissioning
- Document lessons learned

## Support

For issues during migration:
- Review [Troubleshooting Guide](03-TROUBLESHOOTING.md)
- Contact migration lead or on-call engineer
- Escalate to Red Hat support if ARO-specific issues

---

**Runbook Version**: 1.0  
**Last Updated**: 2026-06-02  
**Tested On**: ARO 4.13, AKS 1.28
