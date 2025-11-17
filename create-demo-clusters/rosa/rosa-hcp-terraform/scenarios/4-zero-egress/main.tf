
# ROSA HCP Zero Egress Cluster with VPC Endpoints

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "rhcs" {
  token = var.rhcs_token
  url   = var.rhcs_url
}

locals {
  cluster_name = var.cluster_name
  tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Scenario    = "zero-egress"
    }
  )
}

# VPC Module with Zero Egress Configuration
module "vpc" {
  source = "../../modules/vpc"

  cluster_name       = local.cluster_name
  aws_region         = var.aws_region
  create_vpc         = var.create_vpc
  existing_vpc_id    = var.existing_vpc_id
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  
  # Zero egress configuration
  create_public_subnets = true  # For bastion
  single_nat_gateway    = false
  zero_egress           = true  # No NAT gateway routes to internet
  create_vpc_endpoints  = true  # Create VPC endpoints
  
  vpc_interface_endpoints = var.vpc_interface_endpoints
  
  tags = local.tags
}

# OIDC Config
resource "rhcs_rosa_oidc_config" "oidc_config" {
  managed = true
}

# Account Roles
resource "rhcs_rosa_account_roles" "account_roles" {
  count = var.create_account_roles ? 1 : 0

  account_role_prefix = "${local.cluster_name}-account"
  openshift_version   = var.openshift_version
}

# Operator Roles
resource "rhcs_rosa_operator_roles" "operator_roles" {
  cluster_id           = rhcs_cluster_rosa_hcp.cluster.id
  operator_role_prefix = "${local.cluster_name}-operator"
  account_role_prefix  = var.create_account_roles ? rhcs_rosa_account_roles.account_roles[0].account_role_prefix : var.existing_account_role_prefix
  oidc_config_id       = rhcs_rosa_oidc_config.oidc_config.id
}

# Private ECR Repository for Container Images
resource "aws_ecr_repository" "cluster_images" {
  count = var.create_ecr_repository ? 1 : 0
  
  name                 = "${local.cluster_name}-images"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr[0].arn
  }

  tags = local.tags
}

# KMS Key for ECR
resource "aws_kms_key" "ecr" {
  count = var.create_ecr_repository ? 1 : 0
  
  description             = "KMS key for ECR encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.tags
}

# ECR VPC Endpoint Policy
data "aws_iam_policy_document" "ecr_endpoint_policy" {
  count = var.create_ecr_repository ? 1 : 0
  
  statement {
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }
}

# HTTP Proxy (Optional)
resource "aws_instance" "http_proxy" {
  count = var.enable_http_proxy ? 1 : 0
  
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.proxy_instance_type
  subnet_id     = module.vpc.private_subnet_ids[0]
  
  vpc_security_group_ids = [aws_security_group.http_proxy[0].id]
  
  user_data = templatefile("${path.module}/proxy-user-data.sh", {
    no_proxy = var.no_proxy
  })

  root_block_device {
    volume_size = 20
    encrypted   = true
  }

  tags = merge(local.tags, { Name = "${local.cluster_name}-proxy" })
}

resource "aws_security_group" "http_proxy" {
  count = var.enable_http_proxy ? 1 : 0
  
  name_prefix = "${local.cluster_name}-proxy-"
  description = "Security group for HTTP proxy"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from VPC"
    from_port   = 3128
    to_port     = 3128
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr]
  }

  ingress {
    description = "HTTPS from VPC"
    from_port   = 3129
    to_port     = 3129
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr]
  }

  egress {
    description = "Allow outbound to approved sites"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.cluster_name}-proxy-sg" })
}

# ROSA HCP Cluster with Zero Egress
resource "rhcs_cluster_rosa_hcp" "cluster" {
  name               = local.cluster_name
  cloud_region       = var.aws_region
  version            = var.openshift_version
  
  # Network Configuration
  aws_subnet_ids = module.vpc.private_subnet_ids
  
  # Private cluster with PrivateLink
  private          = true
  aws_private_link = true
  
  # Compute Configuration
  replicas             = var.replicas
  compute_machine_type = var.compute_machine_type
  
  # Availability
  multi_az = length(var.availability_zones) > 1
  
  # OIDC Configuration
  oidc_config_id = rhcs_rosa_oidc_config.oidc_config.id
  
  # Account configuration
  aws_account_id = data.aws_caller_identity.current.account_id
  
  # HTTP Proxy Configuration (if enabled)
  proxy = var.enable_http_proxy ? {
    http_proxy  = "http://${aws_instance.http_proxy[0].private_ip}:3128"
    https_proxy = "http://${aws_instance.http_proxy[0].private_ip}:3128"
    no_proxy    = var.no_proxy
  } : null
  
  properties = {
    rosa_creator_arn = data.aws_caller_identity.current.arn
  }

  lifecycle {
    ignore_changes = [version]
  }

  depends_on = [
    rhcs_rosa_oidc_config.oidc_config,
    aws_instance.http_proxy
  ]
}

# Wait for cluster
resource "time_sleep" "wait_for_cluster" {
  depends_on      = [rhcs_cluster_rosa_hcp.cluster]
  create_duration = "10m"
}

# Admin Credentials
resource "rhcs_cluster_rosa_hcp_admin_credentials" "admin_credentials" {
  count = var.create_admin_user ? 1 : 0
  
  cluster = rhcs_cluster_rosa_hcp.cluster.id
  
  depends_on = [time_sleep.wait_for_cluster]
}

# Bastion Host for Cluster Access
resource "aws_security_group" "bastion" {
  name_prefix = "${local.cluster_name}-bastion-"
  description = "Security group for bastion host"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_allowed_cidr_blocks
  }

  egress {
    description = "Allow to VPC endpoints only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr]
  }

  egress {
    description = "Allow to cluster"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr]
  }

  tags = merge(local.tags, { Name = "${local.cluster_name}-bastion-sg" })
}

resource "aws_key_pair" "bastion" {
  key_name   = "${local.cluster_name}-bastion-key"
  public_key = var.bastion_ssh_public_key
  tags       = local.tags
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.bastion_instance_type
  key_name      = aws_key_pair.bastion.key_name
  
  subnet_id                   = module.vpc.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/bastion-user-data.sh", {
    cluster_name = local.cluster_name
    aws_region   = var.aws_region
  })

  root_block_device {
    volume_size = 30
    encrypted   = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  tags = merge(local.tags, { Name = "${local.cluster_name}-bastion" })
}

# S3 Bucket for Logs/Backups (Private)
resource "aws_s3_bucket" "cluster_data" {
  count = var.create_s3_bucket ? 1 : 0
  
  bucket = "${local.cluster_name}-data-${data.aws_caller_identity.current.account_id}"

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "cluster_data" {
  count = var.create_s3_bucket ? 1 : 0
  
  bucket = aws_s3_bucket.cluster_data[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cluster_data" {
  count = var.create_s3_bucket ? 1 : 0
  
  bucket = aws_s3_bucket.cluster_data[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cluster_data" {
  count = var.create_s3_bucket ? 1 : 0
  
  bucket = aws_s3_bucket.cluster_data[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Data Sources
data "aws_caller_identity" "current" {}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}