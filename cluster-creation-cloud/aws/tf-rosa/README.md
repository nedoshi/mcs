# ROSA HCP Terraform (Pattern 1)

Primary **standalone** stack for ROSA HCP. See [`../README.md`](../README.md) for all patterns and addons.

This folder provisions:

- **Networking** – VPC, public/private subnets, NAT (private/public architecture)
- **ROSA HCP cluster** – Red Hat managed control plane, worker machine pool(s)
- **Optional bastion** – For private cluster access (SSH or SSM)
- **Optional HTPasswd IDP** – Admin and developer users

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.4.6
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2, configured
- [ROSA CLI](https://docs.openshift.com/rosa/cli_reference/rosa_cli_get_started_cli.html) (optional, for account roles)
- **RHCS API credentials** (exactly one method):
  - **Recommended (CI/automation):** `client_id` + `client_secret` via `TF_VAR_client_id` / `TF_VAR_client_secret`
  - **Optional:** OCM `token` via `TF_VAR_token` ([console token](https://console.redhat.com/openshift/token/show))

## Quick start

```bash
cp examples/standard.tfvars.example terraform.tfvars
# Or pick a pattern from examples/README.md

# Set secrets via env (do not commit):
#   source ~/Documents/Scripts/cluster-creation-cloud/env.sh aws-tf-rosa

make init
make test
make plan TFVARS=terraform.tfvars
make apply TFVARS=terraform.tfvars
```

**External authentication:**

```bash
make plan TFVARS=examples/external-auth.tfvars.example
```

**All patterns:** see [examples/README.md](examples/README.md).

**Using a different tfvars file:**

```bash
make plan TFVARS=terraform.tfvars
make apply TFVARS=terraform.tfvars
```

## Production: use shared account roles

HCP uses **account-level** IAM roles that can be shared across clusters in the same AWS account. For production, create them once and reuse:

1. **Create roles once** (choose one):
   - **ROSA CLI:** `rosa create account-roles --hosted-cp --mode auto`
   - **Terraform:** Use [rosa-tf environments/account-hcp](https://github.com/supernovae/rosa-tf/tree/main/environments/account-hcp) or Red Hat’s account-roles module

2. **Use existing roles in this repo:** Set in your tfvars:
   ```hcl
   create_account_roles = false
   account_role_prefix   = "ManagedOpenShift"   # prefix used when roles were created
   installer_role_arn   = "arn:aws:iam::ACCOUNT_ID:role/ManagedOpenShift-HCP-ROSA-Installer-Role"
   support_role_arn     = "arn:aws:iam::ACCOUNT_ID:role/ManagedOpenShift-HCP-ROSA-Support-Role"
   worker_role_arn      = "arn:aws:iam::ACCOUNT_ID:role/ManagedOpenShift-HCP-ROSA-Worker-Role"
   ```

If `create_account_roles = true` (default), this Terraform creates account roles per run using `account_role_prefix` (defaults to `cluster_name`).

## Optional: customer-managed KMS

By default the cluster uses **provider-managed** encryption (AWS managed key). For compliance or custom key policies you can use a customer-managed KMS key:

- **`cluster_kms_mode = "create"`** – Terraform creates a KMS key with the required ROSA HCP policy (account/operator roles, EC2, Auto Scaling, CAPA). Use for audit and control.
- **`cluster_kms_mode = "existing"`** – Use your own key; set **`cluster_kms_key_arn`** to the key ARN. The key policy must allow the ROSA account and operator roles and HCP service principals (see [Red Hat: Creating ROSA with HCP using a custom KMS key](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_rosa_with_hcp_clusters/rosa-hcp-creating-cluster-with-aws-kms-key)).

**etcd encryption:** When using customer-managed KMS (`create` or `existing`), you can set **`etcd_encryption = true`** to encrypt etcd at rest with the same key (policy in kms.tf includes the required operator roles).

Example (create key and enable etcd encryption):

```hcl
cluster_kms_mode = "create"
etcd_encryption  = true
```

## Makefile targets

| Target   | Description                    |
|----------|--------------------------------|
| `help`   | Show usage and targets        |
| `init`   | `terraform init`              |
| `plan`   | `terraform plan -var-file=$(TFVARS)` |
| `apply`  | `terraform apply -var-file=$(TFVARS)` |
| `destroy`| `terraform destroy -var-file=$(TFVARS)` |
| `output` | `terraform output`            |
| `validate` | `terraform validate`        |
| `fmt`      | `terraform fmt -check -recursive` |
| `test`     | `fmt` + `validate`          |

Default **TFVARS** is `terraform.tfvars`. Override with `make plan TFVARS=my.tfvars`.

**Auth:** Set `TF_VAR_client_id` + `TF_VAR_client_secret` (recommended) **or** `TF_VAR_token` (optional). If neither is set, `make plan`/`apply`/`destroy` fall back to Bitwarden `ocm-api-key` for token. Do not commit secrets.

## Variables

See [variables.tf](variables.tf) for all options. Key ones:

- **cluster_name** – Name of the cluster (and prefix for resources).
- **create_account_roles** – If `true`, create HCP account roles here; if `false`, set **installer_role_arn**, **support_role_arn**, **worker_role_arn**.
- **cluster_kms_mode** – `provider_managed` \| `create` \| `existing`.
- **private** – Private cluster (no public API).
- **multi_az** – Multi-AZ deployment.

## References

- [ROSA HCP architecture](https://docs.openshift.com/rosa/architecture/rosa-architecture-models.html#rosa-hcp-architecture_rosa-architecture-models)
- [ROSA HCP with custom KMS key](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_rosa_with_hcp_clusters/rosa-hcp-creating-cluster-with-aws-kms-key)
- [rosa-tf](https://github.com/supernovae/rosa-tf) – Multi-env ROSA Terraform (KMS, account-hcp)
- [rh-mobb/terraform-rosa](https://github.com/rh-mobb/terraform-rosa) – Upstream-style layout reference
