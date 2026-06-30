output "internal_api_lb_arn" {
  value = aws_lb.internal_api.arn
}

output "external_api_lb_arn" {
  value = aws_lb.external_api.arn
}

output "internal_api_lb_dns_name" {
  value = aws_lb.internal_api.dns_name
}

output "internal_api_lb_zone_id" {
  value = aws_lb.internal_api.zone_id
}

output "external_api_lb_dns_name" {
  value = aws_lb.external_api.dns_name
}

output "external_api_lb_zone_id" {
  value = aws_lb.external_api.zone_id
}

output "internal_api_target_group_arn" {
  value = aws_lb_target_group.internal_api.arn
}

output "internal_service_target_group_arn" {
  value = aws_lb_target_group.internal_service.arn
}

output "external_api_target_group_arn" {
  value = aws_lb_target_group.external_api.arn
}
