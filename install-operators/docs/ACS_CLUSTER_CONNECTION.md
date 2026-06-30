# Red Hat Advanced Cluster Security (ACS) - Cluster Connection Guide

This guide explains how to connect OpenShift clusters to Red Hat Advanced Cluster Security (ACS) Central.

## Overview

ACS consists of two main components:
- **Central**: The management console that provides the UI and API
- **SecuredCluster**: The sensor that monitors and secures individual clusters

## Prerequisites

1. ACS Operator installed and CSV in `Succeeded` phase
2. Central deployed and in `Deployed` state
3. Access to both the Central cluster and the target cluster(s)

## Step 1: Verify Central is Ready

```bash
# Check Central status
oc get central stackrox-central-services -n rhacs-operator

# Wait for Central to be deployed
oc wait --for=condition=Deployed central/stackrox-central-services -n rhacs-operator --timeout=15m

# Get Central route and credentials
./scripts/acs-get-info.sh
```

## Step 2: Generate Init Bundle

The init bundle contains secrets needed for communication between Central and secured clusters.

### Option A: Using ACS UI (Recommended)

1. **Access ACS Central UI:**
   ```bash
   # Get the route
   oc get route central -n rhacs-operator
   
   # Get admin password
   oc get secret central-htpasswd -n rhacs-operator -o jsonpath='{.data.password}' | base64 -d
   ```

2. **Login to ACS Central:**
   - URL: `https://<central-route>`
   - Username: `admin`
   - Password: (from above command)

3. **Generate Init Bundle:**
   - Navigate to: **Platform Configuration** > **Integrations** > **Cluster Init Bundle**
   - Click **Generate bundle**
   - Enter a name (e.g., `production-cluster`)
   - Click **Generate bundle**
   - Download the YAML file

### Option B: Using roxctl CLI

```bash
# Download roxctl
curl -O https://mirror.openshift.com/pub/rhacs/assets/latest/bin/Linux/roxctl
chmod +x roxctl

# Set Central endpoint
export ROX_CENTRAL_ADDRESS=$(oc get route central -n rhacs-operator -o jsonpath='{.spec.host}')

# Login to Central
export ROX_PASSWORD=$(oc get secret central-htpasswd -n rhacs-operator -o jsonpath='{.data.password}' | base64 -d)
./roxctl central login

# Generate init bundle
./roxctl central init-bundles generate production-cluster --output-secrets init-bundle.yaml
```

## Step 3: Apply Init Bundle to Target Cluster

On the **target cluster** (the cluster you want to monitor):

```bash
# Create the stackrox namespace (if it doesn't exist)
oc create namespace stackrox

# Apply the init bundle
oc create -f init-bundle.yaml -n stackrox
```

## Step 4: Install ACS Operator on Target Cluster

If not already installed, install the ACS Operator on the target cluster:

```bash
# Create namespace
oc create namespace rhacs-operator

# Create OperatorGroup
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: acs-og
  namespace: rhacs-operator
spec:
  targetNamespaces:
  - rhacs-operator
EOF

# Create Subscription
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhacs-operator
  namespace: rhacs-operator
spec:
  channel: stable
  name: rhacs-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Wait for operator to be ready
oc wait --for=condition=AtLatestKnown subscription/rhacs-operator -n rhacs-operator --timeout=5m
```

## Step 5: Create SecuredCluster on Target Cluster

On the **target cluster**, create a SecuredCluster custom resource:

```bash
# Get Central endpoint from the Central cluster
CENTRAL_ENDPOINT="central.rhacs-operator.svc:443"  # If Central is in same cluster
# OR for external Central:
# CENTRAL_ENDPOINT="central.example.com:443"  # Use Central's route hostname

# Create SecuredCluster
cat <<EOF | oc apply -f -
apiVersion: platform.stackrox.io/v1alpha1
kind: SecuredCluster
metadata:
  name: secured-cluster
  namespace: stackrox
spec:
  admissionControl:
    listenOnCreates: true
    listenOnEvents: true
    listenOnUpdates: true
    dynamic:
      enforceOnCreates: false
      enforceOnUpdates: false
  centralEndpoint: ${CENTRAL_ENDPOINT}
  clusterName: $(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
  perNode:
    collector:
      collectionMethod: KernelModule
    taintToleration: None
EOF
```

