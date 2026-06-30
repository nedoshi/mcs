output "private_zone_id" {
  description = "Route53 private hosted zone ID"
  value       = aws_route53_zone.private.zone_id
}

output "private_zone_name" {
  description = "Private hosted zone DNS name"
  value       = aws_route53_zone.private.name
}

output "ingress_nlb_dns_name" {
  description = "DNS name of the cluster ingress network load balancer"
  value       = data.aws_lb.ingress.dns_name
}
