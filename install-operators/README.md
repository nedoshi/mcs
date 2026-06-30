# OpenShift Operators Management

This directory contains tools for managing OpenShift operators using GitOps patterns with Kustomize and Argo CD.

## 🚀 Quick Start (Simplest Method - Recommended)

**Having issues with Kustomize or Helm?** Use the simple installation script that directly applies YAML files:

```bash
# Install GitOps operator (recommended first)
./install-operator-simple.sh gitops

# Install other operators
./install-operator-simple.sh pipelines
./install-operator-simple.sh acs
./install-operator-simple.sh ai
./install-operator-simple.sh rhtas
./install-operator-simple.sh virtualization
./install-operator-simple.sh developer-hub
```

**Why this method?**
- ✅ No Kustomize complexity
- ✅ No Helm chart dependencies
- ✅ Direct `oc apply` - most reliable
- ✅ Easy to debug
- ✅ Works when other methods fail

See [INSTALL_SIMPLE.md](./INSTALL_SIMPLE.md) for complete documentation.

## Installation Methods

This repository supports multiple installation methods:

1. **Simple Script** (Recommended) - Direct YAML application, no dependencies
2. **Kustomize** - For GitOps workflows
3. **Helm Charts** - For complex deployments
4. **Makefile** - For manifest generation

## Features

- **Operator Manifest Generation**: Generate operator manifests (Namespace, OperatorGroup, Subscription)
- **Environment Overlays**: Support for dev, staging, and prod environments with environment-specific configurations
- **Argo CD Integration**: Generate Argo CD Application manifests for automated deployments
- **CSV Health Validation**: Validate ClusterServiceVersion health for all operators

## Prerequisites

- `kubectl` or `oc` - Kubernetes/OpenShift CLI (for simple script)
- `make` - Build automation tool (for Makefile method)
- Access to an OpenShift cluster (for validation)

## Quick Start (Makefile Method)

### Generate All Manifests

```bash
make all
```

This will generate:
- Operator manifests in `operators/`
- Environment overlays in `overlays/`
- Argo CD Application manifests in `argocd/`

### Individual Targets

#### Generate Operators Only

```bash
make generate-operators
```

#### Generate Environment Overlays

```bash
make generate-overlays
```

This creates overlays for:
- `overlays/dev/` - Development environment
- `overlays/staging/` - Staging environment
- `overlays/prod/` - Production environment

#### Generate Argo CD Applications

```bash
make generate-argocd
```

This creates Argo CD Application manifests for each environment.

#### Validate CSV Health

```bash
make validate-csv
```

Validates that all ClusterServiceVersions are in `Succeeded` phase.

For detailed validation output:

```bash
make validate-csv-detailed
```

## Installing Generated Manifests

After generating manifests with `make all` or `make generate-operators`, you can install them using one of the following methods:

### Direct Installation (kubectl/oc)

#### Option 1: Install All Operators (Base Configuration)

**Note:** Some operators share the same namespace (e.g., `pipelines` and `rhtas` both use `openshift-operators`). Due to kustomize limitations with duplicate resources, you have two options:

**Option 1a: Apply operators individually (Recommended)**

Apply each operator separately to avoid namespace conflicts:

```bash
oc apply -k operators/pipelines/
oc apply -k operators/rhtas/
oc apply -k operators/acs/
oc apply -k operators/ai/
oc apply -k operators/virtualization/
oc apply -k operators/developer-hub/
oc apply -k operators/gitops/
```

**Option 1b: Apply all at once (may require namespace handling)**

If you want to apply all at once, you may need to handle duplicate namespaces. The `openshift-operators` namespace is typically pre-existing in OpenShift clusters, so you can apply all operators:

```bash
oc apply -k operators/ --server-side=true
```

Or using kubectl:

```bash
kubectl apply -k operators/
```

#### Option 2: Install with Environment Overlay

Apply operators with environment-specific configurations:

**Development Environment:**
```bash
oc apply -k overlays/dev/
```

**Staging Environment:**
```bash
oc apply -k overlays/staging/
```

