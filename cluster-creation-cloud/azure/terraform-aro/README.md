# MCS terraform-aro

MCS wrapper around [rh-mobb/terraform-aro](https://github.com/rh-mobb/terraform-aro) with MOBB lab defaults, cost-notifier tagging, and post-deploy OAuth addon.

**Pinned upstream:** `v2.0.0-preview` (see [UPSTREAM_PIN](UPSTREAM_PIN))

## Layout

```
terraform-aro/
├── upstream/                 # rh-mobb/terraform-aro @ pinned tag (git submodule)
├── overlays/
│   └── cost_notifier.tf      # cost-center 468 + expires-at/delete-after tags
├── examples/
│   └── mobb-lab.tfvars.example
├── cluster-oauth-config.yaml # MCS post-deploy Entra ID OAuth addon
├── terraform.tfvars.example
├── Makefile                  # merges upstream + overlays, delegates targets
├── UPSTREAM_PIN
└── .terraform-root/          # generated merge dir (gitignored)
```

Legacy flat SP-only fork: [`../terraform-aro.legacy/`](../terraform-aro.legacy/)

## Quick start

```bash
cd cluster-creation-cloud/azure/terraform-aro

# First-time: populate upstream submodule
git submodule update --init --recursive upstream
# or: make submodule-update

cp examples/mobb-lab.tfvars.example terraform.tfvars
export TF_VAR_subscription_id="<azure-subscription-id>"

make init
make plan
make apply
```

Cross-cloud DR tfvars: [`../../cross-cloud-dr/environments/`](../../cross-cloud-dr/environments/)

```bash
make plan TFVARS=../../cross-cloud-dr/environments/aro-primary.tfvars.example
make apply TFVARS=../../cross-cloud-dr/environments/aro-primary.tfvars.example
```

## MCS customizations

| Item | Location |
|------|----------|
| cost-center `468` | `overlays/cost_notifier.tf` (always applied) |
| `expires-at` (+2d), `delete-after` (+3d) | `overlays/cost_notifier.tf` via `time_static` |
| Entra ID OAuth addon | `cluster-oauth-config.yaml` (apply after cluster is ready) |

```bash
oc apply -f cluster-oauth-config.yaml
```

## Managed identities (preview)

Pinned `v2.0.0-preview` uses **ARM template** deployment for managed identities (`enable_managed_identities = true`).

```bash
# In terraform.tfvars:
enable_managed_identities = true

make create-managed-identity
# or private:
make create-private-managed-identity
```

Destroy managed-identity clusters with:

```bash
make destroy-managed-identity
```

### reference-sync (newer upstream / AzAPI path)

`main` branch adds AzAPI modules under `reference/` (not vendored in git). Before `make init` on that upstream revision:

```bash
REFERENCE_ARO_AZAPI_URL=https://github.com/your-org/terraform-aro-reference-aro-azapi.git make reference-sync
```

On `v2.0.0-preview`, `make reference-sync` prints a no-op notice. See upstream [CONTRIBUTING.md](https://github.com/rh-mobb/terraform-aro/blob/main/CONTRIBUTING.md) when bumping `UPSTREAM_PIN`.

## Validation (no Azure credentials)

```bash
make pr          # validate + fmt + optional tflint/checkov in merged root
make validate
```

`make test` / `terraform plan` require `az login`.

## State migration from legacy fork

The previous MCS layout was a **flat fork** (now in `terraform-aro.legacy/`). The new wrapper uses a **different root module** (upstream rh-mobb). Existing `terraform.tfstate` is **not compatible** without manual `state mv` across renamed/restructured resources.

| Situation | Recommendation |
|-----------|----------------|
| Lab / disposable cluster | `terraform destroy` with legacy code, then greenfield `make apply` |
| Production cluster | Stay on `terraform-aro.legacy/` until planned migration, or use Azure Portal/CLI import workflow |
| DR templates | Update tfvars paths only; variable names match upstream |

To destroy a cluster created with the legacy fork:

```bash
cd ../terraform-aro.legacy
terraform destroy -var "subscription_id=$TF_VAR_subscription_id"
```

## Submodule maintenance

Convert from old `nedoshi/terraform-aro` submodule (one-time, repo maintainer):

```bash
# From MCS repo root — deinit old submodule, commit MCS wrapper + new upstream submodule
git submodule deinit -f cluster-creation-cloud/azure/terraform-aro
git rm cluster-creation-cloud/azure/terraform-aro
# restore MCS wrapper files, then:
git submodule add -b v2.0.0-preview https://github.com/rh-mobb/terraform-aro.git \
  cluster-creation-cloud/azure/terraform-aro/upstream
```

Bump upstream:

1. Update `UPSTREAM_PIN`
2. `make submodule-update`
3. `make pr`
4. Test apply in lab

## Related docs

- [ARO operation guide](../../../docs/guide/aro-operation-guide.md)
- [Cross-cloud DR](../cross-cloud-dr/README.md)
- [Failover runbook](../../../operations/disaster-recovery/failover-runbook-aro-rosa.md)
- Upstream: https://github.com/rh-mobb/terraform-aro
