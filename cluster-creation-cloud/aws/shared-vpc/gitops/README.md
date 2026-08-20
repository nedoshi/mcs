# OpenShift GitOps — ROSA HCP & ARO Platform Management

Production-grade GitOps configuration for managing ROSA HCP (AWS) and ARO (Azure) OpenShift clusters using Red Hat Advanced Cluster Management (ACM) and Argo CD.

This directory lives alongside the `terraform/` directory in the same repository. Terraform handles **Day 0–1** (infrastructure provisioning), and GitOps handles **Day 2+** (platform configuration, policies, ongoing drift remediation).

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            ACM Hub Cluster                                  │
│                                                                             │
│  ┌──────────────────┐   ┌──────────────────┐   ┌────────────────────────┐  │
│  │ ManagedClusterSets│   │    Placements     │   │    GitOpsCluster       │  │
│  │ - rosa-clusters   │──▶│ - rosa-production │──▶│ - argo-acm-clusters    │  │
│  │ - aro-clusters    │   │ - aro-production  │   │ - argo-acm-rosa        │  │
│  │ - production-     │   │ - all-production  │   │ - argo-acm-aro         │  │
│  │   clusters        │   │ - rosa-eu         │   └─────────┬──────────────┘  │
│  │ - eu-clusters     │   │ - all-managed-    │             │                │
│  └──────────────────┘   │   clusters        │             ▼                │
│                          └──────────────────┘   ┌────────────────────────┐  │
│                                                  │   Argo CD (openshift-  │  │
│                                                  │   gitops namespace)    │  │
│                                                  │                        │  │
│  ┌──────────────────────────────────────────────▶│  ApplicationSets:      │  │
│  │  Git Repo (this repo)                         │  - baseline (all)      │  │
│  │  ┌─────────────────┐                          │  - rosa-overlay        │  │
│  │  │ gitops/charts/   │                         │  - aro-overlay         │  │
│  │  │ gitops/cluster-  │                         └─────────┬──────────────┘  │
│  │  │   values/        │                                   │                │
│  │  │ gitops/policies/ │                                   │                │
│  │  └─────────────────┘                                    │                │
│  └─────────────────────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────────────────────┘
         │                               │                          │
         ▼                               ▼                          ▼
┌─────────────────┐           ┌─────────────────┐       ┌─────────────────┐
│  ROSA Cluster    │           │  ROSA Cluster    │       │   ARO Cluster    │
│  Baseline:       │           │  Baseline:       │       │  Baseline:       │
│  - RBAC          │           │  - RBAC          │       │  - RBAC          │
│  - Monitoring    │           │  - Monitoring    │       │  - Monitoring    │
│  - NetworkPolicy │           │  - NetworkPolicy │       │  - NetworkPolicy │
│  ROSA Overlay:   │           │  ROSA Overlay:   │       │  ARO Overlay:    │
│  - StorageClass  │           │  - StorageClass  │       │  - StorageClass  │
│  - MachineConfig │           │  - MachineConfig │       │  - OAuth (if     │
│                  │           │                  │       │    enabled)      │
└─────────────────┘           └─────────────────┘       └─────────────────┘
```

## Terraform + GitOps Ownership Boundaries

This repo uses a clear **Day 0–1 / Day 2** split to avoid resource conflicts:

| Resource | Owner | Notes |
|----------|-------|-------|
| VPC, subnets, NAT, DNS | **Terraform** (`shared-vpc` module) | Infrastructure lifecycle |
| ROSA HCP cluster | **Terraform** (`rosa-cluster` module) | Cluster creation/destroy |
| KMS key | **Terraform** (`rosa-kms` module) | Key referenced by GitOps StorageClass values |
| Entra ID app + IdP | **Terraform** (`rosa-entra-idp` module) | OAuth managed via RHCS API |
| Demote gp3-csi default | **Terraform** (`rosa-post-install` module) | One-time patch |
| StorageClasses (KMS) | **GitOps** (`rosa-platform-config` chart) | Ongoing drift remediation |
| RBAC, namespaces | **GitOps** (`cluster-baseline` chart) | Across all clusters |
| NetworkPolicies | **GitOps** (`cluster-baseline` chart) | Across all clusters |
| Monitoring rules | **GitOps** (`cluster-baseline` chart) | Across all clusters |
| Pod security | **GitOps** (`cluster-baseline` chart) | Across all clusters |
| MachineConfig | **GitOps** (`rosa-platform-config` chart) | ROSA-specific |
| ACM policies | **GitOps** (`policies/`) | Compliance enforcement |
| OAuth (ARO only) | **GitOps** (`aro-platform-config` chart) | ARO clusters without Terraform IdP |

**Important:** For ROSA clusters where Terraform manages the Entra ID IdP, set `identityProvider.enabled: false` in the cluster-values file to prevent conflict. The GitOps OAuth template is available for ARO clusters or any cluster not using the Terraform IdP module.

### Cross-Cloud DR Placements

For ARO ↔ ROSA HCP disaster recovery pairs, additional ManagedClusterSets and Placements are defined in `bootstrap/acm/`:

| Placement | Labels | Purpose |
|-----------|--------|---------|
| `cross-cloud-dr` | `dr-pair: aro-rosa-cross-cloud` | Both clusters in a DR pair |
| `aro-primary` | `dr-role: primary`, `platform: aro` | ARO primary |
| `rosa-dr-standby` | `dr-role: dr-standby`, `platform: rosa` | ROSA DR standby |

See [Cross-Cloud DR ACM Setup](../../../operations/disaster-recovery/acm-gitops-setup.md) and example cluster values (`prod-aro-primary.yaml`, `prod-rosa-dr.yaml`).

## Directory Structure

```
gitops/
├── bootstrap/
│   ├── acm/                           # ACM resources (apply in numbered order)
│   │   ├── 01-cluster-sets.yaml       #   ManagedClusterSets
│   │   ├── 02-cluster-set-bindings.yaml
│   │   ├── 03-placements.yaml         #   Placement rules for cluster targeting
│   │   ├── 04-gitops-clusters.yaml    #   GitOpsCluster links ACM → Argo CD
│   │   └── 05-gitops-operator.yaml    #   OpenShift GitOps operator subscription
│   ├── argocd/
│   │   ├── appprojects.yaml           #   AppProject with resource whitelist
│   │   └── applicationsets.yaml       #   3 ApplicationSets (baseline + overlays)
│   └── policies/
│       └── policy-placement-bindings.yaml
├── charts/
│   ├── cluster-baseline/              # Shared config for ALL clusters
│   ├── rosa-platform-config/          # ROSA-specific: StorageClass, MachineConfig
│   └── aro-platform-config/           # ARO-specific: StorageClass, OAuth
├── cluster-values/
│   ├── baseline/                      # Per-cluster baseline overrides
│   ├── rosa/                          # Per-cluster ROSA values (KMS key ARN, etc.)
│   └── aro/                           # Per-cluster ARO values
└── policies/                          # ACM governance policies
    ├── compliance/
    ├── configuration/
    └── security/
