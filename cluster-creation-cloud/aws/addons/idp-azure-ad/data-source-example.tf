# Example: Accessing ROSA Cluster Information from Terraform Cloud
#
# This file demonstrates how to retrieve cluster information from a Terraform Cloud
# workspace where your ROSA cluster was created (e.g., using tf-rosa module).
#
# Choose one of the methods below based on your setup.

# ==============================================================================
# Method 1: Using terraform_remote_state Data Source
# ==============================================================================
# This method works when both workspaces are in the same Terraform Cloud organization
# and you have access to the source workspace.

# Uncomment and configure this if you want to use remote state:
#
# data "terraform_remote_state" "rosa_cluster" {
#   backend = "remote"
#   config = {
#     organization = "your-organization-name"
#     workspaces {
#       name = "your-rosa-cluster-workspace-name"  # Name of workspace where cluster was created
#     }
#   }
# }
#
# Then reference outputs like this:
# locals {
#   cluster_id = data.terraform_remote_state.rosa_cluster.outputs.cluster_id
#   cluster_api_url = data.terraform_remote_state.rosa_cluster.outputs.cluster_api_url
#   cluster_console_url = data.terraform_remote_state.rosa_cluster.outputs.cluster_console_url
# }

# ==============================================================================
# Method 2: Using Terraform Cloud API
# ==============================================================================
# Alternative approach using external data source or HTTP provider
# This requires a Terraform Cloud API token with read access

# Example using HTTP data source (requires Terraform Cloud API token):
#
# data "http" "workspace_outputs" {
#   url = "https://app.terraform.io/api/v2/workspaces/${var.tfc_workspace_id}/current-state-version/outputs"
#   request_headers = {
#     Authorization = "Bearer ${var.tfc_api_token}"
#   }
# }

# ==============================================================================
# Method 3: Manual Variable Input (Current Approach)
# ==============================================================================
# The simplest approach is to manually provide cluster_id as a variable.
# You can get this value from:
# 1. Terraform Cloud workspace outputs (web UI)
# 2. Running: terraform output cluster_id (in the cluster workspace)
# 3. ROSA CLI: rosa describe cluster <cluster-name>
# 4. OCM Console: https://console.redhat.com/openshift

# The cluster_id variable is defined in variables.tf and should be set in terraform.tfvars

# ==============================================================================
# Example: Using Remote State (if enabled above)
# ==============================================================================
# If you uncommented the terraform_remote_state data source above, you can use it like this:

# resource "rhcs_identity_provider" "azure_ad" {
#   cluster = data.terraform_remote_state.rosa_cluster.outputs.cluster_id
#   name    = var.idp_name
#   # ... rest of configuration
# }

# ==============================================================================
# Outputs from Remote State (if using Method 1)
# ==============================================================================
# If using remote state, you can expose cluster information as outputs:

# output "cluster_api_url_from_remote" {
#   description = "Cluster API URL from remote state"
#   value       = try(data.terraform_remote_state.rosa_cluster.outputs.cluster_api_url, null)
#   sensitive   = false
# }
#
# output "cluster_console_url_from_remote" {
#   description = "Cluster console URL from remote state"
#   value       = try(data.terraform_remote_state.rosa_cluster.outputs.cluster_console_url, null)
#   sensitive   = false
# }

