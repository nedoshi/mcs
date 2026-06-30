# Simple Operator Installation Guide

This guide provides the **simplest and most reliable** way to install operators without dealing with Kustomize or Helm chart complexity.

## Why This Method?

- ✅ **No Kustomize** - Direct YAML application
- ✅ **No Helm** - Simple `oc apply` commands
- ✅ **No Dependencies** - Just needs `oc` or `kubectl`
- ✅ **Reliable** - Works even when other methods fail
- ✅ **Easy to Debug** - Clear error messages

## Quick Start

### Install GitOps Operator (Recommended First)

```bash
cd install-operators
./install-operator-simple.sh gitops
```

This will:
1. Create the namespace `openshift-gitops-operator`
2. Create the OperatorGroup
3. Create the Subscription
4. Wait for the operator to be ready (15 minutes timeout)

### Install Other Operators

```bash
# Install Pipelines
./install-operator-simple.sh pipelines

# Install RHTAS
./install-operator-simple.sh rhtas

# Install ACS (operator only)
./install-operator-simple.sh acs

# Install ACS with Central Custom Resource
./install-operator-simple.sh acs -c

# Install AI (operator only)
./install-operator-simple.sh ai

# Install AI with DataScienceCluster Custom Resource
./install-operator-simple.sh ai -c

# Install Virtualization
./install-operator-simple.sh virtualization

# Install Developer Hub (operator only)
./install-operator-simple.sh developer-hub

# Install Developer Hub with Backstage Custom Resource
./install-operator-simple.sh developer-hub -c
```

## Available Operators

| Operator | Command | Namespace |
|----------|---------|-----------|
| OpenShift GitOps | `gitops` | `openshift-gitops-operator` |
| OpenShift Pipelines | `pipelines` | `openshift-operators` |
| Red Hat Trusted Artifact Signer | `rhtas` | `openshift-operators` |
| Advanced Cluster Security | `acs` | `rhacs-operator` |
| OpenShift AI | `ai` | `redhat-ods-operator` |
| KubeVirt Virtualization | `virtualization` | `openshift-cnv` |
| Developer Hub | `developer-hub` | `rhdh-operator` |

## Options

### Install Without Waiting

```bash
# Install and return immediately (don't wait for operator to be ready)
./install-operator-simple.sh gitops --no-wait
```

### Custom Timeout

```bash
# Wait up to 10 minutes (600 seconds)
./install-operator-simple.sh gitops --timeout 600
```

### Create Custom Resources After Installation

Some operators require Custom Resources (CRs) to be created after the operator is installed:

```bash
# Install ACS operator and automatically create Central CR
./install-operator-simple.sh acs -c

# Install AI operator and automatically create DataScienceCluster CR
./install-operator-simple.sh ai -c

# Install Developer Hub and automatically create Backstage CR
./install-operator-simple.sh developer-hub -c
```

**Available Custom Resources:**
- **ACS**: `central.yaml` and `secured-cluster.yaml`
- **AI**: `datasciencecluster.yaml`
- **Developer Hub**: `backstage.yaml`
- **Virtualization**: No CR file in operators folder (use Helm for HyperConverged)

**Note:** The `-c` flag will:
1. Wait for the operator to be ready (CSV in Succeeded phase)
2. Automatically detect and apply any CR YAML files in the operator directory
3. Skip namespace, operatorgroup, subscription, and kustomization files

## Manual Installation (If Script Fails)

If the script doesn't work, you can install manually:

### Step 1: Create Namespace

```bash
oc apply -f operators/gitops/namespace.yaml
```

### Step 2: Create OperatorGroup

```bash
oc apply -f operators/gitops/operatorgroup.yaml
```

### Step 3: Create Subscription

```bash
oc apply -f operators/gitops/subscription.yaml
```

### Step 4: Wait for Operator

```bash
oc wait --for=condition=Succeeded csv \
  -n openshift-gitops-operator \
  -l operators.coreos.com/openshift-gitops-operator.openshift-gitops-operator= \
  --timeout=15m
```

## Verification

After installation, verify the operator is working:

