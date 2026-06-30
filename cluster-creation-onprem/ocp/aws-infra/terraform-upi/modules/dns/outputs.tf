output "private_hosted_zone_id" {
  value = aws_route53_zone.private.zone_id
}

output "cluster_domain" {
  value = local.cluster_domain
}
