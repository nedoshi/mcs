# ARO HCP Validation — Path B (terraform-aro-hcp)

Path B validates that [rh-mobb/terraform-aro-hcp](https://github.com/rh-mobb/terraform-aro-hcp) produces equivalent clusters to Path A ([02-provision-azure-cli.md](02-provision-azure-cli.md)).

> **Status:** Repository access required. MCS includes a submodule placeholder and MOBB lab tfvars template. Complete this path when access is granted.

## Submodule location

```
cluster-creation-cloud/azure/terraform-aro-hcp/
├── README.md
└── examples/
    └── mobb-lab.tfvars.example
```

When the upstream repo is available:

```bash
cd /path/to/mcs
git submodule add https://github.com/rh-mobb/terraform-aro-hcp.git \
  cluster-creation-cloud/azure/terraform-aro-hcp
git submodule update --init --recursive
```

Update [.gitmodules](../../../.gitmodules) accordingly.

## MOBB lab variables

Copy the example tfvars:

```bash
cd cluster-creation-cloud/azure/terraform-aro-hcp
cp examples/mobb-lab.tfvars.example terraform.tfvars
# Set secrets via TF_VAR_* — do not commit terraform.tfvars
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

## Comparison checklist (Path A vs Path B)

After both paths succeed, fill this table in [validation-report.md](validation-report.md):

| Output | Path A value | Path B value | Match? |
|--------|--------------|--------------|--------|
| API server URL | | | |
| Console URL | | | |
| Provisioning state | | | |
| External auth resource ID | | | |
| Worker node count | | | |
| Destroy clean (no orphaned RG) | | | |

## Gaps to document during Path B

- Private cluster / private ingress
- Outbound type (LoadBalancer vs user-defined routing)
- Managed identity vs service principal
- Multi-AZ worker pools
- In-place cluster upgrades
- External auth at create-time vs post-create Bicep

## Destroy lifecycle

```bash
terraform destroy -var-file=terraform.tfvars
```

Confirm managed resource group cleanup and no orphaned `hcpOpenShiftClusters` resources.

## If repository remains unavailable

Path A is authoritative for Phase 1 exit. Record blockers in [validation-report.md](validation-report.md) and proceed with workshop recommendations based on Path A only.

## References

- [Azure/ARO-HCP upstream](https://github.com/Azure/ARO-HCP/)
- [Classic terraform-aro](../../../cluster-creation-cloud/azure/terraform-aro/)
- [ROSA HCP MOBB lab pattern](../../../cluster-creation-cloud/aws/tf-rosa/examples/mobb-lab.tfvars.example)
