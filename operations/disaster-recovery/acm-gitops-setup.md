# ACM + GitOps Setup — Cross-Cloud DR (ARO ↔ ROSA HCP)

Register primary and DR clusters in Red Hat Advanced Cluster Management (ACM) and deploy ApplicationSets so **both clusters reconcile continuously** before a disaster.

**Related:** [GitOps README](../../cluster-creation-cloud/aws/shared-vpc/gitops/README.md) · [Cross-Cloud DR Guide](../../docs/guide/cross-cloud-dr-aro-rosa/README.md)

---

## Prerequisites

- ACM Hub cluster (recommended: on **DR cloud** or neutral cluster — not solely on primary)
- Primary and DR clusters provisioned via [cross-cloud-dr tfvars](../../cluster-creation-cloud/cross-cloud-dr/environments/)
- Hub cluster admin access; `oc` logged into hub

---

## Step 1: Label Clusters at Import

When importing clusters into ACM, apply labels matching Terraform tags:

### ARO Primary (Scenario A)

```yaml
labels:
  env: production
  platform: aro
  dr-role: primary
  dr-pair: aro-rosa-cross-cloud
```

### ROSA DR Standby (Scenario A)

```yaml
labels:
  env: production
  platform: rosa
  dr-role: dr-standby
  dr-pair: aro-rosa-cross-cloud
```

Reverse `dr-role` labels for Scenario B (ROSA primary, ARO DR).

---

## Step 2: Apply ACM Bootstrap

From the hub cluster:

```bash
cd cluster-creation-cloud/aws/shared-vpc/gitops/bootstrap/acm

oc apply -f 01-cluster-sets.yaml
oc apply -f 02-cluster-set-bindings.yaml
oc apply -f 03-placements.yaml
oc apply -f 04-gitops-clusters.yaml
oc apply -f 05-gitops-operator.yaml
```

New cluster sets and placements for cross-cloud DR:

| Resource | Purpose |
|----------|---------|
| `cross-cloud-dr-clusters` | All clusters in the DR pair |
| `aro-primary-clusters` | ARO primary only |
| `rosa-dr-clusters` | ROSA DR standby only |
| Placement `cross-cloud-dr` | Targets both by `dr-pair: aro-rosa-cross-cloud` |

---

## Step 3: Deploy Argo CD ApplicationSets

```bash
cd ../argocd
oc apply -f appprojects.yaml
oc apply -f applicationsets.yaml
```

ApplicationSets deploy:

| ApplicationSet | Chart | Placement |
|----------------|-------|-----------|
| `platform-baseline-helm` | `cluster-baseline` | `all-production` |
| `platform-rosa-overlay-helm` | `rosa-platform-config` | `rosa-production` |
| `platform-aro-overlay-helm` | `aro-platform-config` | `aro-production` |

---

## Step 4: Create Cluster Values

Copy templates and fill per cluster:

```bash
# Baseline (all clusters)
cp cluster-values/baseline/_template.yaml cluster-values/baseline/prod-aro-primary.yaml
cp cluster-values/baseline/_template.yaml cluster-values/baseline/prod-rosa-dr.yaml

# Cloud overlays
cp cluster-values/aro/_template.yaml cluster-values/aro/prod-aro-primary.yaml
cp cluster-values/rosa/_template.yaml cluster-values/rosa/prod-rosa-dr.yaml
```

Example DR cluster values are in:

- [`cluster-values/baseline/prod-rosa-dr.yaml`](../../cluster-creation-cloud/aws/shared-vpc/gitops/cluster-values/baseline/prod-rosa-dr.yaml)
- [`cluster-values/rosa/prod-rosa-dr.yaml`](../../cluster-creation-cloud/aws/shared-vpc/gitops/cluster-values/rosa/prod-rosa-dr.yaml)

---

## Step 5: Verify Continuous Reconciliation

On the **DR cluster** (must pass before go-live):

```bash
# Switch context to DR cluster
oc get applications -n openshift-gitops
oc get applicationsets -n openshift-gitops

# Confirm sync status Healthy
argocd app list  # if CLI configured
```

DR cluster must show `Synced` / `Healthy` **before** any failover event.

---

## Hub Survivability

| Option | Pros | Cons |
|--------|------|------|
| Hub on DR cloud | Survives primary cloud outage | Primary cloud ops depend on DR path |
| Hub on neutral 3rd cluster | Independent of both | Additional cluster cost |
| Hub on primary | Simplest Day 0 | Hub down if primary cloud fails — document break-glass manual GitOps |

Document chosen option in your DR runbook.

---

## Validation Checklist

- [ ] Both clusters imported with correct `dr-pair` and `dr-role` labels
- [ ] Placements `cross-cloud-dr`, `aro-primary`, `rosa-dr-standby` show expected clusters
- [ ] ApplicationSets syncing to DR cluster (not just primary)
- [ ] Cluster values files committed for both clusters
- [ ] No Terraform/GitOps ownership conflict on OAuth (see GitOps README)
