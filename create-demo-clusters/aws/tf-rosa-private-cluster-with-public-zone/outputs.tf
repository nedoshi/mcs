output "cluster_id" {
  description = "The ID of the ROSA cluster"
  value       = module.rosa-classic.cluster_id
}

output "cluster_name" {
  description = "The name of the ROSA cluster"
  value       = local.cluster_name
}

output "cluster_api_url" {
  description = "The API endpoint URL of the ROSA cluster"
  value       = data.rhcs_cluster_rosa_classic.cluster.api_url
}

output "cluster_console_url" {
  description = "The URL of the OpenShift console"
  value       = data.rhcs_cluster_rosa_classic.cluster.console_url
}

output "cluster_domain" {
  description = "The base domain of the cluster"
  value       = data.rhcs_cluster_rosa_classic.cluster.domain
}

output "cluster_base_dns_domain" {
  description = "The base DNS domain of the cluster"
  value       = data.rhcs_cluster_rosa_classic.cluster.base_dns_domain
}

output "vpc_id" {
  description = "The ID of the VPC (if created)"
  value       = var.create_vpc ? module.vpc[0].vpc_id : null
}

output "private_subnet_ids" {
  description = "The IDs of the private subnets (if VPC created)"
  value       = var.create_vpc ? module.vpc[0].private_subnets : null
}

output "public_subnet_ids" {
  description = "The IDs of the public subnets (if VPC created)"
  value       = var.create_vpc ? module.vpc[0].public_subnets : null
}

output "public_zone_id" {
  description = "The Route53 hosted zone ID for the public zone"
  value       = data.aws_route53_zone.public_zone.zone_id
}

output "api_record_name" {
  description = "The Route53 record name for the API endpoint"
  value       = aws_route53_record.api-to-public-zone.name
}

