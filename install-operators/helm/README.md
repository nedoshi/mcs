# OpenShift Operators - Helm Installation

This directory contains Helm charts for installing OpenShift operators using the Operator Lifecycle Manager (OLM).

## Overview

The Helm chart structure includes:
- **Parent Chart** (`helm/Chart.yaml`): Umbrella chart that manages all operator subcharts
- **Subcharts** (`helm/charts/`): Individual Helm charts for each operator
- **Values Files**: Configuration files for customizing operator installations

## Prerequisites

- Helm 3.x installed
- `kubectl` or `oc` CLI configured with cluster access
- OpenShift cluster with OLM (Operator Lifecycle Manager) enabled
- Access to `redhat-operators` catalog source in `openshift-marketplace`

## Quick Start

### Install Operators One by One (Recommended for Testing)

Use the provided script to install operators individually:

```bash
cd helm

# Install a single operator
./install-operator.sh pipelines

# Install and wait for operator to be ready
./install-operator.sh acs -w

# Install with Custom Resource (e.g., Central for ACS)
./install-operator.sh acs -w -c

# Install AI with DataScienceCluster
./install-operator.sh ai -w -d

# Install Virtualization with HyperConverged
./install-operator.sh virtualization -w -H

# Install Developer Hub with Backstage
./install-operator.sh developer-hub -w -b
```

**Available operators:**
- `pipelines` - OpenShift Pipelines
- `rhtas` - Red Hat Trusted Artifact Signer
- `acs` - Advanced Cluster Security
- `ai` - OpenShift AI
- `virtualization` - KubeVirt Virtualization
- `developer-hub` - Developer Hub (Backstage)
- `gitops` - OpenShift GitOps

