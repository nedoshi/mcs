
# ROSA HCP Public Cluster with Identity Providers and Machine Pools

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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
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
      Scenario    = "public-idp-pools"
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

# ROSA HCP Public Cluster
resource "rhcs_cluster_rosa_hcp" "cluster" {
  name               = local.cluster_name
  cloud_region       = var.aws_region
  version            = var.openshift_version
  
  # Network Configuration - both public and private subnets for public cluster
  aws_subnet_ids = concat(module.vpc.private_subnet_ids, module.vpc.public_subnet_ids)
  
  # Public cluster (default)
  private = false
  
  # Compute Configuration
  replicas             = var.default_replicas
  compute_machine_type = var.default_compute_machine_type
  
  # Availability
  multi_az = length(var.availability_zones) > 1
  
  # OIDC Configuration
  oidc_config_id = rhcs_rosa_oidc_config.oidc_config.id
  
  # Account configuration
  aws_account_id = data.aws_caller_identity.current.account_id
  
  properties = {
    rosa_creator_arn = data.aws_caller_identity.current.arn
  }

  lifecycle {
    ignore_changes = [version]
  }

  depends_on = [rhcs_rosa_oidc_config.oidc_config]
}

# Wait for cluster to be ready
resource "time_sleep" "wait_for_cluster" {
  depends_on      = [rhcs_cluster_rosa_hcp.cluster]
  create_duration = "10m"
}

# Development Machine Pool
resource "rhcs_hcp_machine_pool" "dev_pool" {
  count = var.create_dev_pool ? 1 : 0
  
  cluster = rhcs_cluster_rosa_hcp.cluster.id
  name    = "dev-pool"
  
  aws_node_pool = {
    instance_type = var.dev_instance_type
  }
  
  subnet_id = module.vpc.private_subnet_ids[0]
  
  autoscaling = var.enable_dev_autoscaling ? {
    enabled      = true
    min_replicas = var.dev_pool_min_replicas
    max_replicas = var.dev_pool_max_replicas
  } : null
  
  replicas = var.enable_dev_autoscaling ? null : var.dev_pool_replicas
  
  labels = {
    "environment" = "development"
    "pool-type"   = "dev"
  }

  depends_on = [time_sleep.wait_for_cluster]
}

# Production Machine Pool
resource "rhcs_hcp_machine_pool" "prod_pool" {
  count = var.create_prod_pool ? 1 : 0
  
  cluster = rhcs_cluster_rosa_hcp.cluster.id
  name    = "prod-pool"
  
  aws_node_pool = {
    instance_type = var.prod_instance_type
  }
  
  subnet_id = module.vpc.private_subnet_ids[1]
  
  autoscaling = var.enable_prod_autoscaling ? {
    enabled      = true
    min_replicas = var.prod_pool_min_replicas
    max_replicas = var.prod_pool_max_replicas
  } : null
  
  replicas = var.enable_prod_autoscaling ? null : var.prod_pool_replicas
  
  labels = {
    "environment" = "production"
    "pool-type"   = "prod"
  }

  depends_on = [time_sleep.wait_for_cluster]
}

# Testing Machine Pool
resource "rhcs_hcp_machine_pool" "test_pool" {
  count = var.create_test_pool ? 1 : 0
  
  cluster = rhcs_cluster_rosa_hcp.cluster.id
  name    = "test-pool"
  
  aws_node_pool = {
    instance_type = var.test_instance_type
  }
  
  subnet_id = module.vpc.private_subnet_ids[2 % length(module.vpc.private_subnet_ids)]
  
  autoscaling = var.enable_test_autoscaling ? {
    enabled      = true
    min_replicas = var.test_pool_min_replicas
    max_replicas = var.test_pool_max_replicas
  } : null
  
  replicas = var.enable_test_autoscaling ? null : var.test_pool_replicas
  
  labels = {
    "environment" = "testing"
    "pool-type"   = "test"
  }

  depends_on = [time_sleep.wait_for_cluster]
}

# HTPasswd Identity Provider (always created for emergency access)
resource "random_password" "htpasswd_password" {
  length  = 16
  special = true
}

