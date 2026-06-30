# Troubleshooting Guide

Common issues encountered during AKS to ARO migration and their solutions.

## Table of Contents

- [Container Image Pull Issues](#container-image-pull-issues)
- [Security Context Constraints Violations](#security-context-constraints-violations)
- [Database Connectivity Issues](#database-connectivity-issues)
- [Route and Networking Issues](#route-and-networking-issues)
- [Azure Key Vault Integration Issues](#azure-key-vault-integration-issues)
- [Pod Crashes and Restarts](#pod-crashes-and-restarts)
- [Performance Issues](#performance-issues)

---

## Container Image Pull Issues

### Problem: ImagePullBackOff Error

**Symptoms:**
```bash
oc get pods -n production
# NAME                          READY   STATUS             RESTARTS   AGE
# sample-app-7d5c4b9f8d-abc12   0/1     ImagePullBackOff   0          2m
```

**Diagnosis:**
```bash
# Check pod events
oc describe pod <pod-name> -n production | grep -A 10 Events

# Common error messages:
# - "unauthorized: authentication required"
# - "image not found"
# - "pull access denied"
```

**Solutions:**

1. **Verify ACR pull secret exists:**
   ```bash
   oc get secret acr-pull-secret -n production
   ```

2. **Recreate pull secret:**
   ```bash
   export ACR_NAME="mycontainerregistry"
   export ACR_SP_APP_ID="<service-principal-app-id>"
   export ACR_SP_PASSWORD="<service-principal-password>"

   oc delete secret acr-pull-secret -n production --ignore-not-found
   oc create secret docker-registry acr-pull-secret \
     --docker-server="${ACR_NAME}.azurecr.io" \
     --docker-username="$ACR_SP_APP_ID" \
     --docker-password="$ACR_SP_PASSWORD" \
     --namespace=production
   ```

3. **Link secret to service account:**
   ```bash
   oc secrets link <service-account-name> acr-pull-secret --for=pull -n production
   ```

4. **Verify deployment references pull secret:**
   ```bash
   oc get deployment <deployment-name> -n production -o yaml | grep imagePullSecrets -A 2
   ```

5. **Check ACR firewall rules:**
   ```bash
   # Get ARO worker subnet
   WORKER_SUBNET=$(az aro show -g <aro-rg> -n <aro-cluster> --query 'workerProfiles[0].subnetId' -o tsv)

   # Check ACR network rules
   az acr network-rule list --name $ACR_NAME

   # Add ARO subnet to ACR firewall (if needed)
   az acr network-rule add --name $ACR_NAME --subnet $WORKER_SUBNET
   ```

---

## Security Context Constraints Violations

### Problem: Pod Creation Blocked by SCC

**Symptoms:**
```bash
# Pod stuck in Pending or Creating state
oc get pods -n production
# NAME                          READY   STATUS    RESTARTS   AGE
# sample-app-7d5c4b9f8d-abc12   0/1     Pending   0          5m
```

**Diagnosis:**
```bash
# Check pod events for SCC errors
oc describe pod <pod-name> -n production | grep -i "scc\|security"

# Common error:
# "unable to validate against any security context constraint"
# "does not match required level"
```

**Solutions:**

1. **Check which SCC is assigned:**
   ```bash
   oc describe pod <pod-name> -n production | grep "openshift.io/scc"
   ```

2. **Review deployment security context:**
   ```bash
   oc get deployment <deployment-name> -n production -o yaml | grep -A 20 securityContext
   ```

3. **Fix: Add proper security context to deployment:**
   ```yaml
   spec:
     template:
       spec:
         securityContext:
           runAsNonRoot: true
           seccompProfile:
             type: RuntimeDefault
         containers:
         - name: app
           securityContext:
             allowPrivilegeEscalation: false
             runAsNonRoot: true
             capabilities:
               drop:
               - ALL
   ```

4. **Apply the fix:**
   ```bash
   oc apply -f deployment.yaml
   ```

5. **If app requires specific privileges, create custom SCC:**
   ```bash
   # Apply custom SCC
   oc apply -f custom-scc.yaml

   # Grant SCC to service account
   oc adm policy add-scc-to-user <scc-name> -z <service-account> -n production
   ```

6. **Verify SCC assignment:**
   ```bash
   oc get scc --as=system:serviceaccount:production:<service-account-name>
   ```

---

## Database Connectivity Issues

### Problem: Application Cannot Connect to Azure Database

**Symptoms:**
- Application logs show database connection errors
- Connection timeouts
- Authentication failures

**Diagnosis:**
```bash
# Check application logs
oc logs deployment/<deployment-name> -n production | grep -i "database\|connection"

# Test database connectivity from pod
oc run db-test --image=postgres:15 --rm -it --restart=Never -n production -- \
  bash -c "psql -h <db-host> -U <db-user> -d <db-name> -c 'SELECT version();'"
```

**Solutions:**

1. **Check database firewall rules:**
   ```bash
   # Get ARO worker subnet CIDR
   WORKER_SUBNET_CIDR=$(az network vnet subnet show \
     --resource-group <aro-rg> \
     --vnet-name <vnet-name> \
     --name worker-subnet \
     --query addressPrefix -o tsv)

   # List current firewall rules
   az postgres flexible-server firewall-rule list \
     --resource-group <db-rg> \
     --name <db-server-name> \
     --output table

   # Add firewall rule for ARO subnet
   az postgres flexible-server firewall-rule create \
     --resource-group <db-rg> \
     --name <db-server-name> \
     --rule-name "aro-worker-subnet" \
     --start-ip-address $(echo $WORKER_SUBNET_CIDR | cut -d'/' -f1) \
     --end-ip-address <calculate-end-ip>
   ```

2. **Verify connection string in environment variables:**
   ```bash
   oc exec deployment/<deployment-name> -n production -- env | grep DATABASE
   ```

3. **Check secret values:**
   ```bash
   # For regular secrets
   oc get secret db-credentials -n production -o jsonpath='{.data.username}' | base64 -d
   oc get secret db-credentials -n production -o jsonpath='{.data.password}' | base64 -d

   # For Azure Key Vault CSI
   oc describe secretproviderclass azure-keyvault-<app> -n production
   ```

4. **Test DNS resolution:**
   ```bash
   oc debug node/<node-name>
   chroot /host
   nslookup <db-host>.postgres.database.azure.com
   ```

5. **Enable SSL/TLS for PostgreSQL:**
   ```yaml
   env:
   - name: DATABASE_SSL
     value: "require"
   - name: PGSSLMODE
     value: "require"
   ```

6. **Use Private Endpoint (recommended):**
   ```bash
   # Create private endpoint for database
   az network private-endpoint create \
     --resource-group <aro-rg> \
     --name postgres-private-endpoint \
     --vnet-name <vnet-name> \
     --subnet worker-subnet \
     --private-connection-resource-id <db-resource-id> \
     --group-id postgresqlServer \
     --connection-name postgres-connection
   ```

---

## Route and Networking Issues

### Problem: Route Not Accessible

**Symptoms:**
- External users cannot access application URL
- `curl` to route returns connection timeout or 503

**Diagnosis:**
```bash
# Check route status
oc get route <route-name> -n production -o yaml

# Check route ingress status
oc get route <route-name> -n production -o jsonpath='{.status.ingress[0]}'

# Test from within cluster
oc run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -v http://<service-name>.<namespace>.svc.cluster.local
```

**Solutions:**

1. **Verify service has endpoints:**
   ```bash
   oc get endpoints <service-name> -n production
   ```

2. **Check route target:**
   ```bash
   oc get route <route-name> -n production -o yaml | grep -A 5 "spec:"
   ```

3. **Verify TLS configuration:**
   ```yaml
   apiVersion: route.openshift.io/v1
   kind: Route
   metadata:
     name: sample-app
   spec:
     tls:
       termination: edge
       insecureEdgeTerminationPolicy: Redirect
   ```

4. **Check router pods:**
   ```bash
   oc get pods -n openshift-ingress
   oc logs <router-pod> -n openshift-ingress
   ```

5. **Verify DNS resolution:**
   ```bash
   nslookup <route-hostname>
   dig <route-hostname>
   ```

6. **Update DNS records to point to ARO:**
   ```bash
   # Get route canonical hostname
   ROUTE_TARGET=$(oc get route <route-name> -n production \
     -o jsonpath='{.status.ingress[0].routerCanonicalHostname}')

   # Update DNS CNAME record to point to $ROUTE_TARGET
   ```

---

## Azure Key Vault Integration Issues

### Problem: Secrets Not Loading from Key Vault

**Symptoms:**
- Pods fail to start or restart frequently
- Mount errors in pod events
- Environment variables empty

**Diagnosis:**
```bash
# Check SecretProviderClass
oc get secretproviderclass -n production
oc describe secretproviderclass <spc-name> -n production

# Check pod events
oc describe pod <pod-name> -n production | grep -A 10 "csi\|secret"

# Check CSI driver pods
oc get pods -n kube-system | grep secrets-store-csi
oc get pods -n kube-system | grep provider-azure
```

**Solutions:**

1. **Verify CSI driver installation:**
   ```bash
   # Check driver pods running
   oc get pods -n kube-system | grep csi

   # If not installed, install CSI driver
   oc apply -f https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy/secrets-store-csi-driver.yaml
   oc apply -f https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/deployment/provider-azure-installer.yaml
   ```

2. **Check Key Vault access permissions:**
   ```bash
   # Get ARO service principal
   ARO_SP=$(az aro show -g <aro-rg> -n <aro-cluster> --query servicePrincipalProfile.clientId -o tsv)

   # Grant Key Vault permissions
   az keyvault set-policy \
     --name <key-vault-name> \
     --object-id $(az ad sp show --id $ARO_SP --query id -o tsv) \
     --secret-permissions get list
   ```

3. **Verify SecretProviderClass configuration:**
   ```yaml
   spec:
     provider: azure
     parameters:
       usePodIdentity: "false"
       useVMManagedIdentity: "true"
       userAssignedIdentityID: "<correct-client-id>"
       keyvaultName: "<correct-vault-name>"
       tenantId: "<correct-tenant-id>"
   ```

4. **Check volume mount in pod:**
   ```bash
   oc get pod <pod-name> -n production -o yaml | grep -A 10 "volumeMounts:\|volumes:"
   ```

5. **Test manual secret retrieval:**
   ```bash
   az keyvault secret show --vault-name <vault-name> --name <secret-name>
   ```

---

## Pod Crashes and Restarts

### Problem: Pods Continuously Restarting

**Symptoms:**
```bash
oc get pods -n production
# NAME                          READY   STATUS             RESTARTS   AGE
# sample-app-7d5c4b9f8d-abc12   0/1     CrashLoopBackOff   5          10m
```

**Diagnosis:**
```bash
# Check pod logs
oc logs <pod-name> -n production --previous

# Check restart count and reason
oc describe pod <pod-name> -n production | grep -A 20 "State:\|Last State:"

# Check resource limits
oc describe pod <pod-name> -n production | grep -A 10 "Limits:\|Requests:"
```

**Solutions:**

1. **Application errors - check logs:**
   ```bash
   oc logs deployment/<deployment-name> -n production --tail=100
   ```

2. **Liveness probe failing:**
   ```bash
   # Check probe configuration
   oc get deployment <deployment-name> -n production -o yaml | grep -A 5 livenessProbe

   # Increase initialDelaySeconds if app takes time to start
   livenessProbe:
     initialDelaySeconds: 60  # Increase from 30
     periodSeconds: 10
   ```

3. **Out of Memory (OOM) kills:**
   ```bash
   # Check if OOMKilled
   oc describe pod <pod-name> -n production | grep -i "oom\|memory"

   # Increase memory limits
   resources:
     limits:
       memory: "1Gi"  # Increase from 512Mi
   ```

4. **Missing environment variables:**
   ```bash
   oc exec deployment/<deployment-name> -n production -- env
   ```

5. **Debug with temporary pod:**
   ```bash
   oc debug deployment/<deployment-name> -n production
   ```

---

## Performance Issues

### Problem: Slow Response Times

**Diagnosis:**
```bash
# Check pod resource usage
oc adm top pods -n production

# Check node resource usage
oc adm top nodes

# Check pod limits
oc describe pod <pod-name> -n production | grep -A 10 Limits

# Application-level profiling (if available)
oc port-forward deployment/<deployment-name> 8080:8080 -n production
# Access profiling endpoint: http://localhost:8080/metrics
```

**Solutions:**

1. **Increase resource limits:**
   ```yaml
   resources:
     requests:
       memory: "512Mi"
       cpu: "500m"
     limits:
       memory: "1Gi"
       cpu: "1000m"
   ```

2. **Enable Horizontal Pod Autoscaler:**
   ```bash
   oc autoscale deployment <deployment-name> \
     --min=3 \
     --max=10 \
     --cpu-percent=70 \
     -n production
   ```

3. **Optimize database queries:**
   - Add connection pooling
   - Enable query caching
   - Review slow query logs

4. **Enable CDN or caching layer:**
   - Use Azure CDN for static assets
   - Implement Redis for application caching

---

## Getting More Help

### Collect Diagnostic Information

```bash
# Create diagnostics bundle
mkdir -p diagnostics/$(date +%Y%m%d)

# Export all resources
oc get all -n production -o yaml > diagnostics/$(date +%Y%m%d)/all-resources.yaml

# Export events
oc get events -n production --sort-by='.lastTimestamp' > diagnostics/$(date +%Y%m%d)/events.txt

# Export logs for all pods
for pod in $(oc get pods -n production -o name); do
  oc logs $pod -n production > diagnostics/$(date +%Y%m%d)/${pod}-logs.txt 2>&1
done

# Export node information
oc get nodes -o wide > diagnostics/$(date +%Y%m%d)/nodes.txt
oc adm top nodes > diagnostics/$(date +%Y%m%d)/node-resources.txt
```

### Contact Support

- **Red Hat Support**: [https://access.redhat.com/support](https://access.redhat.com/support)
- **Azure Support**: [https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade](https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade)
- **OpenShift Community**: [https://community.openshift.com/](https://community.openshift.com/)

---

**Last Updated**: 2026-06-02
