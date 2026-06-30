output "vpc_id" {
  description = "The ID of the VPC created for the ROSA cluster"
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = module.network.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.network.public_subnets
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.network.private_subnets
}

output "availability_zones" {
  description = "Availability zones used for private subnets"
  value       = module.network.availability_zones
}

output "oidc_config_id" {
  description = "The ID of the OIDC configuration"
  value       = local.cluster_oidc_config_id
}

output "oidc_endpoint_url" {
  description = "The OIDC endpoint URL"
  value       = local.cluster_oidc_endpoint_url
}

output "cluster_api_url" {
  description = "The API URL for the ROSA cluster"
  value       = local.cluster_api_url
}

output "cluster_console_url" {
  description = "The console URL for the ROSA cluster"
  value       = local.cluster_console_url
}

output "cluster_id" {
  description = "The ID of the ROSA cluster"
  value       = local.cluster_id
}

output "cluster_name" {
  description = "The name of the ROSA cluster"
  value       = local.cluster_name
}

output "region" {
  description = "The AWS region where the cluster is deployed"
  value       = var.region
}

output "bastion_instance_id" {
  description = "The instance ID of the bastion host (only set for private clusters)"
  value       = var.private ? aws_instance.bastion_host[0].id : null
}

output "bastion_public_ip" {
  description = "The public IP address of the bastion host (only set for private clusters with public IP enabled)"
  value       = (var.private && var.bastion_public_ip) ? aws_instance.bastion_host[0].public_ip : null
}

output "bastion_connectivity" {
  description = "Instructions for connecting to the bastion host (only set for private clusters)"
  value       = local.bastion_output
}

output "cluster_domain" {
  description = "Cluster DNS domain"
  value       = local.cluster_domain
}

output "external_auth_enabled" {
  description = "Whether external authentication was enabled at cluster creation"
  value       = var.external_auth_providers_enabled
}

output "oauth_callback_url" {
  description = "OAuth callback URL template for external IdP configuration"
  value       = var.external_auth_providers_enabled ? "https://oauth-openshift.apps.${local.cluster_domain}/oauth2callback/<provider_name>" : null
}

output "kms_key_arn" {
  description = "ARN of the cluster KMS key when using customer-managed encryption"
  value       = local.cluster_kms_key_arn
}