```bash
# Check subscription
oc get subscription openshift-gitops-operator -n openshift-gitops-operator

# Check CSV status
oc get csv -n openshift-gitops-operator

# Check operator pods
oc get pods -n openshift-gitops-operator

# Check for Argo CD instance (GitOps creates this automatically)
oc get argocd -n openshift-gitops
```

## Troubleshooting

### Operator Not Installing

1. **Check subscription status:**
   ```bash
   oc describe subscription openshift-gitops-operator -n openshift-gitops-operator
   ```

2. **Check install plan:**
   ```bash
   oc get installplan -n openshift-gitops-operator
   ```

3. **Check CSV:**
   ```bash
   oc get csv -n openshift-gitops-operator
   oc describe csv -n openshift-gitops-operator
   ```

4. **Check operator logs:**
   ```bash
   oc logs -n openshift-gitops-operator -l app=openshift-gitops-operator
   ```

### Namespace Already Exists

If the namespace already exists, the script will continue. This is normal and safe.

### Subscription Already Exists

If you get an error about subscription already existing:

```bash
# Delete existing subscription
oc delete subscription openshift-gitops-operator -n openshift-gitops-operator

# Then run the script again
./install-operator-simple.sh gitops
```

### Operator Stuck in Installing

If the operator CSV is stuck in "Installing" phase:

```bash
# Check for errors
oc describe csv -n openshift-gitops-operator

# Check operator pod logs
oc logs -n openshift-gitops-operator -l app=openshift-gitops-operator

# Check events
oc get events -n openshift-gitops-operator --sort-by='.lastTimestamp'
```

## What Gets Installed?

### Basic Installation (without `-c` flag)

For any operator:

1. **Namespace:** Operator-specific namespace
2. **OperatorGroup:** Targets the namespace
3. **Subscription:** Operator subscription (from `redhat-operators` catalog)
4. **CSV:** Automatically created by OLM
5. **Custom Resources:** NOT created (operator only)

### With Custom Resources (`-c` flag)

For operators that have CR files (ACS, AI, Developer Hub):

1. Everything from basic installation, plus:
2. **Custom Resources:** Automatically created after operator is ready
   - **ACS**: Central and SecuredCluster (if files exist)
   - **AI**: DataScienceCluster
   - **Developer Hub**: Backstage

### GitOps Operator Specifically

1. **Namespace:** `openshift-gitops-operator`
2. **OperatorGroup:** `openshift-gitops-operator` (targets the namespace)
3. **Subscription:** `openshift-gitops-operator` (from `redhat-operators` catalog)
4. **CSV:** Automatically created by OLM
5. **Argo CD Instance:** Automatically created by the operator (no CR file needed)

## Accessing GitOps (Argo CD)

After installation, get the Argo CD route:

```bash
# Get the route
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'

# Get admin password
oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d
```

Default username: `admin`

## Uninstalling

To uninstall an operator:

```bash
# Delete subscription
oc delete subscription openshift-gitops-operator -n openshift-gitops-operator

# Delete operatorgroup
oc delete operatorgroup openshift-gitops-operator -n openshift-gitops-operator

# Delete CSV (optional, for complete removal)
oc delete csv -n openshift-gitops-operator -l operators.coreos.com/openshift-gitops-operator.openshift-gitops-operator=

# Delete namespace (optional, only if empty)
oc delete namespace openshift-gitops-operator
```

## Comparison with Other Methods

| Method | Complexity | Reliability | Best For |
|--------|-----------|-------------|----------|
| **Simple Script** (This) | ⭐ Low | ⭐⭐⭐ High | Quick installs, troubleshooting |
| Kustomize | ⭐⭐ Medium | ⭐⭐ Medium | GitOps workflows |
| Helm Charts | ⭐⭐⭐ High | ⭐⭐ Medium | Complex deployments |

## Next Steps

After installing GitOps operator:

1. **Access Argo CD UI** (see "Accessing GitOps" above)
2. **Install other operators** using the same method
3. **Set up GitOps workflows** to manage operators declaratively

For more advanced usage, see:
- `README.md` - Full documentation
- `helm/README.md` - Helm chart documentation (if you want to use Helm later)

