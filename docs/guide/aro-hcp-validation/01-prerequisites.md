# ARO HCP Validation — Prerequisites

## Azure entitlements

| Requirement | How to verify |
|-------------|---------------|
| Subscription with ARO HCP preview | Azure portal or Red Hat/Microsoft PM confirmation |
| Contributor (or equivalent) on target RG | `az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv)` |
| Sufficient regional quota for worker nodes | Azure portal → Subscriptions → Usage + quotas |
| Non-overlapping VNet CIDR | Plan before deploy; see [cross-cloud DR tfvars](../../../cluster-creation-cloud/cross-cloud-dr/environments/aro-primary.tfvars.example) for CIDR patterns |

Document your subscription ID, region, and API version in [validation-report.md](validation-report.md).

## Required tools

| Tool | Version check | Purpose |
|------|---------------|---------|
| `az` | `az version` | ARM REST, Bicep deploy, account context |
| `oc` | `oc version` | Cluster operations |
| `jq` | `jq --version` | JSON parsing |
| `curl` | `curl --version` | Admin credential async polling |
| `watch` | `watch -v` or procps | Async operation polling in credential script |
| `uuidgen` | macOS/Linux default | Correlation headers (optional for localhost RP) |

Optional for Path B:

| Tool | Purpose |
|------|---------|
| `terraform` >= 1.5 | rh-mobb/terraform-aro-hcp lifecycle |

## MOBB lab guardrails

Apply these tags on the cluster resource group during provisioning (mirror [mobb-lab.tfvars.example](../../../cluster-creation-cloud/aws/tf-rosa/examples/mobb-lab.tfvars.example)):

```hcl
tags = {
  app-code      = "MOBB-001"
  service-phase = "lab"
  cost-center   = "468"
  owner         = "<your-id>"
}
```

Add TTL tags per your org policy (`expires-at`, `delete-after`) to avoid orphaned preview clusters.

## External authentication provider (RHBK)

ARO HCP **requires** external authentication — there is no built-in OAuth server and no permanent kubeadmin.

Before cluster validation:

1. Deploy or obtain access to **Red Hat Build of Keycloak** reachable from the ARO HCP cluster network.
2. Create realm `openshift` per [RHAC Keycloak guide](https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/05-keycloak.html).
3. Pre-create OAuth clients:
   - `openshift-console` (confidential) — redirect `https://<console_host>/auth/callback`
   - `openshift-cli` (public)
4. Configure groups claim and test users (e.g. group `openshift_admins`).

Console host is unknown until the cluster exists — update RHBK redirect URIs after first `oc get route console`.

## Environment setup

```bash
cd docs/guide/aro-hcp-validation/scripts
cp env.example env.sh
# Edit values — do not commit env.sh
source env.sh
```

Required variables:

```bash
export ARO_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export ARO_RESOURCE_GROUP="<resource-group>"
export ARO_CLUSTER_NAME="<cluster-name>"
export RHBK_HOST="https://<keycloak-host>"
export EXTERNAL_AUTH_NAME="aro-hcp-auth"
export FRONTEND_API_VERSION="2024-06-10-preview"
```

## Access requests (if not already granted)

| Item | Owner |
|------|-------|
| ARO HCP preview on subscription | Microsoft / Red Hat field team |
| [rh-mobb/terraform-aro-hcp](https://github.com/rh-mobb/terraform-aro-hcp) repo access | rh-mobb maintainers |
| Shared MOBB RHBK instance (optional) | Platform team |

## Next step

Proceed to [02-provision-azure-cli.md](02-provision-azure-cli.md).
