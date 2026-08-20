# Identity & Container Registry — Cross-Cloud DR

Configure **single Entra ID tenant** and **cloud-neutral container registry** so users and workloads work after failover without depending on the primary cloud.

**Related:** [Cross-Cloud DR Guide](../../docs/guide/cross-cloud-dr-aro-rosa/README.md) · [ROSA Entra ID Setup](../../cluster-creation-cloud/aws/tf-rosa/docs/ENTRA-ID-SETUP.md)

---

## Identity (Entra ID)

### Single Tenant, Both Clusters

| Item | ARO | ROSA HCP |
|------|-----|----------|
| IdP | Entra ID OAuth | Entra ID OAuth (Terraform or RHCS API) |
| Redirect URI | `https://oauth-openshift.apps.<aro-domain>/oauth2callback/<idp-name>` | `https://oauth-openshift.apps.<rosa-domain>/oauth2callback/<idp-name>` |
| RBAC | Entra groups → ClusterRoleBindings | Same groups |

**Register both redirect URIs** in the Entra app registration before go-live.

### Setup Steps

1. Create one Entra app registration (or reuse existing)
2. Add redirect URIs for **both** cluster OAuth endpoints
3. Configure ARO via GitOps [`aro-platform-config`](../../cluster-creation-cloud/aws/shared-vpc/gitops/charts/aro-platform-config/) or Bicep
4. Configure ROSA via Terraform [`rosa-entra-idp`](../../cluster-creation-cloud/aws/shared-vpc/terraform/modules/rosa-entra-idp/) — set `identityProvider.enabled: false` in GitOps to avoid conflict
5. Map same Entra security groups to `cluster-admin` / `cluster-developer` on both clusters
6. Disable kubeadmin after IdP validation on both clusters

### Break-Glass Credentials

Store in a **neutral vault** (not solely in primary cloud):

| Cluster | Break-Glass Method |
|---------|-------------------|
| ARO | `az aro list-credentials` — store in neutral Key Vault / Secrets Manager |
| ROSA HCP | `rosa create admin` — store HTPasswd or emergency admin per [`break-glass.tf`](../../cluster-creation-cloud/aws/tf-rosa/break-glass.tf) |

---

## Container Registry Strategy

Native cloud registries **do not** geo-replicate across clouds:

| Registry | Cross-Cloud DR |
|----------|----------------|
| ACR geo-replication | Azure-only — insufficient alone |
| Amazon ECR | AWS-only — insufficient alone |
| **Red Hat Quay** | Recommended — repository mirroring, geo-replicated storage |
| **Harbor** | Replication rules to ACR + ECR |
| **Dual-push CI** | Pipeline pushes same image to two registries |

### Option A: Red Hat Quay (Recommended)

1. Deploy Quay (cloud-neutral SaaS or self-hosted with HA)
2. Configure repository mirroring or geo-replication
3. Update ImageStreamTags / deployment image references to Quay URLs
4. Ensure DR cluster pull secrets include Quay credentials

### Option B: Dual-Push CI

See [`examples/dual-push-registry.yml`](./examples/dual-push-registry.yml) for a GitHub Actions workflow that pushes to ACR and ECR on every build.

Pipeline requirements:

- Same image digest in both registries (push from single build)
- GitOps manifests reference registry by **environment overlay** (ACR in ARO values, ECR in ROSA values) OR use neutral Quay URL everywhere
- Failover test: confirm DR cluster pulls without primary cloud registry access

### Image Pull Secrets

Pre-create pull secrets on **both** clusters:

```bash
# Quay example
oc create secret docker-registry quay-pull \
  --docker-server=quay.example.com \
  --docker-username=<user> \
  --docker-password=<token> \
  -n production

oc secrets link default quay-pull --for=pull -n production
```

---

## Workload Identity (ESO Pattern)

Use External Secrets Operator with cloud-specific SecretStores — pre-populate secrets in **both** vaults:

| Cloud | Secret Store |
|-------|--------------|
| ARO | Azure Key Vault — [`secretstore-azure.yaml`](../../operations/database-migration/openshift/secrets/secretstore-azure.yaml) |
| ROSA | AWS Secrets Manager — [`secretstore-aws.yaml`](../../operations/database-migration/openshift/secrets/secretstore-aws.yaml) |

Replicate secret **values** to both vaults; ESO syncs locally per cluster.

---

## Validation Checklist

- [ ] Entra app has redirect URIs for both cluster domains
- [ ] Same Entra groups mapped to RBAC on both clusters
- [ ] kubeadmin disabled on both after IdP test
- [ ] Break-glass creds stored in neutral vault; access tested
- [ ] Registry strategy chosen and implemented (Quay / Harbor / dual-push)
- [ ] DR cluster pulls all production images with primary cloud offline (tested)
- [ ] Secrets replicated to both cloud vaults
