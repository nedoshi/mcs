terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.20.0"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = ">= 1.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

provider "rhcs" {
  token        = var.token
  client_id    = var.client_id
  client_secret = var.client_secret
}

provider "aws" {
  region = var.region
}

