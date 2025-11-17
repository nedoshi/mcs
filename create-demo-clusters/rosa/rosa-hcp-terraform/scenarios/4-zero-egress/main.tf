# ROSA HCP Zero Egress Cluster
# This scenario creates a private ROSA HCP cluster with zero egress configuration
# Zero egress means the cluster has no outbound internet connectivity and relies
# entirely on VPC endpoints for AWS service access.

# Note: This scenario uses the terraform-redhat/rosa-hcp/rhcs module
# which handles account roles, operator roles, and cluster creation.

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.20.0"
    }
    rhcs = {
      version = ">= 1.5.0"
      source  = "terraform-redhat/rhcs"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

data "aws_caller_identity" "current" {}

provider "rhcs" {
  token        = var.token
  # client_id    = var.client_id
  #client_secret =  var.client_secret
}

provider "aws" {
  region = var.aws_region != null ? var.aws_region : "us-east-1"
}

