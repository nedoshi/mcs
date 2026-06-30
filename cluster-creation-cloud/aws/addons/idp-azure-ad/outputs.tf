# Identity Provider Outputs
output "idp_name" {
  description = "Name of the created identity provider"
  value       = rhcs_identity_provider.azure_ad.name
}

output "cluster_id" {
  description = "ROSA cluster ID"
  value       = var.cluster_id
}

# Cluster Connection Information
# These outputs help you connect to the cluster
# If you're using remote state from the cluster workspace, you can reference those outputs instead

# Note: To get cluster_api_url and cluster_console_url, you can either:
# 1. Use terraform_remote_state data source (see data-source-example.tf)
# 2. Get them from Terraform Cloud workspace outputs (web UI)
# 3. Use ROSA CLI: rosa describe cluster <cluster-name>
# 4. Query OCM API

# Example outputs if you have cluster information available:
# output "cluster_api_url" {
#   description = "Cluster API endpoint URL"
#   value       = try(data.terraform_remote_state.rosa_cluster.outputs.cluster_api_url, null)
# }
#
# output "cluster_console_url" {
#   description = "OpenShift web console URL"
#   value       = try(data.terraform_remote_state.rosa_cluster.outputs.cluster_console_url, null)
# }