**Production Environment:**
```bash
oc apply -k overlays/prod/
```

#### Option 3: Install Individual Operators

You can also install operators individually:

```bash
# Install a specific operator
oc apply -k operators/pipelines/
oc apply -k operators/acs/
oc apply -k operators/ai/
# etc.
```

### Verify Installation

After applying the manifests, verify that the operators are installing:

```bash
# Check operator subscriptions
oc get subscription -A

# Check ClusterServiceVersions (CSVs)
oc get csv -A

# Validate CSV health
make validate-csv
```

The operators will be installed via Operator Lifecycle Manager (OLM). Installation typically takes 5-15 minutes depending on the operator.

### Helm Installation

Install all operators using Helm charts:

```bash
cd helm
helm dependency update
helm install openshift-operators . --namespace operators --create-namespace
```

**Benefits of Helm installation:**
- Version management and templating
- Easy upgrades and rollbacks
- Environment-specific values files
- Enable/disable operators easily

**Quick Start:**
```bash
# Install with default values
cd helm && helm dependency update && helm install openshift-operators . --namespace operators --create-namespace

# Install with production values
helm install openshift-operators . -f values-prod.yaml --namespace operators --create-namespace

# Install specific operators only
helm install openshift-operators . --set pipelines.enabled=true --set acs.enabled=true --namespace operators --create-namespace
```

For detailed Helm installation instructions, see [helm/README.md](./helm/README.md).

## Makefile Targets

| Target | Description |
|--------|-------------|
| `help` | Show available targets and descriptions |
| `all` | Build everything (operators, overlays, Argo CD) |
| `generate-operators` | Generate operator manifests |
| `generate-overlays` | Generate environment overlays |
| `generate-argocd` | Generate Argo CD Application manifests |
| `validate-csv` | Validate CSV health for all operators |
| `validate-csv-detailed` | Detailed CSV validation with status reporting |
| `validate-all` | Run all validation checks |
| `clean` | Remove all generated files |
| `build` | Build all manifests (operators, overlays, Argo CD) |
| `install-acs-central` | Install ACS Central (requires operator installed) |
| `install-acs-secured-cluster` | Install ACS SecuredCluster (connects cluster) |
| `acs-info` | Get ACS Central route and connection information |
| `acs-route` | Get ACS Central route URL |
| `acs-password` | Get ACS Central admin password |
| `install-ai-datasciencecluster` | Install DataScienceCluster for AI dashboard |
| `ai-info` | Get OpenShift AI dashboard route and connection info |
| `ai-route` | Get OpenShift AI dashboard route URL |
| `install-backstage` | Install Developer Hub (Backstage) instance |
| `backstage-info` | Get Developer Hub route and connection info |
| `backstage-route` | Get Developer Hub route URL |
| `install-tpa` | Install Trusted Profile Analyzer (TPA) service |
| `tpa-info` | Get TPA route and connection info |
| `tpa-route` | Get TPA route URL |

## Directory Structure

```
install-operators/
├── Makefile                 # Main Makefile
├── README.md               # This file
├── script.sh               # Original script (deprecated, use Makefile)
├── operators/              # Base operator manifests (Kustomize)
│   ├── pipelines/
│   ├── rhtas/
│   ├── acs/
│   ├── ai/
│   ├── virtualization/
│   ├── developer-hub/
│   ├── gitops/
│   └── kustomization.yaml
├── helm/                    # Helm charts for operators
│   ├── Chart.yaml          # Parent chart
│   ├── values.yaml         # Default values
│   ├── values-dev.yaml     # Development values
│   ├── values-prod.yaml    # Production values
│   ├── charts/             # Operator subcharts
│   │   ├── pipelines/
│   │   ├── rhtas/
│   │   ├── acs/
│   │   ├── ai/
│   │   ├── virtualization/
│   │   ├── developer-hub/
│   │   └── gitops/
│   └── README.md           # Helm installation guide
├── overlays/               # Environment-specific overlays (Kustomize)
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   └── patches.yaml
│   ├── staging/
│   │   ├── kustomization.yaml
│   │   └── patches.yaml
│   └── prod/
│       ├── kustomization.yaml
│       └── patches.yaml
└── argocd/                 # Argo CD Application manifests
    ├── operators-dev.yaml
    ├── operators-staging.yaml
    ├── operators-prod.yaml
    └── kustomization.yaml
```