### For External Central (Cross-Cluster)

If Central is in a different cluster, you need to:

1. **Expose Central via Route/Ingress:**
   ```bash
   # On Central cluster
   oc get route central -n rhacs-operator -o jsonpath='{.spec.host}'
   ```

2. **Use the route hostname in SecuredCluster:**
   ```yaml
   spec:
     centralEndpoint: central-rhacs-operator.apps.example.com:443
   ```

3. **Ensure network connectivity:**
   - The target cluster must be able to reach the Central route
   - Port 443 must be accessible

## Step 6: Verify Connection

### On Target Cluster

```bash
# Check SecuredCluster status
oc get securedcluster -n stackrox

# Wait for deployment
oc wait --for=condition=Deployed securedcluster/secured-cluster -n stackrox --timeout=10m

# Check sensor pods
oc get pods -n stackrox -l app=sensor

# Check collector pods (one per node)
oc get pods -n stackrox -l app=collector
```

### On Central Cluster

1. **Login to ACS Central UI**
2. **Navigate to: Platform Configuration > Clusters**
3. **Verify the cluster appears in the list**
4. **Check cluster health status**

## Step 7: Configure Security Policies

1. **Access ACS Central UI**
2. **Navigate to: Platform Configuration > Policy Management**
3. **Review and customize policies:**
   - System policies (pre-configured)
   - Custom policies (create your own)

4. **Enable policy enforcement:**
   - Go to: **Platform Configuration > System Policies**
   - Select policies to enforce
   - Set enforcement actions (Alert, Deploy, Runtime)

## Troubleshooting

### Central Not Ready

```bash
# Check Central pods
oc get pods -n rhacs-operator -l app=central

# Check Central logs
oc logs -n rhacs-operator -l app=central --tail=100

# Check Central CR status
oc describe central stackrox-central-services -n rhacs-operator
```

### SecuredCluster Not Connecting

```bash
# Check sensor pods
oc get pods -n stackrox -l app=sensor

# Check sensor logs
oc logs -n stackrox -l app=sensor --tail=100

# Verify init bundle secrets exist
oc get secrets -n stackrox | grep init

# Check network connectivity
oc run -it --rm debug --image=registry.redhat.io/ubi8/ubi-minimal:latest --restart=Never -- \
  sh -c "nc -zv <central-endpoint> 443"
```

### Admission Controller Issues

```bash
# Check admission controller pods
oc get pods -n stackrox -l app=admission-control

# Check webhook configuration
oc get validatingwebhookconfigurations | grep stackrox
oc get mutatingwebhookconfigurations | grep stackrox

# Test admission control
oc run test-pod --image=nginx:latest --dry-run=server -o yaml
```

## API Token for CI/CD

To integrate ACS with CI/CD pipelines:

1. **Login to ACS Central UI**
2. **Navigate to: Platform Configuration > Integrations > Authentication Tokens**
3. **Click "Generate token"**
4. **Configure permissions:**
   - **Name**: e.g., `ci-cd-token`
   - **Roles**: Select appropriate roles (e.g., `Continuous Integration`, `Vulnerability Management`)
5. **Download or copy the token**

### Using API Token

```bash
export ROX_API_TOKEN="<your-token>"
export ROX_CENTRAL_ADDRESS="<central-route>"

# Example: Scan image
roxctl image scan --image quay.io/example/app:latest

# Example: Check policy violations
roxctl deployment check --name my-app --namespace production
```

## Additional Resources

- [Red Hat ACS Documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/)
- [ACS Installation Guide](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.2/html/installing/installing_rhacs)
- [Connecting Clusters](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.2/html/installing/connecting_clusters)

## Quick Reference

```bash
# Get Central info
./scripts/acs-get-info.sh

# Get Central route
oc get route central -n rhacs-operator

# Get admin password
oc get secret central-htpasswd -n rhacs-operator -o jsonpath='{.data.password}' | base64 -d

# Check Central status
oc get central stackrox-central-services -n rhacs-operator

# Check SecuredCluster status
oc get securedcluster -n stackrox

# Check all ACS components
oc get all -n rhacs-operator
oc get all -n stackrox
```

