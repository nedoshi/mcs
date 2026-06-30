output "cluster_id" {
  description = "ID of the ROSA HCP cluster"
  value       = rhcs_cluster_rosa_hcp.main.id
}

output "cluster_api_url" {
  description = "API URL of the ROSA HCP cluster"
  value       = rhcs_cluster_rosa_hcp.main.api_url
}

output "cluster_console_url" {
  description = "Web console URL of the ROSA HCP cluster"
  value       = rhcs_cluster_rosa_hcp.main.console_url
}

output "cluster_state" {
  description = "Current state of the cluster"
  value       = rhcs_cluster_rosa_hcp.main.state
}