## Environment Overlays

Environment overlays allow you to customize operator configurations per environment:

- **Dev**: Fast channel for quicker updates
- **Staging**: Stable channel for testing
- **Prod**: Stable channel with Manual install plan approval

You can customize the patches in `overlays/<env>/patches.yaml` to:
- Override subscription channels
- Change install plan approval strategy
- Add environment-specific labels
- Modify resource requirements

## Argo CD Integration

The generated Argo CD Application manifests include:

- Automated sync policies (with manual approval for prod)
- Health checks for all ClusterServiceVersions
- Retry policies for failed syncs
- Self-healing enabled

### Deploying with Argo CD

1. Set environment variables:
   ```bash
   export ARGOCD_REPO_URL=https://github.com/your-org/your-repo
   export ARGOCD_REVISION=main
   ```

2. Apply the Argo CD Application:
   ```bash
   envsubst < argocd/operators-dev.yaml | oc apply -f -
   ```

3. Or use kustomize to apply all:
   ```bash
   oc apply -k argocd/
   ```

## Advanced Cluster Security (ACS) Installation

### Quick Start

```bash
# 1. Verify ACS operator is installed
make validate-csv-acs

# 2. Install ACS Central
make install-acs-central

# 3. Get connection information
make acs-info

# 4. (Optional) Connect cluster for monitoring
make install-acs-secured-cluster
```

### Detailed Documentation

- [ACS Quick Start Guide](./docs/ACS_QUICK_START.md) - Quick reference
- [ACS Cluster Connection Guide](./docs/ACS_CLUSTER_CONNECTION.md) - Connect additional clusters

### ACS Components

- **Central**: Management console (UI and API)
- **Scanner**: Image vulnerability scanning
- **SecuredCluster**: Runtime security monitoring (sensor)

## OpenShift AI (Data Science) Installation

### Quick Start

```bash
# 1. Verify OpenShift AI operator is installed
make validate-csv-ai

# 2. Install DataScienceCluster (enables dashboard)
make install-ai-datasciencecluster

# 3. Get dashboard connection information
make ai-info

# 4. Access the dashboard using the route URL
```

### Detailed Documentation

- [AI Dashboard Guide](./docs/AI_DASHBOARD_GUIDE.md) - Complete guide for accessing the AI dashboard

### OpenShift AI Components

- **Dashboard**: Main UI for AI/ML capabilities
- **Workbenches**: Jupyter notebook environments
- **Data Science Pipelines**: ML workflow orchestration
- **Model Registry**: Model versioning and management

## Developer Hub (Backstage) Installation

### Quick Start

```bash
# 1. Verify Developer Hub operator is installed
make validate-csv-developer-hub

# 2. Install Backstage instance
make install-backstage

# 3. Get connection information
make backstage-info

# 4. Access the dashboard using the route URL shown
```

### Detailed Documentation

- [Backstage Guide](./docs/BACKSTAGE_GUIDE.md) - Complete guide for Developer Hub

### Developer Hub Components

- **Backstage Application**: Main UI for software catalog and developer tools
- **PostgreSQL Database**: Local database for Backstage data
- **Software Catalog**: Centralized view of services and applications
- **Software Templates**: Scaffold new projects
- **TechDocs**: Technical documentation integration

## Trusted Profile Analyzer (TPA) Installation

### Quick Start

```bash
# 1. Install TPA service
make install-tpa

# 2. Get connection information
make tpa-info

# 3. Access the dashboard using the route URL shown
```

### Detailed Documentation

- [TPA Guide](./docs/TPA_GUIDE.md) - Complete guide for Trusted Profile Analyzer

### TPA Components

