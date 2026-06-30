# ARO Red Hat Operators Catalog Troubleshooting Guide

Complete step-by-step guide for troubleshooting Red Hat Operators catalog connection issues in Azure Red Hat OpenShift (ARO).

---

## Table of Contents
1. [Initial Assessment](#1-initial-assessment)
2. [Pod Status and Logs](#2-pod-status-and-logs)
3. [Image Pull Issues](#3-image-pull-issues)
4. [Network Connectivity Issues](#4-network-connectivity-issues)
5. [DNS Resolution Issues](#5-dns-resolution-issues)
6. [Proxy Configuration](#6-proxy-configuration)
7. [Firewall and NSG Rules](#7-firewall-and-nsg-rules)
8. [Azure-Specific Issues](#8-azure-specific-issues)
9. [CatalogSource Rebuild](#9-catalogsource-rebuild)
10. [Monitoring and Verification](#10-monitoring-and-verification)

---

## 1. Initial Assessment

### 1.1 Check Catalog Source Status
```bash
oc get catalogsource -n openshift-marketplace
```

**Expected Output:**
```
NAME               DISPLAY            TYPE   PUBLISHER   AGE
redhat-operators   Red Hat Operators  grpc   Red Hat     10d
```

### 1.2 Describe Catalog Source
```bash
oc describe catalogsource redhat-operators -n openshift-marketplace
```

**What to Look For:**
- `Connection State:` should be `READY` (if `TRANSIENT_FAILURE`, there's an issue)
- `Last Observed State:` shows current pod state
- `Key:` shows specific error conditions (e.g., `node.kubernetes.io/not-ready`)

### 1.3 Check Cluster Operators
```bash
oc get clusteroperators
```

**What to Look For:**
- All operators should show `AVAILABLE=True`, `PROGRESSING=False`, `DEGRADED=False`
- Pay attention to `marketplace` operator

---

## 2. Pod Status and Logs

### 2.1 List All Marketplace Pods
```bash
oc get pods -n openshift-marketplace
```

**Expected Output:**
```
NAME                                    READY   STATUS    RESTARTS   AGE
certified-operators-xyz                 1/1     Running   0          5d
community-operators-abc                 1/1     Running   0          5d
marketplace-operator-123                1/1     Running   0          10d
redhat-operators-456                    1/1     Running   0          5d
```

**Problem Indicators:**
- `0/1` in READY column
- Status: `ImagePullBackOff`, `ErrImagePull`, `CrashLoopBackOff`, `Pending`

### 2.2 Identify the Red Hat Operators Pod
```bash
oc get pods -n openshift-marketplace -l olm.catalogSource=redhat-operators
```

### 2.3 Describe the Pod
```bash
# Replace <pod-name> with actual pod name from step 2.2
oc describe pod <pod-name> -n openshift-marketplace
```

**What to Look For in Events Section:**
- `Failed to pull image` - Image pull issue
- `Back-off pulling image` - Repeated pull failures
- `Failed to create pod sandbox` - Network/runtime issue
- `Liveness probe failed` - Pod is unhealthy
- `FailedScheduling` - Resource or node issue

### 2.4 Check Pod Logs
```bash
oc logs <pod-name> -n openshift-marketplace
```

**Common Error Messages:**
- `connection refused` - Network/service issue
- `dial tcp: lookup` - DNS issue
- `x509: certificate` - Certificate/trust issue
- `unauthorized` - Authentication issue

### 2.5 Check Previous Pod Logs (if pod restarted)
```bash
oc logs <pod-name> -n openshift-marketplace --previous
```

---

## 3. Image Pull Issues

### 3.1 Check Global Pull Secret
```bash
oc get secret pull-secret -n openshift-config
```

### 3.2 Examine Pull Secret Contents
```bash
oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
```

**What to Look For:**
- Must contain `registry.redhat.io` entry
- Must contain valid authentication token

**Example Good Output:**
```json
{
  "auths": {
    "registry.redhat.io": {
      "auth": "encoded-credentials-here",
      "email": "your-email@example.com"
    },
    "cloud.openshift.com": {
      "auth": "encoded-credentials-here",
      "email": "your-email@example.com"
    }
  }
}
```

### 3.3 Verify Registry Access from Cluster

Create a test pod:
```bash
oc run test-registry-access \
  --image=registry.redhat.io/redhat/redhat-operator-index:v4.19 \
  --restart=Never \
  -n openshift-marketplace \
  -- sleep 3600
```

Check if it pulls successfully:
```bash
oc get pod test-registry-access -n openshift-marketplace
oc describe pod test-registry-access -n openshift-marketplace
```

**Expected Output:**
```
NAME                    READY   STATUS    RESTARTS   AGE
test-registry-access    1/1     Running   0          30s
```

Delete test pod:
```bash
oc delete pod test-registry-access -n openshift-marketplace
```

### 3.4 Update Pull Secret (if needed)

**Step 1:** Download your pull secret from https://console.redhat.com/openshift/downloads

**Step 2:** Save it to a file (e.g., `pull-secret.json`)

**Step 3:** Update the cluster pull secret:
```bash
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=./pull-secret.json
```

**Step 4:** Wait for nodes to update (this can take 10-15 minutes):
```bash
watch oc get nodes
```

**Step 5:** Verify the update:
```bash
oc get secret pull-secret -n openshift-config -o jsonpath='{.metadata.creationTimestamp}'
```

---

## 4. Network Connectivity Issues

### 4.1 Check Service Existence
```bash
oc get svc redhat-operators -n openshift-marketplace
```

**Expected Output:**
```
NAME               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)     AGE
redhat-operators   ClusterIP   172.30.123.45   <none>        50051/TCP   5d
```

### 4.2 Check Service Endpoints
```bash
oc get endpoints redhat-operators -n openshift-marketplace
```

**Expected Output:**
```
NAME               ENDPOINTS          AGE
redhat-operators   10.128.2.45:50051  5d
```

**Problem Indicator:**
- If ENDPOINTS is `<none>`, the pod isn't running or ready

### 4.3 Test Internal Network Connectivity

Start a debug container:
```bash
oc run network-test --rm -it --image=registry.access.redhat.com/ubi8/ubi:latest --restart=Never -n openshift-marketplace -- bash
```

Inside the container, test connectivity:
```bash
# Test DNS resolution
nslookup redhat-operators.openshift-marketplace.svc

# Test port connectivity
curl -v telnet://redhat-operators.openshift-marketplace.svc:50051

# Test HTTPS connectivity to Red Hat registry
curl -v https://registry.redhat.io/v2/

# Exit the container
exit
```

**Expected DNS Output:**
```
Server:         172.30.0.10
Address:        172.30.0.10#53

Name:   redhat-operators.openshift-marketplace.svc.cluster.local
Address: 172.30.123.45
```

### 4.4 Check Network Policies

List network policies in the namespace:
```bash
oc get networkpolicy -n openshift-marketplace
```

Describe each policy:
```bash
oc describe networkpolicy <policy-name> -n openshift-marketplace
```

**What to Look For:**
- Policies that might block ingress to port 50051
- Policies that might block egress to external registries

### 4.5 Test Node-to-Pod Connectivity

Get a worker node name:
```bash
oc get nodes -l node-role.kubernetes.io/worker
```

Debug from the node:
```bash
oc debug node/<node-name>
```

Inside the debug session:
```bash
chroot /host

# Test DNS
nslookup redhat-operators.openshift-marketplace.svc

# Test connectivity to catalog service
curl -v http://redhat-operators.openshift-marketplace.svc:50051

# Test external registry connectivity
curl -v https://registry.redhat.io/v2/

# Check if proxy is configured
env | grep -i proxy

# Exit debug session
exit
exit
```

### 4.6 Check Pod Network Status

Get pod IP:
```bash
oc get pod <catalog-pod-name> -n openshift-marketplace -o jsonpath='{.status.podIP}'
```

Check if pod has network:
```bash
oc exec <catalog-pod-name> -n openshift-marketplace -- ip addr show
```

---

## 5. DNS Resolution Issues

### 5.1 Check Cluster DNS Operator
```bash
oc get clusteroperator dns
```

**Expected Output:**
```
NAME   VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE
dns    4.x.x     True        False         False      10d
```

### 5.2 Check DNS Pods
```bash
oc get pods -n openshift-dns
```

**Expected Output:**
```
NAME                      READY   STATUS    RESTARTS   AGE
dns-default-abcd1         2/2     Running   0          5d
dns-default-abcd2         2/2     Running   0          5d
node-resolver-xyz1        1/1     Running   0          10d
node-resolver-xyz2        1/1     Running   0          10d
```

### 5.3 Test DNS from Catalog Pod

```bash
oc exec <catalog-pod-name> -n openshift-marketplace -- nslookup registry.redhat.io
```

**Expected Output:**
```
Server:         172.30.0.10
Address:        172.30.0.10#53

Non-authoritative answer:
Name:   registry.redhat.io
Address: 52.x.x.x
```

### 5.4 Check DNS Configuration
```bash
oc get dns.operator cluster -o yaml
```

### 5.5 Restart DNS Pods (if needed)

```bash
oc delete pod -n openshift-dns -l dns.operator.openshift.io/daemonset-dns=default
```

Wait for pods to restart:
```bash
watch oc get pods -n openshift-dns
```

---

## 6. Proxy Configuration

### 6.1 Check Cluster Proxy Configuration
```bash
oc get proxy cluster -o yaml
```

**Example Output (with proxy):**
```yaml
spec:
  httpProxy: http://proxy.example.com:8080
  httpsProxy: http://proxy.example.com:8080
  noProxy: .cluster.local,.svc,172.30.0.0/16,10.128.0.0/14
status:
  httpProxy: http://proxy.example.com:8080
  httpsProxy: http://proxy.example.com:8080
  noProxy: .cluster.local,.svc,172.30.0.0/16,10.128.0.0/14
```

### 6.2 Verify Proxy Environment Variables in Pod

```bash
oc get pod <catalog-pod-name> -n openshift-marketplace -o jsonpath='{.spec.containers[0].env}' | jq '.[] | select(.name | test("PROXY|proxy"))'
```

**Expected Output (if proxy is configured):**
```json
{
  "name": "HTTP_PROXY",
  "value": "http://proxy.example.com:8080"
}
{
  "name": "HTTPS_PROXY",
  "value": "http://proxy.example.com:8080"
}
{
  "name": "NO_PROXY",
  "value": ".cluster.local,.svc,172.30.0.0/16"
}
```

### 6.3 Test External Connectivity Through Proxy

```bash
oc run proxy-test --rm -it --image=registry.access.redhat.com/ubi8/ubi:latest --restart=Never -n openshift-marketplace -- bash
```

Inside the container:
```bash
# Test with proxy
curl -v -x $HTTP_PROXY https://registry.redhat.io/v2/

# Test direct (should fail if proxy required)
curl -v --noproxy "*" https://registry.redhat.io/v2/

exit
```

### 6.4 Update Proxy Configuration (if needed)

```bash
oc edit proxy cluster
```

Add or update the noProxy field to include:
- `.cluster.local`
- `.svc`
- Internal cluster IP ranges
- Internal service IP ranges

---

## 7. Firewall and NSG Rules

### 7.1 Required Outbound Endpoints

The cluster needs access to:

| Endpoint | Port | Purpose |
|----------|------|---------|
| registry.redhat.io | 443 | Container images |
| cdn.quay.io | 443 | Container images |
| cdn01.quay.io | 443 | Container images |
| cdn02.quay.io | 443 | Container images |
| cdn03.quay.io | 443 | Container images |
| quay.io | 443 | Container images |
| sso.redhat.com | 443 | Authentication |
| api.openshift.com | 443 | OpenShift services |

### 7.2 Check Azure NSG Rules

**Via Azure CLI:**

```bash
# Login to Azure
az login

# List NSGs in resource group
az network nsg list --resource-group <aro-resource-group> --output table

# Check NSG rules
az network nsg rule list --resource-group <aro-resource-group> --nsg-name <nsg-name> --output table
```

**What to Look For:**
- Outbound rules allowing HTTPS (443) to required endpoints
- No deny rules blocking outbound traffic

### 7.3 Check Azure Firewall Rules (if applicable)

```bash
# List firewall rules
az network firewall network-rule list --resource-group <aro-resource-group> --firewall-name <firewall-name> --collection-name <collection-name>
```

### 7.4 Test Connectivity to Required Endpoints

From a debug pod:
```bash
oc run connectivity-test --rm -it --image=registry.access.redhat.com/ubi8/ubi:latest --restart=Never -n openshift-marketplace -- bash
```

Inside the container:
```bash
# Test each endpoint
for endpoint in registry.redhat.io cdn.quay.io quay.io sso.redhat.com api.openshift.com; do
  echo "Testing $endpoint..."
  curl -I -m 5 https://$endpoint 2>&1 | head -n 1
done

exit
```

**Expected Output:**
```
Testing registry.redhat.io...
HTTP/2 200

Testing cdn.quay.io...
HTTP/2 200
...
```

---

## 8. Azure-Specific Issues

### 8.1 Check ARO Cluster Status

```bash
# Via Azure CLI
az aro show --name <cluster-name> --resource-group <resource-group> --query provisioningState
```

**Expected Output:**
```
"Succeeded"
```

### 8.2 Check Service Principal Permissions

```bash
# Get cluster service principal
oc get secret azure-credentials -n kube-system -o jsonpath='{.data.azure_client_id}' | base64 -d

# Check SP permissions in Azure
az role assignment list --assignee <service-principal-id> --resource-group <aro-resource-group>
```

### 8.3 Check Azure Private Link Configuration (if applicable)

```bash
# Check if cluster uses private link
az aro show --name <cluster-name> --resource-group <resource-group> --query 'networkProfile.privateEndpoint'
```

If using private endpoints, verify:
```bash
# List private endpoints
az network private-endpoint list --resource-group <aro-resource-group> --output table
```

### 8.4 Check ARO API Server Connectivity

```bash
oc whoami --show-server
curl -k $(oc whoami --show-server)/healthz
```

**Expected Output:**
```
ok
```

### 8.5 Verify Subnet Configuration

```bash
# Get cluster subnet info
az aro show --name <cluster-name> --resource-group <resource-group> --query 'masterProfile.subnetId'
az aro show --name <cluster-name> --resource-group <resource-group> --query 'workerProfiles[0].subnetId'
```

Check subnet properties:
```bash
az network vnet subnet show --ids <subnet-id>
```

**What to Look For:**
- Service endpoints enabled for Microsoft.ContainerRegistry
- Sufficient IP addresses available

---

## 9. CatalogSource Rebuild

### 9.1 Get Current CatalogSource Configuration

```bash
oc get catalogsource redhat-operators -n openshift-marketplace -o yaml > redhat-operators-backup.yaml
```

### 9.2 Delete the CatalogSource

```bash
oc delete catalogsource redhat-operators -n openshift-marketplace
```

### 9.3 Wait for Automatic Recreation

The cluster should automatically recreate it. Watch for recreation:
```bash
watch oc get catalogsource -n openshift-marketplace
```

### 9.4 Manual Recreation (if needed)

If it doesn't auto-recreate after 5 minutes:

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: redhat-operators
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: registry.redhat.io/redhat/redhat-operator-index:v4.19
  displayName: Red Hat Operators
  publisher: Red Hat
  updateStrategy:
    registryPoll:
      interval: 10m
  grpcPodConfig:
    securityContextConfig: restricted
EOF
```

### 9.5 Force Pod Recreation

If catalog exists but pod is stuck:

```bash
# Delete the pod
oc delete pod -n openshift-marketplace -l olm.catalogSource=redhat-operators

# Watch new pod creation
watch oc get pods -n openshift-marketplace -l olm.catalogSource=redhat-operators
```

### 9.6 Check PackageManifest Availability

After catalog is ready:
```bash
oc get packagemanifest -n openshift-marketplace | grep -i redhat
```

**Expected Output:**
```
advanced-cluster-management          Red Hat Operators   5d
ansible-automation-platform-operator Red Hat Operators   5d
...
```

---

## 10. Monitoring and Verification

### 10.1 Continuous Monitoring

Watch catalog source status:
```bash
watch -n 5 'oc get catalogsource redhat-operators -n openshift-marketplace -o custom-columns=NAME:.metadata.name,STATE:.status.connectionState.lastObservedState,CONNECTION:.status.connectionState.address'
```

**Expected Output:**
```
NAME               STATE    CONNECTION
redhat-operators   READY    redhat-operators.openshift-marketplace.svc:50051
```

### 10.2 Monitor Pods

```bash
watch -n 2 'oc get pods -n openshift-marketplace'
```

### 10.3 Test gRPC Connection

Install grpcurl for testing (from external machine or debug pod):

```bash
oc run grpcurl-test --rm -it --image=fullstorydev/grpcurl:latest --restart=Never -n openshift-marketplace -- \
  -plaintext redhat-operators.openshift-marketplace.svc:50051 list
```

**Expected Output:**
```
api.Registry
grpc.health.v1.Health
```

### 10.4 Verify Operator Availability

```bash
oc get packagemanifests -n openshift-marketplace | wc -l
```

Should show a large number (typically 200+)

### 10.5 Check Recent Events

```bash
oc get events -n openshift-marketplace --sort-by='.lastTimestamp' | head -20
```

---

## Common Issue Resolution Summary

### Issue: ImagePullBackOff
**Steps:**
1. Check pull secret (Section 3.2)
2. Update pull secret if needed (Section 3.4)
3. Test registry access (Section 3.3)
4. Check firewall rules (Section 7.1)

### Issue: TRANSIENT_FAILURE Connection State
**Steps:**
1. Check pod status (Section 2.1)
2. Check service and endpoints (Section 4.1, 4.2)
3. Test network connectivity (Section 4.3)
4. Rebuild catalog source (Section 9)

### Issue: DNS Resolution Failures
**Steps:**
1. Check DNS operator (Section 5.1)
2. Check DNS pods (Section 5.2)
3. Test DNS resolution (Section 5.3)
4. Restart DNS pods if needed (Section 5.5)

### Issue: Proxy Connection Problems
**Steps:**
1. Check proxy configuration (Section 6.1)
2. Verify noProxy settings (Section 6.2)
3. Test connectivity through proxy (Section 6.3)
4. Update proxy configuration (Section 6.4)

### Issue: Azure Network Restrictions
**Steps:**
1. Check NSG rules (Section 7.2)
2. Verify required endpoints (Section 7.1)
3. Test endpoint connectivity (Section 7.4)
4. Check subnet configuration (Section 8.5)

---

## Quick Diagnostic Script

Save this as `diagnose-catalog.sh`:

```bash
#!/bin/bash

echo "=== ARO Catalog Source Diagnostics ==="
echo ""

echo "1. Catalog Source Status:"
oc get catalogsource redhat-operators -n openshift-marketplace
echo ""

echo "2. Pod Status:"
oc get pods -n openshift-marketplace -l olm.catalogSource=redhat-operators
echo ""

echo "3. Pod Events:"
POD=$(oc get pods -n openshift-marketplace -l olm.catalogSource=redhat-operators -o jsonpath='{.items[0].metadata.name}')
oc get events -n openshift-marketplace --field-selector involvedObject.name=$POD --sort-by='.lastTimestamp' | tail -10
echo ""

echo "4. Service and Endpoints:"
oc get svc redhat-operators -n openshift-marketplace
oc get endpoints redhat-operators -n openshift-marketplace
echo ""

echo "5. Pull Secret Status:"
oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq -r '.auths | keys[]' | grep redhat
echo ""

echo "6. DNS Test:"
oc run dns-test --rm -it --image=registry.access.redhat.com/ubi8/ubi-minimal:latest --restart=Never -n openshift-marketplace -- sh -c "nslookup registry.redhat.io" 2>&1 | grep -A 5 "Server:"
echo ""

echo "7. Registry Connectivity:"
oc run registry-test --rm --image=registry.access.redhat.com/ubi8/ubi-minimal:latest --restart=Never -n openshift-marketplace -- sh -c "curl -I -m 5 https://registry.redhat.io 2>&1" | grep "HTTP"
echo ""

echo "=== Diagnostics Complete ==="
```

Run it:
```bash
chmod +x diagnose-catalog.sh
./diagnose-catalog.sh
```

---

## Getting Help

If issues persist after following this guide:

1. **Collect Must-Gather Data:**
```bash
oc adm must-gather
```

2. **Open Red Hat Support Case:**
- Navigate to https://access.redhat.com/support/cases/
- Select "Azure Red Hat OpenShift"
- Attach must-gather data

3. **Check Red Hat Customer Portal:**
- Search knowledge base: https://access.redhat.com/
- Check known issues and solutions

4. **Community Resources:**
- ARO Documentation: https://docs.openshift.com/aro/
- Red Hat Community: https://connect.redhat.com/

---

## Maintenance Tips

### Regular Health Checks
```bash
# Daily: Check catalog status
oc get catalogsource -n openshift-marketplace

# Weekly: Verify all operators
oc get clusteroperators

# Monthly: Review pull secret expiration
oc get secret pull-secret -n openshift-config -o yaml
```

### Preventive Measures
- Keep pull secrets updated
- Monitor Azure service health
- Review NSG rules after changes
- Test connectivity after network changes
- Keep cluster updated to latest version

---

**Document Version:** 1.0  
**Last Updated:** January 2026  
**Target Platform:** Azure Red Hat OpenShift (ARO) 4.x