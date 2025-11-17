# scenarios/3-public-idp-pools/outputs.tf

output "cluster_id" {
  description = "Cluster ID"
  value       = rhcs_cluster_rosa_hcp.cluster.id
}

output "cluster_name" {
  description = "Cluster name"
  value       = rhcs_cluster_rosa_hcp.cluster.name
}

output "cluster_api_url" {
  description = "Cluster API URL"
  value       = rhcs_cluster_rosa_hcp.cluster.api_url
}

output "cluster_console_url" {
  description = "Cluster console URL"
  value       = rhcs_cluster_rosa_hcp.cluster.console_url
}

output "htpasswd_username" {
  description = "HTPasswd username"
  value       = var.htpasswd_username
}

output "htpasswd_password" {
  description = "HTPasswd password"
  value       = random_password.htpasswd_password.result
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "connection_instructions" {
  description = "Connection instructions"
  value = <<-EOT
    
    ========================================
    ROSA HCP Public Cluster Access
    ========================================
    
    Cluster Console: ${rhcs_cluster_rosa_hcp.cluster.console_url}
    API URL: ${rhcs_cluster_rosa_hcp.cluster.api_url}
    
    Login with HTPasswd (Emergency Access):
    oc login ${rhcs_cluster_rosa_hcp.cluster.api_url} -u ${var.htpasswd_username} -p $(terraform output -raw htpasswd_password)
    
    ${var.enable_github_idp ? "GitHub OAuth: Enabled - Login via console" : ""}
    ${var.enable_google_idp ? "Google OAuth: Enabled - Login via console" : ""}
    ${var.enable_gitlab_idp ? "GitLab OAuth: Enabled - Login via console" : ""}
    
    Machine Pools:
    - Default: ${var.default_replicas} x ${var.default_compute_machine_type}
    ${var.create_dev_pool ? "- Development: ${var.enable_dev_autoscaling ? "${var.dev_pool_min_replicas}-${var.dev_pool_max_replicas}" : var.dev_pool_replicas} x ${var.dev_instance_type}" : ""}
    ${var.create_prod_pool ? "- Production: ${var.enable_prod_autoscaling ? "${var.prod_pool_min_replicas}-${var.prod_pool_max_replicas}" : var.prod_pool_replicas} x ${var.prod_instance_type}" : ""}
    
    ========================================
  EOT
}