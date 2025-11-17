# ROSA HCP Private Cluster with AI and Virtualization Machine Pools

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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
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
      Scenario    = "private-ai-virt-pools"
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
  
  create_public_subnets = true
  single_nat_gateway    = var.single_nat_gateway
  
  tags = local.tags
}

# OIDC Config
resource "rhcs_rosa_oidc_config" "oidc_config" {
  managed = true
}

# Local values for STS roles
locals {
  account_role_prefix = var.create_account_roles ? "${local.cluster_name}-account" : var.existing_account_role_prefix
  operator_role_prefix = "${local.cluster_name}-operator"
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_account_arn = data.aws_caller_identity.current.arn
  
  sts_roles = {
    role_arn         = "arn:aws:iam::${local.aws_account_id}:role/${local.account_role_prefix}-HCP-ROSA-Installer-Role"
    support_role_arn  = "arn:aws:iam::${local.aws_account_id}:role/${local.account_role_prefix}-HCP-ROSA-Support-Role"
    instance_iam_roles = {
      worker_role_arn = "arn:aws:iam::${local.aws_account_id}:role/${local.account_role_prefix}-HCP-ROSA-Worker-Role"
    }
    operator_role_prefix = local.operator_role_prefix
    oidc_config_id      = rhcs_rosa_oidc_config.oidc_config.id
  }
}

# ROSA HCP Cluster
resource "rhcs_cluster_rosa_hcp" "cluster" {
  name               = local.cluster_name
  cloud_region       = var.aws_region
  version            = var.openshift_version
  
  # Network Configuration
  aws_subnet_ids = module.vpc.private_subnet_ids
  
  # Private cluster
  private = true
  
  # Required STS configuration
  sts = local.sts_roles
  
  # Required availability zones
  availability_zones = var.availability_zones
  
  # Default Compute Configuration
  replicas             = var.default_replicas
  compute_machine_type = var.default_compute_machine_type
  
  # Account configuration
  aws_account_id = local.aws_account_id
  
  # Admin user configuration
  create_admin_user = var.create_admin_user
  
  properties = {
    rosa_creator_arn = local.aws_account_arn
  }

  lifecycle {
    ignore_changes = [version]
  }

  depends_on = [rhcs_rosa_oidc_config.oidc_config]
}

# Wait for cluster to be ready
resource "time_sleep" "wait_for_cluster" {
  depends_on = [rhcs_cluster_rosa_hcp.cluster]
  create_duration = "10m"
}

# AI Workload Machine Pool (GPU instances)
resource "rhcs_hcp_machine_pool" "ai_pool" {
  cluster      = rhcs_cluster_rosa_hcp.cluster.id
  name         = "ai-gpu-pool"
  
  # GPU Instance Types
  aws_node_pool = {
    instance_type = var.ai_instance_type  # e.g., p3.2xlarge, p4d.24xlarge, g5.xlarge
  }
  
  replicas      = var.ai_pool_replicas
  subnet_id     = module.vpc.private_subnet_ids[0]
  auto_repair   = true
  
  # Auto-scaling configuration
  autoscaling = var.enable_ai_autoscaling ? {
    enabled = true
    min_replicas = var.ai_pool_min_replicas
    max_replicas = var.ai_pool_max_replicas
  } : null
  
  # Labels for workload scheduling
  labels = {
    "workload-type" = "ai"
    "gpu-enabled"   = "true"
    "node-role"     = "ai-ml"
  }
  
  # Taints to dedicate nodes to AI workloads
  taints = var.taint_ai_nodes ? [
    {
      key          = "workload"
      value        = "ai"
      effect       = "NoSchedule"
      schedule_type = "NoSchedule"
    }
  ] : []

  depends_on = [time_sleep.wait_for_cluster]
}

# Virtualization Machine Pool (Bare Metal)
resource "rhcs_hcp_machine_pool" "virt_pool" {
  cluster      = rhcs_cluster_rosa_hcp.cluster.id
  name         = "virt-baremetal-pool"
  
  # Bare metal or metal-optimized instances
  aws_node_pool = {
    instance_type = var.virt_instance_type  # e.g., m5.metal, m5zn.metal, c5n.metal
  }
  
  replicas      = var.virt_pool_replicas
  subnet_id     = module.vpc.private_subnet_ids[1]
  auto_repair   = true
  
  # Auto-scaling
  autoscaling = var.enable_virt_autoscaling ? {
    enabled = true
    min_replicas = var.virt_pool_min_replicas
    max_replicas = var.virt_pool_max_replicas
  } : null
  
  # Labels for virtualization workloads
  labels = {
    "workload-type"      = "virtualization"
    "bare-metal"         = "true"
    "kubevirt-node"      = "true"
    "feature.node.kubernetes.io/cpu-hardware_multithreading" = "true"
  }
  
  # Taints to dedicate nodes to virtualization
  taints = var.taint_virt_nodes ? [
    {
      key          = "workload"
      value        = "virtualization"
      effect       = "NoSchedule"
      schedule_type = "NoSchedule"
    }
  ] : []

  depends_on = [time_sleep.wait_for_cluster]
}

# High-Memory Machine Pool (for data-intensive workloads)
resource "rhcs_hcp_machine_pool" "highmem_pool" {
  count = var.create_highmem_pool ? 1 : 0
  
  cluster      = rhcs_cluster_rosa_hcp.cluster.id
  name         = "highmem-pool"
  
  aws_node_pool = {
    instance_type = var.highmem_instance_type  # e.g., r5.4xlarge, x1e.xlarge
  }
  
  replicas      = var.highmem_pool_replicas
  subnet_id     = module.vpc.private_subnet_ids[2]
  auto_repair   = true
  
  # Autoscaling is required - set to disabled
  autoscaling = {
    enabled = false
  }
  
  labels = {
    "workload-type" = "memory-intensive"
    "high-memory"   = "true"
  }

  depends_on = [time_sleep.wait_for_cluster]
}


# Bastion Host (for cluster access)
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
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

  root_block_device {
    volume_size = 30
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.tags, { Name = "${local.cluster_name}-bastion" })
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
}