resource "rhcs_identity_provider" "htpasswd_idp" {
  cluster = rhcs_cluster_rosa_hcp.cluster.id
  name    = "htpasswd"
  
  htpasswd = {
    users = [
      {
        username = var.htpasswd_username
        password = random_password.htpasswd_password.result
      }
    ]
  }

  depends_on = [time_sleep.wait_for_cluster]
}

# GitHub Identity Provider
resource "rhcs_identity_provider" "github_idp" {
  count = var.enable_github_idp ? 1 : 0
  
  cluster = rhcs_cluster_rosa_hcp.cluster.id
  name    = "github"
  
  github = {
    client_id     = var.github_client_id
    client_secret = var.github_client_secret
    organizations = var.github_organizations
    teams         = var.github_teams
    hostname      = var.github_hostname
    ca            = var.github_ca
  }

  depends_on = [time_sleep.wait_for_cluster]
}

# GitLab Identity Provider
resource "rhcs_identity_provider" "gitlab_idp" {
  count = var.enable_gitlab_idp ? 1 : 0
  
  cluster = rhcs_cluster_rosa_hcp.cluster.id
  name    = "gitlab"
  
  gitlab = {
    client_id     = var.gitlab_client_id
    client_secret = var.gitlab_client_secret
    url           = var.gitlab_url
    ca            = var.gitlab_ca
  }

  depends_on = [time_sleep.wait_for_cluster]
}

# Google Identity Provider
resource "rhcs_identity_provider" "google_idp" {
  count = var.enable_google_idp ? 1 : 0
  
  cluster = rhcs_cluster_rosa_hcp.cluster.id
  name    = "google"
  
  google = {
    client_id     = var.google_client_id
    client_secret = var.google_client_secret
    hosted_domain = var.google_hosted_domain
  }

  depends_on = [time_sleep.wait_for_cluster]
}

# LDAP Identity Provider
resource "rhcs_identity_provider" "ldap_idp" {
  count = var.enable_ldap_idp ? 1 : 0
  
  cluster = rhcs_cluster_rosa_hcp.cluster.id
  name    = "ldap"
  
  ldap = {
    bind_dn       = var.ldap_bind_dn
    bind_password = var.ldap_bind_password
    url           = var.ldap_url
    insecure      = var.ldap_insecure
    ca            = var.ldap_ca
    
    attributes = {
      id                = var.ldap_id_attributes
      email             = var.ldap_email_attributes
      name              = var.ldap_name_attributes
      preferred_username = var.ldap_preferred_username_attributes
    }
  }

  depends_on = [time_sleep.wait_for_cluster]
}

# OpenID Connect Identity Provider
resource "rhcs_identity_provider" "oidc_idp" {
  count = var.enable_oidc_idp ? 1 : 0
  
  cluster = rhcs_cluster_rosa_hcp.cluster.id
  name    = var.oidc_idp_name
  
  openid = {
    client_id                 = var.oidc_client_id
    client_secret             = var.oidc_client_secret
    issuer                    = var.oidc_issuer
    ca                        = var.oidc_ca
    claims = {
      email              = var.oidc_email_claims
      name               = var.oidc_name_claims
      preferred_username = var.oidc_preferred_username_claims
      groups             = var.oidc_groups_claims
    }
    extra_scopes = var.oidc_extra_scopes
  }

  depends_on = [time_sleep.wait_for_cluster]
}

# Grant cluster-admin to specific users (optional)
resource "null_resource" "grant_cluster_admin" {
  count = length(var.cluster_admin_users)
  
  provisioner "local-exec" {
    command = <<-EOT
      oc login ${rhcs_cluster_rosa_hcp.cluster.api_url} -u ${var.htpasswd_username} -p ${random_password.htpasswd_password.result}
      oc adm policy add-cluster-role-to-user cluster-admin ${var.cluster_admin_users[count.index]}
    EOT
  }

  depends_on = [
    rhcs_identity_provider.htpasswd_idp,
    rhcs_identity_provider.github_idp,
    rhcs_identity_provider.google_idp
  ]
}

# Data Sources
data "aws_caller_identity" "current" {}