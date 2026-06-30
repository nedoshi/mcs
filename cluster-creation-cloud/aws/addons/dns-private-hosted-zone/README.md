# DNS private hosted zone (post-cluster addon)

Associates a **Route53 private hosted zone** with an existing ROSA cluster VPC and creates a wildcard `A` alias to the cluster ingress NLB.

**Independent:** does not create a cluster. Apply after `tf-rosa` (or any HCP install) and pass outputs:

```bash
cd cluster-creation/aws/addons/dns-private-hosted-zone
cp terraform.tfvars.example terraform.tfvars
# cluster_name, vpc_id from: terraform -chdir=../../tf-rosa output

terraform init
terraform plan
terraform apply
```

**Inputs:** `cluster_name`, `vpc_id`, `custom_domain`, `region`.

**Does not overlap with:** `tf-rosa`, `cluster-zero-egress`, or operator addons.
