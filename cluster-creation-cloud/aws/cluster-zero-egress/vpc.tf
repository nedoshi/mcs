data "aws_availability_zones" "available" {}

locals {
  # Extract availability zone names for the specified region, limit it to 3 if multi az or 1 if single
  standard_azs = [
    for zone in data.aws_availability_zones.available.names :
    zone if can(regex("^${data.aws_region.current.id}[a-z]$", zone))
  ]

  max_az_count = var.multi_az ? 3 : 1

  region_azs = slice(
    local.standard_azs,
    0,
    min(length(local.standard_azs), local.max_az_count)
  )
}

resource "random_string" "random_name" {
  length  = 6
  special = false
  upper   = false
}

locals {
  path                 = coalesce(var.path, "/")
  # Use provided worker_node_replicas or default based on multi_az
  worker_node_replicas = var.worker_node_replicas != null ? var.worker_node_replicas : (var.multi_az ? 3 : 2)
  # If cluster_name is not null, use that, otherwise generate a random cluster name
  cluster_name = coalesce(var.cluster_name, "rosa-hcp-zero-egress-${random_string.random_name.result}")
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = ">= 5.8.1"

  name = coalesce(var.vpc_name, "${local.cluster_name}-vpc")
  cidr = var.vpc_cidr_block

  azs             = local.region_azs
  private_subnets = var.multi_az ? var.private_subnet_cidrs : [var.private_subnet_cidrs[0]]
  public_subnets  = var.multi_az ? var.public_subnet_cidrs : [var.public_subnet_cidrs[0]]

  # For zero egress, we don't need NAT gateway as all traffic goes through VPC endpoints
  # NAT gateway is disabled regardless of private_cluster setting for zero egress
  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true
  manage_default_security_group = true

  tags = merge(
    var.additional_tags,
    {
      Name = "${local.cluster_name}-vpc"
    }
  )
}

