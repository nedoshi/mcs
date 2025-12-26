# OpenShift Operators Management

This directory contains tools for managing OpenShift operators using GitOps patterns with Kustomize and Argo CD.

## Features

- **Operator Manifest Generation**: Generate operator manifests (Namespace, OperatorGroup, Subscription)
- **Environment Overlays**: Support for dev, staging, and prod environments with environment-specific configurations
- **Argo CD Integration**: Generate Argo CD Application manifests for automated deployments
- **CSV Health Validation**: Validate ClusterServiceVersion health for all operators

## Prerequisites

- `make` - Build automation tool
- `kubectl` or `oc` - Kubernetes/OpenShift CLI
- Access to an OpenShift cluster (for validation)

## Quick Start

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
├── operators/              # Base operator manifests
│   ├── pipelines/
│   ├── rhtas/
│   ├── acs/
│   ├── ai/
│   ├── virtualization/
│   └── kustomization.yaml
├── overlays/               # Environment-specific overlays
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

