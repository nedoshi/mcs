# scenarios/4-zero-egress/outputs.tf

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

output "admin_username" {
  description = "Admin username"
  value       = var.create_admin_user ? rhcs_cluster_rosa_hcp_admin_credentials.admin_credentials[0].username : null
}

output "admin_password" {
  description = "Admin password"
  value       = var.create_admin_user ? rhcs_cluster_rosa_hcp_admin_credentials.admin_credentials[0].password : null
  sensitive   = true
}

output "bastion_public_ip" {
  description = "Bastion public IP"
  value       = aws_instance.bastion.public_ip
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = var.create_ecr_repository ? aws_ecr_repository.cluster_images[0].repository_url : null
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = var.create_s3_bucket ? aws_s3_bucket.cluster_data[0].id : null
}

output "http_proxy_url" {
  description = "HTTP proxy URL"
  value       = var.enable_http_proxy ? "http://${aws_instance.http_proxy[0].private_ip}:3128" : null
}

output "connection_instructions" {
  description = "Connection instructions"
  value = <<-EOT
    
    ========================================
    ROSA HCP Zero Egress Cluster
    ========================================
    
    This is a ZERO EGRESS cluster - no internet access from worker nodes.
    All AWS services accessed via VPC endpoints.
    
    1. SSH to Bastion:
       ssh -i <key> ec2-user@${aws_instance.bastion.public_ip}
    
    2. Login to Cluster:
       oc login ${rhcs_cluster_rosa_hcp.cluster.api_url} -u ${var.create_admin_user ? rhcs_cluster_rosa_hcp_admin_credentials.admin_credentials[0].username : "admin"} -p <password>
    
    3. Container Registry (Private ECR):
       ${var.create_ecr_repository ? "ECR URL: ${aws_ecr_repository.cluster_images[0].repository_url}" : "ECR not created"}
    
    4. HTTP Proxy:
       ${var.enable_http_proxy ? "Proxy: http://${aws_instance.http_proxy[0].private_ip}:3128" : "HTTP Proxy not enabled"}
    
    5. VPC Endpoints Created:
       ${join(", ", var.vpc_interface_endpoints)}
    
    IMPORTANT: To push images to ECR from outside the cluster:
    - Use AWS CLI with proper credentials
    - Images must be pulled from ECR within the cluster
    
    ========================================
  EOT
}