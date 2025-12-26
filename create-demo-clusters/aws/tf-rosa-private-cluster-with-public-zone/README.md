# ROSA Private Cluster with Public Zone

This Terraform configuration deploys a Red Hat OpenShift Service on AWS (ROSA) Classic cluster configured as a private cluster, with Route53 DNS records added to a public hosted zone to allow external DNS resolution of the API endpoint.

## Overview

This configuration creates:

- **ROSA Classic Cluster** configured as private (no public API endpoint)
- **VPC** with private and public subnets (optional, can use existing VPC)
- **Route53 Record** in the public hosted zone pointing to the internal API load balancer
- **IAM Roles** for ROSA account and operator roles

## Key Features

- **Private Cluster**: API endpoint is only accessible from within the VPC
- **Public DNS Resolution**: Adds DNS record to public zone for external DNS resolution (does not make the API public)
- **Flexible VPC**: Can create a new VPC or use existing subnets
- **Multi-AZ Support**: Configurable for high availability

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **Red Hat OpenShift Cluster Manager (OCM) Account** with ROSA access
3. **OCM Token or Client Credentials** - Get your token from: https://console.redhat.com/openshift/token/rosa/show
4. **Terraform** >= 1.0 installed
5. **AWS CLI** configured with appropriate credentials
6. **Route53 Public Hosted Zone** - The cluster's base DNS domain must have a public hosted zone in Route53

## Quick Start

### 1. Configure Variables

Create a `terraform.tfvars` file:

```hcl
token              = "your-ocm-token-here"  # or set RHCS_TOKEN env var
aws_region         = "us-east-2"
cluster_name      = "my-rosa-private-cluster"
openshift_version  = "4.14.20"
private_cluster    = true
multi_az           = true
create_vpc         = true

# VPC Configuration (if create_vpc = true)
vpc_name           = "rosa-private-vpc"
vpc_cidr_block     = "10.0.0.0/16"
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

# Or use existing subnets (if create_vpc = false)
# aws_subnet_ids = ["subnet-xxx", "subnet-yyy", "subnet-zzz"]
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review the Plan

```bash
terraform plan
```

### 4. Apply the Configuration

```bash
terraform apply
```

## Important Notes

### Private Cluster Configuration

- **Private API**: The API endpoint is only accessible from within the VPC
- **Public DNS**: The Route53 record in the public zone allows DNS resolution but does not make the API publicly accessible
- **Network Access**: You'll need VPN, Direct Connect, or a bastion host to access the cluster

### Route53 Requirements

- The cluster's `base_dns_domain` must have a **public hosted zone** in Route53
- The Terraform configuration will automatically find and use this zone
- A DNS record for `api.<cluster-domain>` will be created pointing to the internal load balancer

### VPC Configuration

- **Create New VPC**: Set `create_vpc = true` to create a new VPC with subnets
- **Use Existing VPC**: Set `create_vpc = false` and provide `aws_subnet_ids`
- **Multi-AZ**: When `multi_az = true`, ensure you have 3 availability zones available

## Variables Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `token` | OCM token (or set RHCS_TOKEN env var) | `null` | No* |
| `client_id` | RHCS client ID (alternative to token) | `null` | No* |
| `client_secret` | RHCS client secret (alternative to token) | `null` | No* |
| `aws_region` | AWS region | `us-east-2` | No |
| `cluster_name` | ROSA cluster name | Auto-generated | No |
| `openshift_version` | OpenShift version | `4.14.20` | No |
| `private_cluster` | Deploy as private cluster | - | Yes |
| `multi_az` | Enable multi-AZ | `true` | No |
| `create_vpc` | Create new VPC | - | Yes |
| `worker_node_replicas` | Number of worker nodes | Auto (3/2) | No |
| `machine_type` | AWS instance type | `m5.xlarge` | No |
| `vpc_name` | VPC name (if creating) | `mobb-tf-vpc` | No |
| `vpc_cidr_block` | VPC CIDR | `10.0.0.0/16` | No |
| `private_subnet_cidrs` | Private subnet CIDRs | `["10.0.1.0/24", ...]` | No |
| `public_subnet_cidrs` | Public subnet CIDRs | `["10.0.101.0/24", ...]` | No |
| `aws_subnet_ids` | Existing subnet IDs (if not creating VPC) | - | No |

*Either token or client_id/secret must be provided

## Outputs

After deployment, Terraform will output:

- `cluster_id`: The ROSA cluster ID
- `cluster_name`: The cluster name
- `cluster_api_url`: API endpoint URL
- `cluster_console_url`: OpenShift console URL
- `cluster_domain`: Cluster domain
- `cluster_base_dns_domain`: Base DNS domain
- `vpc_id`: VPC ID (if created)
- `private_subnet_ids`: Private subnet IDs (if created)
- `public_subnet_ids`: Public subnet IDs (if created)
- `public_zone_id`: Route53 public zone ID
- `api_record_name`: Route53 API record name

## Troubleshooting

### Route53 Zone Not Found

- Ensure the cluster's base DNS domain has a public hosted zone in Route53
- Verify the zone exists before cluster creation
- Check AWS permissions for Route53 access

### Network Verifier Warnings

- The configuration includes a 60-second delay after VPC creation to prevent network verifier warnings
- If you still see warnings, they are typically false positives and can be ignored

### Cluster Creation Fails

1. Verify your OCM token is valid: `rosa whoami`
2. Check AWS permissions for creating IAM roles and VPC resources
3. Ensure the region supports ROSA Classic
4. Verify subnet CIDR blocks don't overlap

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete the ROSA cluster and all associated resources. Make sure you have backups of any important data.

## Additional Resources

- [ROSA Classic Documentation](https://docs.openshift.com/rosa/rosa_architecture/rosa-architecture-overview.html)
- [Private Cluster Configuration](https://docs.openshift.com/rosa/rosa_planning/rosa-private-clusters.html)
- [Route53 Integration](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/)

## Support

For issues or questions:
- Check the [ROSA Documentation](https://docs.openshift.com/rosa/)
- Open an issue in the repository
- Contact Red Hat Support

