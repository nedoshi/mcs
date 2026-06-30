# Shared VPC Module - Outputs

output "vpc_id" {
  description = "ID of the shared VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = [for s in aws_subnet.private : s.id]
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "hcp_internal_hosted_zone_id" {
  description = "Route53 hosted zone ID for HCP internal (hypershift.local)"
  value       = aws_route53_zone.hcp_internal.zone_id
}

output "ingress_hosted_zone_id" {
  description = "Route53 hosted zone ID for ingress"
  value       = aws_route53_zone.ingress.zone_id
}

output "route53_role_arn" {
  description = "ARN of the IAM role for Route53 management"
  value       = aws_iam_role.route53.arn
}

output "vpc_endpoint_role_arn" {
  description = "ARN of the IAM role for VPC endpoints"
  value       = aws_iam_role.vpc_endpoint.arn
}
/*
output "ram_share_arn" {
  description = "ARN of the RAM resource share"
  value       = aws_ram_resource_share.vpc.arn
}
*/