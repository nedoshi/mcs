terraform {
  required_version = ">= 1.5.0"

  required_providers {
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = ">= 1.7.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.20.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.1"
    }
  }
}

provider "rhcs" {
  token         = local.rhcs_use_token ? var.token : null
  client_id     = local.rhcs_use_client ? var.client_id : "cloud-services"
  client_secret = local.rhcs_use_client ? var.client_secret : ""
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}
