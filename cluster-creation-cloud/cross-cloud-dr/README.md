# Cross-Cloud DR Environment Templates

Terraform variable templates for ARO ↔ ROSA HCP disaster recovery pairs. Use **non-overlapping CIDRs** across clouds.

## Directory Layout

```
cross-cloud-dr/
├── README.md                          # This file
└── environments/
    ├── aro-primary.tfvars.example     # ARO production (Azure)
    ├── aro-dr.tfvars.example          # ARO DR standby (Azure) — Scenario B
    ├── rosa-primary.tfvars.example    # ROSA HCP production (AWS)
    └── rosa-dr.tfvars.example         # ROSA HCP DR standby (AWS) — Scenario A
```

Source Terraform modules:

- ARO: [`../azure/terraform-aro/`](../azure/terraform-aro/)
- ROSA HCP: [`../aws/tf-rosa/`](../aws/tf-rosa/)

## Scenarios

| Scenario | Primary | DR | tfvars to use |
|----------|---------|-----|---------------|
| **A** — Azure-centric | ARO | ROSA HCP | `aro-primary` + `rosa-dr` |
| **B** — AWS-centric | ROSA HCP | ARO | `rosa-primary` + `aro-dr` |

Pin the **same OpenShift minor version** on both clusters.

## CIDR Planning

| Cluster role | Cloud | Suggested VNet/VPC CIDR |
|--------------|-------|-------------------------|
| ARO primary | Azure | `10.0.0.0/20` |
| ARO DR | Azure | `10.10.0.0/20` |
| ROSA primary | AWS | `10.1.0.0/16` |
| ROSA DR | AWS | `10.11.0.0/16` |

No overlap — required for cross-cloud VPN and future connectivity.

## Deploy

### ARO (primary or DR)

```bash
cd cluster-creation-cloud/azure/terraform-aro
cp ../../cross-cloud-dr/environments/aro-primary.tfvars.example terraform.tfvars
# Edit subscription_id, cluster_name, location, domain
make create          # public
# or
make create-private  # private + optional egress lockdown
```

### ROSA HCP (primary or DR)

```bash
cd cluster-creation-cloud/aws/tf-rosa
make init
make plan TFVARS=../../cross-cloud-dr/environments/rosa-dr.tfvars.example
make apply TFVARS=../../cross-cloud-dr/environments/rosa-dr.tfvars.example
```

## Post-Provision

1. Register both clusters in ACM — [ACM GitOps Setup](../../operations/disaster-recovery/acm-gitops-setup.md)
2. Configure OADP cross-cloud backup — [OADP S3 Guide](../../operations/backup-restore/oadp_cross_cloud_s3_guide.md)
3. Run DR validation — [DR Validation Guide](../../operations/disaster-recovery/dr-validation-guide.md)

## Related Documentation

- [Cross-Cloud DR Strategy Guide](../../docs/guide/cross-cloud-dr-aro-rosa/README.md)
- [Failover Runbook](../../operations/disaster-recovery/failover-runbook-aro-rosa.md)
