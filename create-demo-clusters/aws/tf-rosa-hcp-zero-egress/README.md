# ROSA HCP Cluster with Zero Egress

This Terraform configuration deploys a Red Hat OpenShift Service on AWS (ROSA) Hosted Control Plane (HCP) cluster with **zero egress** configuration. Zero egress means that all outbound traffic from the cluster goes through AWS VPC endpoints instead of using NAT gateways or internet gateways, providing enhanced security and network isolation.

## Overview

This configuration creates:

- **VPC** with private and public subnets (NAT gateway disabled for zero egress)
- **VPC Endpoints** for:
  - STS (Security Token Service) - for IAM authentication
  - ECR API and DKR - for container image pulls
  - S3 - for object storage access
- **ROSA HCP Cluster** with zero egress property enabled
- **IAM Roles** for ROSA account and operator roles
- **Security Groups** for VPC endpoint access

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **Red Hat OpenShift Cluster Manager (OCM) Account** with ROSA access
3. **OCM Token** - Get your token from: https://console.redhat.com/openshift/token/rosa/show
4. **Terraform** >= 1.0 installed
5. **AWS CLI** configured with appropriate credentials
6. **ROSA CLI** installed (optional, for cluster management)

## Quick Start

### 1. Clone and Navigate

```bash
cd create-demo-clusters/aws/tf-rosa-hcp-zero-egress
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
token              = "your-ocm-token-here"
region             = "us-east-1"
cluster_name       = "my-rosa-hcp-zero-egress"
openshift_version  = "4.19.4"
multi_az           = true
private_cluster    = true
worker_node_replicas = 3
machine_type       = "m5.xlarge"

vpc_cidr_block = "10.0.0.0/16"
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

additional_tags = {
  Environment = "production"
  Owner      = "your-email@example.com"
  Project    = "zero-egress-demo"
}
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review the Plan

```bash
terraform plan
```

### 5. Apply the Configuration

```bash
terraform apply
```

Type `yes` when prompted to confirm the deployment.

### 6. Access Your Cluster

After the cluster is created, you can access it using:

```bash
# Get cluster console URL
terraform output cluster_console_url

# Login to the cluster (you'll need to set up authentication)
rosa login --token=$(terraform output -raw token)
```

## Important Notes

### Zero Egress Configuration

- **No NAT Gateway**: The VPC is configured without a NAT gateway to enforce zero egress
- **VPC Endpoints Required**: All AWS service access (ECR, S3, STS) goes through VPC endpoints
- **Private Cluster**: The cluster is configured as private by default for enhanced security
- **Additional Endpoints**: You may need to add more VPC endpoints depending on your workload requirements

### Cost Considerations

- **VPC Endpoints**: Interface endpoints (STS, ECR) incur hourly charges and data processing charges
- **S3 Gateway Endpoint**: Free of charge
- **No NAT Gateway Costs**: Savings from not using NAT gateways

### Network Requirements

- **Private Subnets**: Worker nodes are deployed in private subnets
- **DNS**: Ensure DNS hostnames and DNS support are enabled (configured automatically)
- **Security Groups**: VPC endpoints have security groups allowing traffic from private subnets

## Variables Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `token` | OCM token for authentication | - | Yes |
| `region` | AWS region for deployment | `us-east-1` | No |
| `cluster_name` | Name of the ROSA HCP cluster | Auto-generated | No |
| `openshift_version` | OpenShift version | `4.19.4` | No |
| `multi_az` | Enable multi-AZ deployment | `true` | No |
| `private_cluster` | Deploy as private cluster | `true` | No |
| `worker_node_replicas` | Number of worker nodes | `3` | No |
| `machine_type` | AWS instance type (available for reference, machine pools can be configured separately) | `m5.xlarge` | No |
| `vpc_cidr_block` | VPC CIDR block | `10.0.0.0/16` | No |
| `autoscaling_enabled` | Enable autoscaling | `false` | No |
| `min_replicas` | Minimum replicas for autoscaling | `3` | No |
| `max_replicas` | Maximum replicas for autoscaling | `3` | No |
| `client_id` | RHCS client ID (alternative to token) | `null` | No |
| `client_secret` | RHCS client secret (alternative to token) | `null` | No |
| `proxy` | Proxy configuration object | `null` | No |
| `private_subnet_cidrs` | Private subnet CIDRs | `["10.0.1.0/24", ...]` | No |
| `public_subnet_cidrs` | Public subnet CIDRs | `["10.0.101.0/24", ...]` | No |
| `additional_tags` | Additional AWS tags | `{}` | No |

## Outputs

After deployment, Terraform will output:

- `cluster_id`: The ROSA HCP cluster ID
- `cluster_name`: The cluster name
- `cluster_console_url`: OpenShift console URL
- `cluster_api_url`: API endpoint URL
- `vpc_id`: VPC ID
- `private_subnet_ids`: Private subnet IDs
- `public_subnet_ids`: Public subnet IDs
- `vpc_endpoint_ids`: IDs of all VPC endpoints

## Additional VPC Endpoints

Depending on your workload, you may need to add additional VPC endpoints for:

- **CloudWatch Logs**: For logging
- **CloudWatch Metrics**: For metrics
- **SNS**: For notifications
- **SQS**: For queuing
- **EC2**: For EC2 API calls
- **ELB**: For load balancer operations

You can add these by creating additional `aws_vpc_endpoint` resources in `vpc-endpoints.tf`.

## Troubleshooting

### Cluster Creation Fails

1. Verify your OCM token is valid: `rosa whoami`
2. Check AWS permissions for creating IAM roles and VPC resources
3. Ensure the region supports ROSA HCP
4. Verify subnet CIDR blocks don't overlap

### Cannot Pull Container Images

1. Verify ECR endpoints are created and healthy
2. Check security group rules allow traffic from private subnets
3. Ensure IAM role has ECR read permissions (automatically configured)

### Network Connectivity Issues

1. Verify VPC endpoints are in "available" state
2. Check route tables are properly configured
3. Ensure DNS resolution is working in private subnets

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete the ROSA HCP cluster and all associated resources. Make sure you have backups of any important data.

## Additional Resources

- [ROSA HCP Documentation](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-overview.html)
- [Zero Egress Configuration](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-networking.html)
- [VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)
- [Terraform ROSA HCP Provider](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs)

## Support

For issues or questions:
- Check the [ROSA Documentation](https://docs.openshift.com/rosa/)
- Open an issue in the repository
- Contact Red Hat Support

