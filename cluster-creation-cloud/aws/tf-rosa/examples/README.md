# tfvars examples

Copy any file to `terraform.tfvars` or pass with `make plan TFVARS=examples/<file>`.

| File | Pattern |
|------|---------|
| `mobb-lab.tfvars.example` | Full reference — all variables |
| `standard.tfvars.example` | Public HCP, single AZ |
| `private.tfvars.example` | Private API + bastion |
| `multi-az.tfvars.example` | Multi-AZ + autoscaling |
| `htpasswd.tfvars.example` | HTPasswd admin + developer users |
| `kms.tfvars.example` | Customer-managed KMS + etcd encryption |
| `shared-roles.tfvars.example` | Reuse shared account IAM roles |
| `external-auth.tfvars.example` | External auth + break-glass |

## Auth (do not commit secrets)

Pick **one** method:

**Service account (recommended for CI/automation):**

```bash
export TF_VAR_client_id=...
export TF_VAR_client_secret=...
```

**OCM token (optional):**

```bash
export TF_VAR_token=...
```

If neither is set, `make plan` / `apply` / `destroy` try Bitwarden item `ocm-api-key` for token.

```bash
make plan TFVARS=examples/standard.tfvars.example
```
