terraform {
  required_version = ">= 1.0"

  required_providers {
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = ">= 1.7.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.20.0"
    }
  }

  # Terraform Cloud backend configuration
  # Update organization and workspace name to match your Terraform Cloud setup
  backend "remote" {
    organization = "your-organization-name"

    workspaces {
      name = "rosa-cluster-idp-setup"
    }
  }
}

# AWS provider configuration
provider "aws" {
  region = var.region
}

# RHCS provider configuration
# Uses either token OR client_id/client_secret for authentication
provider "rhcs" {
  token        = var.token
  client_id     = var.client_id
  client_secret = var.client_secret
}

