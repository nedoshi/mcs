# ROSA HCP Private Cluster with PrivateLink and Bastion Host

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
      Scenario    = "private-privatelink"
    }
  )
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  cluster_name       = local.cluster_name
  aws_region         = var.aws_region
  create_vpc         = var.create_vpc
  existing_vpc_id    = var.existing_vpc_id
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  
  create_public_subnets = true  # Need public subnet for bastion
  single_nat_gateway    = var.single_nat_gateway
  
  tags = local.tags
}

# Account Roles (only needed once per AWS account)
resource "rhcs_rosa_account_roles" "account_roles" {
  count = var.create_account_roles ? 1 : 0

  account_role_prefix = "${local.cluster_name}-account"
  openshift_version   = var.openshift_version
}

# OIDC Config
resource "rhcs_rosa_oidc_config" "oidc_config" {
  managed = true
}

# Operator Roles
resource "rhcs_rosa_operator_roles" "operator_roles" {
  cluster_id          = rhcs_cluster_rosa_hcp.cluster.id
  operator_role_prefix = "${local.cluster_name}-operator"
  account_role_prefix  = var.create_account_roles ? rhcs_rosa_account_roles.account_roles[0].account_role_prefix : var.existing_account_role_prefix
  oidc_config_id       = rhcs_rosa_oidc_config.oidc_config.id
}

# ROSA HCP Private Cluster with PrivateLink
resource "rhcs_cluster_rosa_hcp" "cluster" {
  name               = local.cluster_name
  cloud_region       = var.aws_region
  version            = var.openshift_version
  
  # Network Configuration
  aws_subnet_ids = module.vpc.private_subnet_ids
  
  # Private cluster with PrivateLink
  private = true
  aws_private_link = true
  
  # Compute Configuration
  replicas             = var.replicas
  compute_machine_type = var.compute_machine_type
  
  # Availability
  multi_az = length(var.availability_zones) > 1
  
  # OIDC Configuration
  oidc_config_id = rhcs_rosa_oidc_config.oidc_config.id
  
  # Account roles
  aws_account_id = data.aws_caller_identity.current.account_id
  
  properties = {
    rosa_creator_arn = data.aws_caller_identity.current.arn
  }

  lifecycle {
    ignore_changes = [
      version  # Prevent unwanted upgrades
    ]
  }

  depends_on = [
    rhcs_rosa_oidc_config.oidc_config
  ]
}

# Wait for cluster to be ready
resource "time_sleep" "wait_for_cluster" {
  depends_on = [rhcs_cluster_rosa_hcp.cluster]
  create_duration = "10m"
}

# Cluster Admin User (optional)
resource "rhcs_cluster_rosa_hcp_admin_credentials" "admin_credentials" {
  count = var.create_admin_user ? 1 : 0
  
  cluster = rhcs_cluster_rosa_hcp.cluster.id
  
  depends_on = [time_sleep.wait_for_cluster]
}

# Bastion Host Security Group
resource "aws_security_group" "bastion" {
  name_prefix = "${local.cluster_name}-bastion-"
  description = "Security group for bastion host"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH from allowed CIDR blocks"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-bastion-sg"
    }
  )
}

# Bastion Host Key Pair
resource "aws_key_pair" "bastion" {
  key_name   = "${local.cluster_name}-bastion-key"
  public_key = var.bastion_ssh_public_key

  tags = local.tags
}

# Bastion Host
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.bastion_instance_type
  key_name      = aws_key_pair.bastion.key_name
  
  subnet_id                   = module.vpc.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user-data.sh", {
    cluster_name = local.cluster_name
  })

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-bastion"
    }
  )
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
