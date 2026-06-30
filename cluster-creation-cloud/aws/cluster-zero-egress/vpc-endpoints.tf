# Security group for VPC endpoints to allow inbound traffic from private subnets
resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.cluster_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints in zero egress ROSA HCP cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow all inbound traffic from private subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.multi_az ? var.private_subnet_cidrs : [var.private_subnet_cidrs[0]]
  }

  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(
    var.additional_tags,
    {
      Name = "${local.cluster_name}-vpc-endpoints-sg"
    }
  )
}

# VPC Endpoint for STS (Security Token Service) - Required for IAM authentication
resource "aws_vpc_endpoint" "sts" {
  service_name      = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_id            = module.vpc.vpc_id
  vpc_endpoint_type = "Interface"

  private_dns_enabled = true
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = merge(
    var.additional_tags,
    {
      Name        = "${local.cluster_name}-sts-endpoint"
      Service     = "ROSA"
      ClusterName = local.cluster_name
    }
  )
}

# VPC Endpoint for ECR API - Required for container image pulls
resource "aws_vpc_endpoint" "ecr_api" {
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_id            = module.vpc.vpc_id
  vpc_endpoint_type = "Interface"

  private_dns_enabled = true
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = merge(
    var.additional_tags,
    {
      Name        = "${local.cluster_name}-ecr-api-endpoint"
      Service     = "ROSA"
      ClusterName = local.cluster_name
    }
  )
}

# VPC Endpoint for ECR DKR - Required for container image pulls
resource "aws_vpc_endpoint" "ecr_dkr" {
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_id            = module.vpc.vpc_id
  vpc_endpoint_type = "Interface"

  private_dns_enabled = true
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = merge(
    var.additional_tags,
    {
      Name        = "${local.cluster_name}-ecr-dkr-endpoint"
      Service     = "ROSA"
      ClusterName = local.cluster_name
    }
  )
}

# VPC Endpoint for S3 - Gateway endpoint (no cost, better performance)
resource "aws_vpc_endpoint" "s3" {
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_id            = module.vpc.vpc_id
  vpc_endpoint_type = "Gateway"

  # Associate with route tables instead of subnets
  route_table_ids = module.vpc.private_route_table_ids

  tags = merge(
    var.additional_tags,
    {
      Name        = "${local.cluster_name}-s3-endpoint"
      Service     = "ROSA"
      ClusterName = local.cluster_name
    }
  )
}

