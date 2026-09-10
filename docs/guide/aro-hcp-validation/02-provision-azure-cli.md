# ARO HCP Validation — Path A: Provision via Azure

Path A validates ARO HCP using Microsoft upstream tooling **before** [rh-mobb/terraform-aro-hcp](https://github.com/rh-mobb/terraform-aro-hcp) is available.

> Classic ARO commands (`az aro create`, `az aro list-credentials`) do **not** apply to HCP clusters.

## API model

| Classic ARO | ARO HCP |
|-------------|---------|
| `Microsoft.RedHatOpenShift/openShiftClusters` | `Microsoft.RedHatOpenShift/hcpOpenShiftClusters` |
| `az aro` extension | `az rest` + portal (CLI extension may lag preview) |
| kubeadmin password | `requestAdminCredential` (24h kubeconfig) |

Preview API version used in this runbook: **`2024-06-10-preview`**

## Step 1 — Deploy cluster

Follow the current [Microsoft ARO documentation](https://learn.microsoft.com/en-us/azure/openshift/) for Hosted Control Planes deployment.

Record during deploy:

- Azure region
- Resource group name
- Cluster name
- Worker node count and VM SKU
- Network profile (public/private API and ingress)

If portal deployment is unavailable, watch [Azure/ARO-HCP](https://github.com/Azure/ARO-HCP/) for RP/CLI updates.

Apply MOBB tags from [01-prerequisites.md](01-prerequisites.md).

## Step 2 — Verify provisioning state

```bash
source docs/guide/aro-hcp-validation/scripts/env.sh

az rest --method GET \
  --uri "/subscriptions/${ARO_SUBSCRIPTION_ID}/resourceGroups/${ARO_RESOURCE_GROUP}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${ARO_CLUSTER_NAME}?api-version=${FRONTEND_API_VERSION}" \
  | jq '{name: .name, provisioningState: .properties.provisioningState, clusterState: .properties.clusterState}'
```

**Expected:** `provisioningState` or equivalent status = `Succeeded`.

Mark **PA-02** in [README.md](README.md) matrix.

## Step 3 — Retrieve API server URL

```bash
export OPENSHIFT_API_URL=$(az rest --method GET \
  --uri "/subscriptions/${ARO_SUBSCRIPTION_ID}/resourceGroups/${ARO_RESOURCE_GROUP}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${ARO_CLUSTER_NAME}?api-version=${FRONTEND_API_VERSION}" \
  | jq -r '.properties.apiServer.url')

echo "${OPENSHIFT_API_URL}"
```

Mark **PA-03** when URL is non-empty.

## Step 4 — Bootstrap admin access

ARO HCP has no kubeadmin. Continue to [04-admin-credential.md](04-admin-credential.md) before any `oc` commands.

## Step 5 — Configure external authentication

Mandatory for user access. Continue to [03-external-auth-rhbk.md](03-external-auth-rhbk.md).

## Step 6 — Run automated checks

```bash
cd docs/guide/aro-hcp-validation/scripts
export KUBECONFIG="$(pwd)/aro-cluster.kubeconfig"
./validate-cluster.sh
```

## Path A exit criteria

| Criterion | Matrix ID |
|-----------|-----------|
| Cluster `Succeeded` | PA-02 |
| Admin kubeconfig works | PA-04, PA-05 |
| External auth + RHBK user access | PA-06 – PA-10 |
| Credential re-issue works | PA-11 |

Update [validation-report.md](validation-report.md) with timestamps and any blockers.

## Next step

[04-admin-credential.md](04-admin-credential.md) → [03-external-auth-rhbk.md](03-external-auth-rhbk.md)