- **TPA Service**: SBOM and VEX analysis service
- **SBOM Storage**: 10Gi PVC for SBOM data
- **VEX Storage**: 5Gi PVC for VEX documents
- **RESTful API**: Programmatic access for CI/CD integration

## CSV Health Validation

The validation targets check that all ClusterServiceVersions are in the `Succeeded` phase:

```bash
# Quick validation
make validate-csv

# Detailed validation with status
make validate-csv-detailed
```

Validation checks:
- ✅ Pipelines operator (openshift-pipelines-operator)
- ✅ RHTAS operator (trusted-artifact-signer-operator)
- ✅ ACS operator (rhacs-operator)
- ✅ AI operator (rhods-operator)
- ✅ Virtualization operator (kubevirt-hyperconverged)
- ✅ Developer Hub operator (rhdh)
- ✅ GitOps operator (openshift-gitops-operator)

## Customization

### Adding a New Operator

1. Add operator variables to the Makefile:
   ```makefile
   OPERATOR_NEW_NAME := new-operator
   OPERATOR_NEW_NAMESPACE := new-operator-ns
   OPERATOR_NEW_SUBSCRIPTION := new-operator
   OPERATOR_NEW_CHANNEL := stable
   ```

2. Add a generation target:
   ```makefile
   generate-operator-new:
       @echo "  Creating new operator"
       # ... generation logic
   ```

3. Update the `OPERATORS` variable and add to `generate-operators` target

4. Add validation target:
   ```makefile
   validate-csv-new:
       @echo "  Checking new operator CSV..."
       # ... validation logic
   ```

### Modifying Environment Overlays

Edit the patch files in `overlays/<env>/patches.yaml` to customize:
- Subscription channels
- Install plan approval
- Resource limits
- Labels and annotations

## Troubleshooting

### CSV Validation Fails

If CSV validation fails, check:
1. Operator subscription status: `oc get subscription -A`
2. Install plan status: `oc get installplan -A`
3. CSV phase: `oc get csv -A`
4. Operator pod status: `oc get pods -n <operator-namespace>`

### ACS Operator Deployment Failure

If the ACS operator CSV shows "InstallCheckFailed" with deployment timeout:

1. **Check deployment and pods:**
   ```bash
   oc get deployment rhacs-operator-controller-manager -n rhacs-operator
   oc get pods -n rhacs-operator -l app=rhacs-operator
   oc describe pod -n rhacs-operator -l app=rhacs-operator
   ```

2. **Check pod logs:**
   ```bash
   oc logs -n rhacs-operator -l app=rhacs-operator --tail=100
   ```

3. **Check for resource constraints:**
   ```bash
   oc describe nodes
   oc get resourcequota -n rhacs-operator
   ```

4. **Check events for errors:**
   ```bash
   oc get events -n rhacs-operator --sort-by='.lastTimestamp'
   ```

5. **Common fixes:**
   - Delete and reinstall: `oc delete csv rhacs-operator.v4.9.2 -n rhacs-operator && oc delete subscription rhacs-operator -n rhacs-operator`
   - Check image pull secrets: `oc get sa rhacs-operator-controller-manager -n rhacs-operator -o yaml`
   - Verify cluster resources: `oc top nodes`
   - Check for taints/tolerations: `oc describe nodes | grep -i taint`

6. **Verify CRDs are installed:**
   ```bash
   oc get crd | grep stackrox
   # Should show: centrals.platform.stackrox.io, securedclusters.platform.stackrox.io, securitypolicies.config.stackrox.io
   ```

### Argo CD Sync Issues

1. Check Argo CD application status: `oc get application -n argocd`
2. Review sync logs: `oc logs -n argocd -l app.kubernetes.io/name=argocd-application-controller`
3. Verify repository access and permissions

## Migration from script.sh

The original `script.sh` has been replaced by the Makefile. To migrate:

1. Remove old generated files: `make clean`
2. Regenerate with Makefile: `make all`
3. Review and commit the new structure

The Makefile provides the same functionality with additional features:
- Environment overlays
- Argo CD integration
- CSV health validation
- Better organization and maintainability

