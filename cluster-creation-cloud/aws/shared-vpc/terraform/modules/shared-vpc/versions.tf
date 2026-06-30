# Shared VPC Module - Provider Requirements
# Declares aws provider for provider alias passthrough from parent

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.38.0"
    }
  }
}
