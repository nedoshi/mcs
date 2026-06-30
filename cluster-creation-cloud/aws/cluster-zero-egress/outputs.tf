output "cluster_id" {
  description = "The ID of the ROSA HCP cluster"
  value       = module.rosa-hcp.cluster_id
}

output "cluster_name" {
  description = "The name of the ROSA HCP cluster"
  value       = local.cluster_name
}

output "cluster_console_url" {
  description = "The URL of the OpenShift console"
  value       = module.rosa-hcp.cluster_console_url
}

output "cluster_api_url" {
  description = "The API endpoint URL of the ROSA HCP cluster"
  value       = module.rosa-hcp.cluster_api_url
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "The IDs of the private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "The IDs of the public subnets"
  value       = module.vpc.public_subnets
}

output "vpc_endpoint_ids" {
  description = "The IDs of the VPC endpoints created for zero egress"
  value = {
    sts     = aws_vpc_endpoint.sts.id
    ecr_api = aws_vpc_endpoint.ecr_api.id
    ecr_dkr = aws_vpc_endpoint.ecr_dkr.id
    s3      = aws_vpc_endpoint.s3.id
  }
}