See [Installing Individual Operator Charts](#installing-individual-operator-charts) section for manual installation steps.

### Install All Operators

**Important:** If namespaces already exist (e.g., from previous installations), you need to add Helm metadata first:

```bash
cd helm
# Add Helm metadata to existing namespaces (if they exist)
./add-helm-metadata.sh openshift-operators operators

# Update dependencies
helm dependency update

# Install all operators
helm install openshift-operators . --namespace operators --create-namespace
```

**Alternative:** If namespaces don't exist or you want to force adoption:

```bash
cd helm
helm dependency update
helm install openshift-operators . --namespace operators --create-namespace --force
```

### Install Specific Operators

You can enable/disable specific operators using values:

```bash
helm install openshift-operators . \
  --namespace operators \
  --create-namespace \
  --set pipelines.enabled=true \
  --set acs.enabled=true \
  --set ai.enabled=false
```

### Using Custom Values File

Create a custom values file:

```bash
# Copy the default values
cp values.yaml my-values.yaml

# Edit my-values.yaml to customize
# Then install:
helm install openshift-operators . \
  --namespace operators \
  --create-namespace \
  -f my-values.yaml
```

## Chart Structure

```
helm/
├── Chart.yaml              # Parent chart definition
├── values.yaml             # Default values for all operators
├── charts/                 # Subcharts directory
│   ├── pipelines/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── namespace.yaml
│   │       ├── operatorgroup.yaml
│   │       └── subscription.yaml
│   ├── rhtas/
│   ├── acs/
│   ├── ai/
│   ├── virtualization/
│   ├── developer-hub/
│   └── gitops/
└── README.md
```

## Available Operators

| Operator | Chart Name | Default Namespace | Default Channel |
|----------|-----------|-------------------|-----------------|
| OpenShift Pipelines | `pipelines` | `openshift-operators` | `stable` |
| Red Hat Trusted Artifact Signer | `rhtas` | `openshift-operators` | `stable` |
| Advanced Cluster Security | `acs` | `rhacs-operator` | `stable` |
| Central (CR) | `acs.central` | `rhacs-operator` | N/A (requires operator) |
| OpenShift AI | `ai` | `redhat-ods-operator` | `stable` |
| DataScienceCluster (CR) | `ai.datasciencecluster` | `redhat-ods-operator` | N/A (requires operator) |
| KubeVirt Virtualization | `virtualization` | `openshift-cnv` | `stable` |
| HyperConverged (CR) | `virtualization.hyperconverged` | `openshift-cnv` | N/A (requires operator) |
| Developer Hub (Backstage) | `developer-hub` | `rhdh-operator` | `fast` |
| OpenShift GitOps | `gitops` | `openshift-gitops-operator` | `latest` |

## Configuration

### Global Values

```yaml
global:
  channel: stable
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

### Per-Operator Configuration

Each operator can be configured individually:

```yaml
pipelines:
  enabled: true
  namespace: openshift-operators
  subscription:
    name: openshift-pipelines-operator
    channel: stable
    installPlanApproval: Automatic
```

### Environment-Specific Values

#### Development Environment

```yaml
# values-dev.yaml
pipelines:
  subscription:
    channel: fast  # Use fast channel for dev

acs:
  enabled: false  # Disable ACS in dev
```

Install with:
```bash
helm install openshift-operators . -f values-dev.yaml
```

#### Production Environment

```yaml
# values-prod.yaml
global:
  installPlanApproval: Manual  # Manual approval for prod

pipelines:
  subscription:
    channel: stable
    installPlanApproval: Manual
```

## Installation Commands

### Install

```bash
# Update dependencies first
helm dependency update

# Install with default values
helm install openshift-operators . --namespace operators --create-namespace

# Install with custom values
helm install openshift-operators . \
  --namespace operators \
  --create-namespace \
  -f values-prod.yaml

# Install with inline overrides
helm install openshift-operators . \
  --namespace operators \
  --create-namespace \
  --set pipelines.enabled=true \
  --set acs.enabled=false
```

### Upgrade

```bash
# Upgrade with new values
helm upgrade openshift-operators . \
  --namespace operators \
  -f values-prod.yaml

# Upgrade with inline overrides
helm upgrade openshift-operators . \
  --namespace operators \
  --set pipelines.subscription.channel=fast
```

### Uninstall

See the [Uninstalling Operators](#uninstalling-operators) section below for comprehensive uninstall documentation.

**Quick Reference:**

```bash
# Uninstall all operators (umbrella chart)
./uninstall.sh

# Uninstall individual operator
./uninstall-operator.sh pipelines

# Uninstall with resource cleanup
./uninstall-operator.sh acs -c

# Uninstall with complete cleanup (CSVs, Custom Resources)
./uninstall-operator.sh acs -C
```

## Verification

After installation, verify the operators are installing:

```bash
# Check subscriptions
oc get subscription -A

# Check ClusterServiceVersions
oc get csv -A

# Check operator pods
oc get pods -A | grep -E 'operator|controller'

# Validate specific operator
oc get csv -n openshift-operators -l operators.coreos.com/openshift-pipelines-operator.openshift-operators=
```

## Troubleshooting

### Common Installation Errors

#### Error: "values don't meet the specifications of the schema"

This usually means missing required fields in values.yaml. Ensure all subscription sections include:
- `name`
- `channel`
- `source`
- `sourceNamespace`
- `installPlanApproval`

#### Error: "failed to download" or dependency issues

If `helm dependency update` fails:

```bash
# Clean up and retry
rm -rf charts/*.tgz Chart.lock
helm dependency update
```

#### Error: "rendered manifests contain a resource that already exists"

This happens when resources (namespaces, subscriptions) already exist. Options:

1. **Delete existing resources first:**
   ```bash
   oc delete subscription <name> -n <namespace>
   oc delete operatorgroup <name> -n <namespace>
   ```

2. **Use `--replace` flag (Helm 3.9+):**
   ```bash
   helm install openshift-operators . --replace --namespace operators
   ```

3. **Use `--force` flag:**
   ```bash
   helm install openshift-operators . --force --namespace operators
   ```

#### Error: "namespace already exists" or "invalid ownership metadata"

If namespaces already exist without Helm metadata, you have two options:

**Option 1: Add Helm metadata to existing namespaces (Recommended)**

Add the required Helm labels and annotations to existing namespaces:

```bash
# For each existing namespace, run:
NAMESPACE="rhacs-operator"  # Change for each namespace
RELEASE_NAME="openshift-operators"
RELEASE_NAMESPACE="operators"

oc label namespace $NAMESPACE app.kubernetes.io/managed-by=Helm --overwrite
oc annotate namespace $NAMESPACE meta.helm.sh/release-name=$RELEASE_NAME --overwrite
oc annotate namespace $NAMESPACE meta.helm.sh/release-namespace=$RELEASE_NAMESPACE --overwrite
```

**Option 2: Use `--force` flag**

Force Helm to adopt existing resources:

```bash
helm install openshift-operators . --namespace operators --create-namespace --force
```

**Option 3: Delete and recreate namespaces**

If the namespaces don't contain important resources:

```bash
# WARNING: This will delete the namespace and all resources in it
oc delete namespace rhacs-operator
# Then install with Helm
helm install openshift-operators . --namespace operators --create-namespace
```

#### Error: "no matches for kind" or "unable to recognize"

This means the cluster doesn't have OLM installed or the API isn't available:

```bash
# Check if OLM is installed
oc get crd subscriptions.operators.coreos.com
oc get crd operatorgroups.operators.coreos.com

# If not installed, OLM is required for operator installation
```

### Operator Installation Fails

1. Check subscription status:
   ```bash
   oc get subscription -A
   oc describe subscription <name> -n <namespace>
   ```

2. Check install plans:
   ```bash
   oc get installplan -A
   oc describe installplan <name> -n <namespace>
   ```

3. Check CSV status:
   ```bash
   oc get csv -A
   oc describe csv <name> -n <namespace>
   ```

4. Review operator logs:
   ```bash
   oc logs -n <namespace> -l app=<operator-name>
   ```

### ACS Operator Deployment Failure

If the ACS operator CSV shows "InstallCheckFailed" with deployment timeout errors:

1. **Check the deployment status:**
   ```bash
   oc get deployment rhacs-operator-controller-manager -n rhacs-operator
   oc describe deployment rhacs-operator-controller-manager -n rhacs-operator
   ```

2. **Check deployment pods:**
   ```bash
   oc get pods -n rhacs-operator -l app=rhacs-operator
   oc describe pod -n rhacs-operator -l app=rhacs-operator
   ```

3. **Check pod logs for errors:**
   ```bash
   oc logs -n rhacs-operator -l app=rhacs-operator --tail=100
   ```

4. **Check for resource constraints:**
   ```bash
   # Check if nodes have enough resources
   oc describe nodes
   
   # Check for resource quotas
   oc get resourcequota -n rhacs-operator
   ```

5. **Check for image pull issues:**
   ```bash
   # Verify image pull secrets
   oc get secret -n rhacs-operator
   oc get sa rhacs-operator-controller-manager -n rhacs-operator -o yaml
   ```

6. **Common fixes:**
   
   **Option A: Delete and reinstall the CSV:**
   ```bash
   # Delete the failed CSV
   oc delete csv rhacs-operator.v4.9.2 -n rhacs-operator
   
   # Delete the subscription to trigger reinstall
   oc delete subscription rhacs-operator -n rhacs-operator
   
   # Reapply the subscription (or reinstall via Helm)
   oc apply -f operators/acs/subscription.yaml
   ```

   **Option B: Check for conflicting resources:**
   ```bash
   # Check for existing deployments
   oc get deployment -n rhacs-operator
   
   # Check for existing service accounts
   oc get sa -n rhacs-operator
   
   # Clean up if needed
   oc delete deployment rhacs-operator-controller-manager -n rhacs-operator
   ```

   **Option C: Increase deployment timeout (if using Helm):**
   ```bash
   # This is typically handled by OLM, but you can check CSV timeout settings
   oc get csv rhacs-operator.v4.9.2 -n rhacs-operator -o yaml | grep -i timeout
   ```

7. **Verify operator requirements:**
   ```bash
   # Check CSV requirements status
   oc get csv rhacs-operator.v4.9.2 -n rhacs-operator -o jsonpath='{.status.requirementStatus}'
   
   # Check for missing CRDs
   oc get crd | grep stackrox
   ```

8. **If deployment keeps failing, check cluster resources:**
   ```bash
   # Check node resources
   oc top nodes
   
   # Check for taints/tolerations issues
   oc describe nodes | grep -i taint
   
   # Check for pod scheduling issues
   oc get events -n rhacs-operator --sort-by='.lastTimestamp'
   ```

### Namespace Conflicts

Some operators share the same namespace (e.g., `openshift-operators`). Helm will handle this automatically, but if you encounter issues:

1. Check if namespace already exists:
   ```bash
   oc get namespace openshift-operators
   ```

2. The namespace template includes a check, but you may need to manually create shared namespaces before installation.

## Advanced Usage

### Installing Individual Operator Charts

You can install operators one by one by installing each chart individually. This is useful when you want to:
- Install operators in a specific order
- Test individual operators
- Install only specific operators without the umbrella chart
- Have more control over each installation

#### Method 1: Install Individual Charts Directly

Navigate to each chart directory and install it:

**1. Pipelines Operator:**
```bash
cd helm/charts/pipelines
helm install pipelines-operator . \
  --namespace openshift-operators \
  --create-namespace \
  --set namespace=openshift-operators
```

**2. RHTAS (Trusted Artifact Signer) Operator:**
```bash
cd helm/charts/rhtas
helm install rhtas-operator . \
  --namespace openshift-operators \
  --create-namespace \
  --set namespace=openshift-operators
```

**3. ACS (Advanced Cluster Security) Operator:**
```bash
cd helm/charts/acs
helm install acs-operator . \
  --namespace rhacs-operator \
  --create-namespace \
  --set namespace=rhacs-operator
```

**4. AI (OpenShift AI) Operator:**
```bash
cd helm/charts/ai
helm install ai-operator . \
  --namespace redhat-ods-operator \
  --create-namespace \
  --set namespace=redhat-ods-operator
```

**5. Virtualization Operator:**
```bash
cd helm/charts/virtualization
helm install virtualization-operator . \
  --namespace openshift-cnv \
  --create-namespace \
  --set namespace=openshift-cnv
```

**6. Developer Hub Operator:**
```bash
cd helm/charts/developer-hub
helm install developer-hub-operator . \
  --namespace rhdh-operator \
  --create-namespace \
  --set namespace=rhdh-operator
```

**7. GitOps Operator:**
```bash
cd helm/charts/gitops
helm install gitops-operator . \
  --namespace openshift-gitops-operator \
  --create-namespace \
  --set namespace=openshift-gitops-operator
```

#### Method 2: Install with Custom Values File

Create a values file for each operator and use it:

**Example: `pipelines-values.yaml`**
```yaml
namespace: openshift-operators
subscription:
  name: openshift-pipelines-operator
  channel: stable
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

Then install:
```bash
cd helm/charts/pipelines
helm install pipelines-operator . \
  --namespace openshift-operators \
  --create-namespace \
  -f pipelines-values.yaml
```

#### Method 3: Install from Root Directory

You can also install individual charts from the root `helm` directory:

```bash
cd helm

# Install pipelines operator
helm install pipelines-operator ./charts/pipelines \
  --namespace openshift-operators \
  --create-namespace

# Install RHTAS operator
helm install rhtas-operator ./charts/rhtas \
  --namespace openshift-operators \
  --create-namespace

# Install ACS operator
helm install acs-operator ./charts/acs \
  --namespace rhacs-operator \
  --create-namespace
```

#### Installing with Custom Resources

Some operators support Custom Resource instances. Enable them during or after operator installation:

**ACS with Central:**
```bash
cd helm/charts/acs
helm install acs-operator . \
  --namespace rhacs-operator \
  --create-namespace \
  --set namespace=rhacs-operator \
  --set central.enabled=true \
  --set central.namespace=stackrox
```

**AI with DataScienceCluster:**
```bash
cd helm/charts/ai
helm install ai-operator . \
  --namespace redhat-ods-operator \
  --create-namespace \
  --set namespace=redhat-ods-operator \
  --set datasciencecluster.enabled=true
```

**Virtualization with HyperConverged:**
```bash
cd helm/charts/virtualization
helm install virtualization-operator . \
  --namespace openshift-cnv \
  --create-namespace \
  --set namespace=openshift-cnv \
  --set hyperconverged.enabled=true
```

**Developer Hub with Backstage:**
```bash
cd helm/charts/developer-hub
helm install developer-hub-operator . \
  --namespace rhdh-operator \
  --create-namespace \
  --set namespace=rhdh-operator \
  --set backstage.enabled=true
```

#### Verification After Individual Installation

After installing each operator, verify it's working:

```bash
# Check subscription
oc get subscription -n <operator-namespace>

# Check CSV status
oc get csv -n <operator-namespace>

# Check operator pods
oc get pods -n <operator-namespace>

# Example for pipelines
oc get subscription -n openshift-operators | grep pipelines
oc get csv -n openshift-operators | grep pipelines
oc get pods -n openshift-operators | grep pipelines
```

## Uninstalling Operators

### Uninstalling Individual Operators

When you install operators individually, you can uninstall them one by one:

#### Method 1: Using Helm Uninstall

**Basic uninstall (removes Helm release only):**

```bash
# Uninstall pipelines operator
helm uninstall pipelines-operator --namespace openshift-operators

# Uninstall RHTAS operator
helm uninstall rhtas-operator --namespace openshift-operators

# Uninstall ACS operator
helm uninstall acs-operator --namespace rhacs-operator

# Uninstall AI operator
helm uninstall ai-operator --namespace redhat-ods-operator

# Uninstall Virtualization operator
helm uninstall virtualization-operator --namespace openshift-cnv

# Uninstall Developer Hub operator
helm uninstall developer-hub-operator --namespace rhdh-operator

# Uninstall GitOps operator
helm uninstall gitops-operator --namespace openshift-gitops-operator
```

**Uninstall with resource cleanup:**

```bash
# 1. Uninstall Helm release
helm uninstall pipelines-operator --namespace openshift-operators

# 2. Delete subscription
oc delete subscription openshift-pipelines-operator -n openshift-operators

# 3. Delete operatorgroup
oc delete operatorgroup pipelines-og -n openshift-operators

# 4. Delete CSV (if needed for complete removal)
oc delete csv -n openshift-operators -l operators.coreos.com/openshift-pipelines-operator.openshift-operators=
```

#### Method 2: Uninstall Script for Individual Operators

Create a helper script or use these commands:

```bash
# Function to uninstall an operator
uninstall_operator() {
    local release=$1
    local namespace=$2
    local subscription=$3
    local operatorgroup=$4
    
    echo "Uninstalling $release..."
    
    # Uninstall Helm release
    helm uninstall "$release" --namespace "$namespace" || echo "Release not found"
    
    # Delete subscription
    oc delete subscription "$subscription" -n "$namespace" --ignore-not-found=true
    
    # Delete operatorgroup
    oc delete operatorgroup "$operatorgroup" -n "$namespace" --ignore-not-found=true
    
    echo "✅ $release uninstalled"
}

# Examples
uninstall_operator pipelines-operator openshift-operators openshift-pipelines-operator pipelines-og
uninstall_operator acs-operator rhacs-operator rhacs-operator acs-og
```

#### Method 3: Uninstall with Custom Resources

If you installed operators with Custom Resources (Central, DataScienceCluster, etc.), you may need to delete them first:

**ACS with Central:**
```bash
# 1. Delete Central (if enabled)
oc delete central stackrox-central-services -n stackrox --ignore-not-found=true

# 2. Delete SecuredCluster (if enabled)
oc delete securedcluster secured-cluster -n rhacs-operator --ignore-not-found=true

# 3. Uninstall operator
helm uninstall acs-operator --namespace rhacs-operator

# 4. Clean up resources
oc delete subscription rhacs-operator -n rhacs-operator
oc delete operatorgroup acs-og -n rhacs-operator
```

**AI with DataScienceCluster:**
```bash
# 1. Delete DataScienceCluster (if enabled)
oc delete datasciencecluster default-dsc -n redhat-ods-operator --ignore-not-found=true

# 2. Uninstall operator
helm uninstall ai-operator --namespace redhat-ods-operator

# 3. Clean up resources
oc delete subscription rhods-operator -n redhat-ods-operator
oc delete operatorgroup ai-og -n redhat-ods-operator
```

**Virtualization with HyperConverged:**
```bash
# 1. Delete HyperConverged (if enabled)
oc delete hyperconverged kubevirt-hyperconverged -n openshift-cnv --ignore-not-found=true

# 2. Uninstall operator
helm uninstall virtualization-operator --namespace openshift-cnv

# 3. Clean up resources
oc delete subscription kubevirt-hyperconverged -n openshift-cnv
oc delete operatorgroup virtualization-og -n openshift-cnv
```

**Developer Hub with Backstage:**
```bash
# 1. Delete Backstage (if enabled)
oc delete backstage developer-hub -n rhdh-operator --ignore-not-found=true

# 2. Uninstall operator
helm uninstall developer-hub-operator --namespace rhdh-operator

# 3. Clean up resources
oc delete subscription rhdh -n rhdh-operator
oc delete operatorgroup developer-hub-og -n rhdh-operator
```

### Uninstalling All Operators (Umbrella Chart)

If you installed all operators using the umbrella chart:

#### Method 1: Using the Uninstall Script

```bash
cd helm

# Quick uninstall (Helm release only)
./uninstall.sh

# Full uninstall (Helm release + all resources)
./uninstall.sh --clean-all
```

#### Method 2: Manual Uninstall

**Step 1: Uninstall Helm Release**
```bash
helm uninstall openshift-operators --namespace operators
```

**Step 2: Delete Subscriptions (Optional)**
```bash
# Delete all Helm-managed subscriptions
oc delete subscription -A -l app.kubernetes.io/managed-by=Helm

# Or delete individually
oc delete subscription openshift-pipelines-operator -n openshift-operators
oc delete subscription trusted-artifact-signer-operator -n openshift-operators
oc delete subscription rhacs-operator -n rhacs-operator
oc delete subscription rhods-operator -n redhat-ods-operator
oc delete subscription kubevirt-hyperconverged -n openshift-cnv
oc delete subscription rhdh -n rhdh-operator
oc delete subscription openshift-gitops-operator -n openshift-gitops-operator
```

**Step 3: Delete OperatorGroups (Optional)**
```bash
# Delete all Helm-managed operatorgroups
oc delete operatorgroup -A -l app.kubernetes.io/managed-by=Helm

# Or delete individually
oc delete operatorgroup pipelines-og -n openshift-operators
oc delete operatorgroup rhtas-og -n openshift-operators
oc delete operatorgroup acs-og -n rhacs-operator
oc delete operatorgroup ai-og -n redhat-ods-operator
oc delete operatorgroup virtualization-og -n openshift-cnv
oc delete operatorgroup developer-hub-og -n rhdh-operator
oc delete operatorgroup openshift-gitops-operator -n openshift-gitops-operator
```

**Step 4: Delete ClusterServiceVersions (CSVs) - Complete Removal**
```bash
# Delete CSVs to fully remove operators
oc delete csv -n openshift-operators -l operators.coreos.com/openshift-pipelines-operator.openshift-operators=
oc delete csv -n openshift-operators -l operators.coreos.com/trusted-artifact-signer-operator.openshift-operators=
oc delete csv -n rhacs-operator -l operators.coreos.com/rhacs-operator.rhacs-operator=
oc delete csv -n redhat-ods-operator -l operators.coreos.com/rhods-operator.redhat-ods-operator=
oc delete csv -n openshift-cnv -l operators.coreos.com/kubevirt-hyperconverged.openshift-cnv=
oc delete csv -n rhdh-operator -l operators.coreos.com/rhdh.rhdh-operator=
oc delete csv -n openshift-gitops-operator -l operators.coreos.com/openshift-gitops-operator.openshift-gitops-operator=
```

**Step 5: Delete Custom Resources (if any)**
```bash
# Delete Central
oc delete central stackrox-central-services -n stackrox --ignore-not-found=true

# Delete SecuredCluster
oc delete securedcluster secured-cluster -n rhacs-operator --ignore-not-found=true

# Delete DataScienceCluster
oc delete datasciencecluster default-dsc -n redhat-ods-operator --ignore-not-found=true

# Delete HyperConverged
oc delete hyperconverged kubevirt-hyperconverged -n openshift-cnv --ignore-not-found=true

# Delete Backstage
oc delete backstage developer-hub -n rhdh-operator --ignore-not-found=true
```

**Step 6: Clean Up Namespaces (Optional - Use with Caution)**
```bash
# WARNING: Only delete operator-specific namespaces, NOT system namespaces like openshift-operators

# Delete operator namespaces (if empty)
oc delete namespace rhacs-operator --ignore-not-found=true
oc delete namespace redhat-ods-operator --ignore-not-found=true
oc delete namespace openshift-cnv --ignore-not-found=true
oc delete namespace rhdh-operator --ignore-not-found=true
oc delete namespace openshift-gitops-operator --ignore-not-found=true
oc delete namespace stackrox --ignore-not-found=true

# DO NOT delete openshift-operators - it's a system namespace
```

### Verification After Uninstall

After uninstalling, verify everything is removed:

```bash
# Check Helm releases
helm list -A

# Check subscriptions
oc get subscription -A

# Check operatorgroups
oc get operatorgroup -A

# Check CSVs
oc get csv -A

# Check operator pods
oc get pods -A | grep -E "operator|controller"

# Check Custom Resources
oc get central -A
oc get datasciencecluster -A
oc get hyperconverged -A
oc get backstage -A
```

### Important Notes

1. **Helm Release vs. Operator Resources:**
   - Uninstalling the Helm release removes the Subscriptions managed by Helm
   - Operators installed via OLM may continue running until their CSVs are removed
   - Custom Resources (Central, DataScienceCluster, etc.) are NOT automatically deleted when uninstalling the Helm release

2. **System Namespaces:**
   - **DO NOT** delete `openshift-operators` - it's a system namespace used by multiple operators
   - Only delete operator-specific namespaces if they're empty and safe to remove

3. **Custom Resources:**
   - Always delete Custom Resources (Central, DataScienceCluster, HyperConverged, Backstage) before uninstalling operators
   - This ensures proper cleanup and prevents orphaned resources

4. **Complete Removal:**
   - To completely remove an operator, you need to:
     1. Delete Custom Resources (if any)
     2. Uninstall Helm release
     3. Delete Subscription
     4. Delete OperatorGroup
     5. Delete CSV (optional, but ensures complete removal)

5. **Shared Namespaces:**
   - `openshift-operators` is shared by Pipelines and RHTAS
   - Be careful when deleting resources in shared namespaces
   - Use labels to identify Helm-managed resources: `app.kubernetes.io/managed-by=Helm`

### Troubleshooting Uninstall Issues

**Issue: Helm release not found**
```bash
# List all Helm releases
helm list -A

# Check if release exists in different namespace
helm list --all-namespaces | grep <release-name>
```

**Issue: Resources still exist after uninstall**
```bash
# Check for remaining subscriptions
oc get subscription -A -l app.kubernetes.io/managed-by=Helm

# Force delete if needed
oc delete subscription <name> -n <namespace> --force --grace-period=0
```

**Issue: Namespace stuck in Terminating**
```bash
# Check what's blocking namespace deletion
oc get namespace <namespace> -o yaml

# Force delete finalizers (use with caution)
oc patch namespace <namespace> -p '{"metadata":{"finalizers":[]}}' --type=merge
```

**Issue: CSV still exists**
```bash
# Delete CSV directly
oc delete csv <csv-name> -n <namespace>

# Or delete all CSVs for an operator
oc delete csv -n <namespace> -l operators.coreos.com/<operator-name>.<namespace>=
```

#### Complete Installation Sequence Example

Here's an example of installing operators one by one in a specific order:

```bash
# 1. Install Pipelines
cd helm/charts/pipelines
helm install pipelines-operator . \
  --namespace openshift-operators \
  --create-namespace
oc wait --for=condition=AtLatestKnown subscription/openshift-pipelines-operator \
  -n openshift-operators --timeout=10m

# 2. Install RHTAS
cd ../rhtas
helm install rhtas-operator . \
  --namespace openshift-operators \
  --create-namespace
oc wait --for=condition=AtLatestKnown subscription/trusted-artifact-signer-operator \
  -n openshift-operators --timeout=10m

# 3. Install ACS
cd ../acs
helm install acs-operator . \
  --namespace rhacs-operator \
  --create-namespace
oc wait --for=condition=AtLatestKnown subscription/rhacs-operator \
  -n rhacs-operator --timeout=10m

# 4. Enable Central after operator is ready
oc wait --for=condition=Succeeded csv/rhacs-operator.v* \
  -n rhacs-operator --timeout=15m
helm upgrade acs-operator . \
  --namespace rhacs-operator \
  --set central.enabled=true \
  --set central.namespace=stackrox

# Continue with other operators...
```

### Creating HyperConverged for OpenShift Virtualization

After installing the Virtualization operator, you need to create a HyperConverged Custom Resource to enable KubeVirt functionality.

**Option 1: Enable during installation**

```bash
helm install openshift-operators . \
  --namespace operators \
  --create-namespace \
  --set virtualization.enabled=true \
  --set virtualization.hyperconverged.enabled=true
```

**Option 2: Enable after operator installation**

1. First, install the operator:
   ```bash
   helm install openshift-operators . \
     --namespace operators \
     --create-namespace \
     --set virtualization.enabled=true
   ```

2. Wait for the operator CSV to be in `Succeeded` phase:
   ```bash
   oc get csv -n openshift-cnv -l operators.coreos.com/kubevirt-hyperconverged.openshift-cnv=
   ```

3. Upgrade the release to enable HyperConverged:
   ```bash
   helm upgrade openshift-operators . \
     --namespace operators \
     --set virtualization.hyperconverged.enabled=true
   ```

**Option 3: Customize HyperConverged configuration**

Create a custom values file (`my-values.yaml`):

```yaml
virtualization:
  enabled: true
  hyperconverged:
    enabled: true
    name: kubevirt-hyperconverged
    spec:
      localStorageClassName: "local-storage"
      scratchSpaceStorageClass: "local-storage"
      featureGates:
        enableCommonBootImageImport: true
      liveMigrationConfig:
        parallelMigrationsPerCluster: 5
        bandwidthPerMigration: "64Mi"
```

Then install:
```bash
helm install openshift-operators . -f my-values.yaml --namespace operators --create-namespace
```

**Verify HyperConverged installation:**

```bash
# Check HyperConverged status
oc get hyperconverged -n openshift-cnv

# Check detailed status
oc get hyperconverged kubevirt-hyperconverged -n openshift-cnv -o yaml

# Check KubeVirt components
oc get pods -n openshift-cnv
```

### Creating DataScienceCluster for OpenShift AI

After installing the OpenShift AI operator, you need to create a DataScienceCluster Custom Resource to enable the AI dashboard and ML capabilities.

**Option 1: Enable during installation**

```bash
helm install openshift-operators . \
  --namespace operators \
  --create-namespace \
  --set ai.enabled=true \
  --set ai.datasciencecluster.enabled=true
```

**Option 2: Enable after operator installation**

1. First, install the operator:
   ```bash
   helm install openshift-operators . \
     --namespace operators \
     --create-namespace \
     --set ai.enabled=true
   ```

2. Wait for the operator CSV to be in `Succeeded` phase:
   ```bash
   oc get csv -n redhat-ods-operator -l operators.coreos.com/rhods-operator.redhat-ods-operator=
   ```

3. Upgrade the release to enable DataScienceCluster:
   ```bash
   helm upgrade openshift-operators . \
     --namespace operators \
     --set ai.datasciencecluster.enabled=true
   ```

**Option 3: Customize DataScienceCluster configuration**

Create a custom values file (`my-values.yaml`):

```yaml
ai:
  enabled: true
  datasciencecluster:
    enabled: true
    name: default-dsc
    spec:
      components:
        dashboard:
          managementState: Managed
        workbenches:
          managementState: Managed
        datasciencepipelines:
          managementState: Managed
        modelregistry:
          managementState: Managed
        # Disable components you don't need
        kserve:
          managementState: Removed
        modelmeshserving:
          managementState: Removed
        codeflare:
          managementState: Removed
        ray:
          managementState: Removed
        kueue:
          managementState: Removed
        trainingoperator:
          managementState: Removed
```

Then install:
```bash
helm install openshift-operators . -f my-values.yaml --namespace operators --create-namespace
```

**Verify DataScienceCluster installation:**

```bash
# Check DataScienceCluster status
oc get datasciencecluster -n redhat-ods-operator

# Check detailed status
oc get datasciencecluster default-dsc -n redhat-ods-operator -o yaml

# Check AI dashboard route
oc get route rhods-dashboard -n redhat-ods-applications

# Check OpenShift AI components
oc get pods -n redhat-ods-applications
```

**Access the AI Dashboard:**

```bash
# Get the dashboard route URL
oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}'

# Or use the make target
cd .. && make ai-route
```

### Creating Central for Advanced Cluster Security

After installing the ACS operator, you need to create a Central Custom Resource to deploy the ACS Central management console. This follows the [Red Hat ACS documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.6/html-single/installing/index#install-central-other).

**Option 1: Enable during installation**

```bash
helm install openshift-operators . \
  --namespace operators \
  --create-namespace \
  --set acs.enabled=true \
  --set acs.central.enabled=true
```

**Option 2: Enable after operator installation**

1. First, install the operator:
   ```bash
   helm install openshift-operators . \
     --namespace operators \
     --create-namespace \
     --set acs.enabled=true
   ```

2. Wait for the operator CSV to be in `Succeeded` phase:
   ```bash
   oc get csv -n rhacs-operator -l operators.coreos.com/rhacs-operator.rhacs-operator=
   ```

3. Upgrade the release to enable Central:
   ```bash
   helm upgrade openshift-operators . \
     --namespace operators \
     --set acs.central.enabled=true
   ```

**Option 3: Customize Central configuration**

Create a custom values file (`my-values.yaml`):

```yaml
acs:
  enabled: true
  central:
    enabled: true
    name: stackrox-central-services
    # Central will be deployed in the 'stackrox' namespace
    namespace: stackrox
    exposure:
      route:
        enabled: true
    persistence:
      persistentVolumeClaim:
        claimName: stackrox-db
        size: 20Gi
    resources:
      requests:
        memory: 2Gi
        cpu: 500m
      limits:
        memory: 4Gi
        cpu: 2000m
    egress:
      connectivityPolicy: Online
    scanner:
      analyzer:
        scaling:
          autoScaling: Disabled
          maxReplicas: 2
          minReplicas: 1
          replicas: 1
        resources:
          requests:
            memory: 1Gi
            cpu: 500m
          limits:
            memory: 2Gi
            cpu: 1000m
```

Then install:
```bash
helm install openshift-operators . -f my-values.yaml --namespace operators --create-namespace
```

**Note:** By default, Central is configured to deploy in the `stackrox` namespace. If the namespace doesn't exist, create it first:

```bash
oc create namespace stackrox
```

**Verify Central installation:**

```bash
# Check Central status (takes 10-15 minutes to deploy)
# Note: Central is in the 'stackrox' namespace by default
oc get central -n stackrox

# Wait for Central to be deployed (default namespace is 'stackrox')
oc wait --for=condition=Deployed central/stackrox-central-services -n stackrox --timeout=15m

# Check Central pods
oc get pods -n stackrox -l app=central

# Check Scanner pods
oc get pods -n stackrox -l app=scanner

# Get Central route
oc get route central -n stackrox

# Get admin password
oc get secret central-htpasswd -n stackrox -o jsonpath='{.data.password}' | base64 -d
```

**Access ACS Central UI:**

```bash
# Get the route (default namespace is 'stackrox')
ROUTE=$(oc get route central -n stackrox -o jsonpath='{.spec.host}')

# Get the password
PASSWORD=$(oc get secret central-htpasswd -n stackrox -o jsonpath='{.data.password}' | base64 -d)

echo "ACS Central: https://$ROUTE"
echo "Username: admin"
echo "Password: $PASSWORD"
```

**Note:** According to the [Red Hat ACS documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.6/html-single/installing/index#install-central-other), Central deployment typically takes 10-15 minutes. The default configuration includes:
- Route exposure enabled for OpenShift
- 20Gi persistent volume for database
- Online connectivity policy
- Scanner with 1 replica (auto-scaling disabled)

### Customizing Templates

Each operator chart has its own templates in `charts/<operator>/templates/`. You can customize these templates or add additional resources as needed.

### Adding New Operators

To add a new operator:

1. Create a new chart directory: `charts/new-operator/`
2. Add Chart.yaml, values.yaml, and templates
3. Add the dependency to the parent `Chart.yaml`
4. Add configuration to parent `values.yaml`

## Comparison with Other Installation Methods

| Method | Pros | Cons |
|--------|------|------|
| **Helm** | Version management, templating, easy upgrades | Requires Helm knowledge |
| **Kustomize** | Native Kubernetes, GitOps friendly | Less templating flexibility |
| **Direct YAML** | Simple, no dependencies | Hard to manage at scale |

## Additional Resources

- [Helm Documentation](https://helm.sh/docs/)
- [OpenShift Operator Lifecycle Manager](https://docs.openshift.com/container-platform/latest/operators/understanding/olm/olm-understanding-olm.html)
- [Operator Installation Guide](../README.md)

