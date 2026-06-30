# Terraform and Provider Configuration
# ROSA HCP Cluster Automation

terraform {
  required_version = ">= 1.4.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.38"
      configuration_aliases = [aws.shared_vpc_account]
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.6"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# -----------------------------------------------------------------------------
# AWS Provider - Default (cluster account)
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

# -----------------------------------------------------------------------------
# AWS Provider - Shared VPC Account
# -----------------------------------------------------------------------------
provider "aws" {
  alias  = "shared_vpc_account"
  region = var.region

  assume_role {
    role_arn = var.shared_vpc_role_arn
  }

  default_tags {
    tags = var.tags
  }
}

# -----------------------------------------------------------------------------
# RHCS Provider - Red Hat Cloud Services
# -----------------------------------------------------------------------------
provider "rhcs" {
  token = var.rhcs_token
}

# -----------------------------------------------------------------------------
# Kubernetes Provider — uses oc/kubectl context after cluster login
# Run `oc login` after cluster creation, then apply post-install resources.
# In CI/CD, use a service account token or exec-based auth.
# -----------------------------------------------------------------------------
provider "kubernetes" {
  host                   = try(module.rosa_cluster.cluster_api_url, "https://placeholder")
  insecure               = false
  config_path            = "~/.kube/config"
}

# -----------------------------------------------------------------------------
# Helm Provider — same kubeconfig
# -----------------------------------------------------------------------------
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# -----------------------------------------------------------------------------
# Azure AD (Entra ID) Provider — authenticates via Azure CLI or env vars
# Set ARM_TENANT_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET or run `az login`.
# -----------------------------------------------------------------------------
provider "azuread" {}
