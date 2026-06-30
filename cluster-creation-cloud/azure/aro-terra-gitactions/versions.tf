terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.3.0, < 4.0.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 1.0.0, < 2.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0, < 4.0.0"
    }
  }

  cloud {
    organization = "OpenShift"

    workspaces {
      name = "aro-terra-gitaction"
    }
  }
}

