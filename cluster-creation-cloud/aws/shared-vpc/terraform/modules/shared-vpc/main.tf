# Shared VPC Module - ROSA HCP
# Creates VPC, subnets, hosted zones, RAM share, and IAM roles for shared VPC HCP deployment
# Resources created in shared VPC account

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-shared-vpc"
  })
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-igw"
  })
}

# -----------------------------------------------------------------------------
# Private Subnets (one per AZ)
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  for_each = toset(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, index(var.availability_zones, each.key))
  availability_zone = each.key

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# -----------------------------------------------------------------------------
# Public Subnet (first AZ)
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, 15)
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch  = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-public"
  })
}

# -----------------------------------------------------------------------------
# Elastic IP for NAT Gateway
# -----------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-nat-eip"
  })

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# NAT Gateway
# -----------------------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Private Route Table
# -----------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# Public Route Table
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Route53 Private Hosted Zones
# -----------------------------------------------------------------------------
resource "aws_route53_zone" "hcp_internal" {
  name = "${var.cluster_name}.hypershift.local"
  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-hcp-internal"
  })
}

resource "aws_route53_zone" "ingress" {
  name = "rosa.${var.cluster_name}.${var.base_dns_domain}"
  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ingress"
  })
}
/*
# -----------------------------------------------------------------------------
# RAM Share - Share VPC with cluster account
# -----------------------------------------------------------------------------
resource "aws_ram_resource_share" "vpc" {
  name                      = "${var.cluster_name}-vpc-share"
  allow_external_principals = false

  tags = var.tags
}

resource "aws_ram_principal_association" "cluster_account" {
  principal          = var.cluster_account_id
  resource_share_arn  = aws_ram_resource_share.vpc.arn
}

resource "aws_ram_resource_association" "vpc" {
  resource_arn       = aws_vpc.main.arn
  resource_share_arn = aws_ram_resource_share.vpc.arn
}
*/
# -----------------------------------------------------------------------------
# Route53 IAM Role - For cluster to manage Route53
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "route53" {
  name = "${var.cluster_name}-route53-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            var.installer_role_arn,
            "arn:aws:iam::${var.cluster_account_id}:root"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "route53" {
  role       = aws_iam_role.route53.name
  policy_arn = "arn:aws:iam::aws:policy/ROSASharedVPCRoute53Policy"
}

# -----------------------------------------------------------------------------
# VPC Endpoint IAM Role - For HCP VPC endpoints
# -----------------------------------------------------------------------------
resource "aws_iam_role" "vpc_endpoint" {
  name = "${var.cluster_name}-vpc-endpoint-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            var.installer_role_arn,
            "arn:aws:iam::${var.cluster_account_id}:root"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "vpc_endpoint" {
  role       = aws_iam_role.vpc_endpoint.name
  policy_arn = "arn:aws:iam::aws:policy/ROSASharedVPCEndpointPolicy"
}