```

## How ApplicationSets Work

| ApplicationSet | Chart Path | Placement | Deploys |
|----------------|------------|-----------|---------|
| `platform-baseline-helm` | `gitops/charts/cluster-baseline` | `all-production` | RBAC, monitoring, networking, security, namespaces |
| `platform-rosa-overlay-helm` | `gitops/charts/rosa-platform-config` | `rosa-production` | EBS StorageClass (KMS), MachineConfig (journald) |
| `platform-aro-overlay-helm` | `gitops/charts/aro-platform-config` | `aro-production` | Azure Disk StorageClass, OAuth |

All ApplicationSets use `ServerSideApply=true` and automated sync with prune, self-heal, and retry.

## End-to-End Deployment Order

### Phase 1: Terraform — Day 0–1

```bash
cd terraform
terraform init
terraform apply -var-file=environments/us-east-1/demo1.tfvars
```

See `terraform/README.md` for the full step-by-step guide covering VPC, cluster, Entra IdP, and post-install.

### Phase 2: GitOps Bootstrap — Day 2 Setup (on ACM hub)

```bash
# 1. Install GitOps operator
oc apply -f gitops/bootstrap/acm/05-gitops-operator.yaml

# 2. Wait for operator
oc get csv -n openshift-operators | grep gitops

# 3. Apply ACM resources (in order)
oc apply -f gitops/bootstrap/acm/01-cluster-sets.yaml
oc apply -f gitops/bootstrap/acm/02-cluster-set-bindings.yaml
oc apply -f gitops/bootstrap/acm/03-placements.yaml
oc apply -f gitops/bootstrap/acm/04-gitops-clusters.yaml

# 4. Apply Argo CD config
oc apply -f gitops/bootstrap/argocd/appprojects.yaml
oc apply -f gitops/bootstrap/argocd/applicationsets.yaml

# 5. Apply policy framework
oc apply -f gitops/bootstrap/policies/policy-placement-bindings.yaml
oc apply -f gitops/policies/compliance/
oc apply -f gitops/policies/configuration/
oc apply -f gitops/policies/security/
```

### Phase 3: Import Clusters into ACM

Import clusters via the Terraform `rosa-acm-import` module or manually:

```bash
oc apply -f - <<EOF
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: <cluster-name>
  labels:
    cloud: Amazon
    vendor: OpenShift
    platform: rosa
    region: us-east-1
    env: production
    cluster.open-cluster-management.io/clusterset: rosa-clusters
spec:
  hubAcceptsClient: true
EOF
```

### Phase 4: Verify

```bash
oc get managedclusters
oc get placements -n openshift-gitops
oc get applications -n openshift-gitops
oc get policies -n policies
```

## Adding a New ROSA Cluster

1. **Provision with Terraform** — create `.tfvars`, run `terraform apply`
2. **Create cluster-values files:**
   - `gitops/cluster-values/baseline/<cluster-name>.yaml`
   - `gitops/cluster-values/rosa/<cluster-name>.yaml` (set `identityProvider.enabled: false` if Terraform manages IdP)
3. **Import into ACM** with labels: `platform: rosa`, `env: production`, `clusterset: rosa-clusters`
4. **Commit and push** — Argo CD picks up the cluster automatically

## Configuration Reference

### ROSA Chart Values

| Key | Default | Description |
|-----|---------|-------------|
| `storage.kmsKeyArn` | `""` (required) | AWS KMS key ARN — get from `terraform output kms_key_arn` |
| `storage.className` | `gp3-csi-kms` | StorageClass name |
| `storageRetain.enabled` | `true` | Create Retain-policy variant |
| `identityProvider.enabled` | `true` | **Set to `false` when Terraform manages Entra IdP** |
| `machineConfig.journald.enabled` | `true` | journald tuning on workers |

### Baseline Chart Values

| Key | Default | Description |
|-----|---------|-------------|
| `rbac.adminGroups` | `[cluster-admins, platform-admins]` | Groups bound to cluster-admin |
| `monitoring.enabled` | `true` | PrometheusRules and AlertmanagerConfig |
| `networking.defaultDenyAll` | `true` | Default-deny NetworkPolicies per namespace |

## Customization

Before deploying, update the Git repository URL in:
- `gitops/bootstrap/argocd/appprojects.yaml` — `sourceRepos`
- `gitops/bootstrap/argocd/applicationsets.yaml` — all `repoURL` fields

Replace `https://github.com/your-org/tf-rosa-shared-vpc.git` with your actual repository URL.
