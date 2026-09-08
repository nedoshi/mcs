# terraform-aro.legacy — archived flat fork

This directory preserves the **pre-incorporation** MCS terraform-aro implementation (flat layout, service-principal only, external `terraform-aro-permissions` git module).

**Do not use for new clusters.** Use [`../terraform-aro/`](../terraform-aro/) (rh-mobb upstream wrapper).

## Contents

Snapshot of the former `cluster-creation-cloud/azure/terraform-aro/` tree before rh-mobb `v2.0.0-preview` incorporation (2025).

## Destroy-only usage

If you still have state for a cluster created with this fork:

```bash
cd cluster-creation-cloud/azure/terraform-aro.legacy
export TF_VAR_subscription_id="..."
terraform init
terraform destroy
```

Copy `terraform.tfstate` from the old working directory if needed.

## Migration

See [terraform-aro README — State migration](../terraform-aro/README.md#state-migration-from-legacy-fork).
