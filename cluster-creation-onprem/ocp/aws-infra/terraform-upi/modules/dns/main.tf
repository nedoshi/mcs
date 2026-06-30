resource "aws_route53_zone" "private" {
  name = local.cluster_domain

  vpc {
    vpc_id = var.vpc_id
  }

  force_destroy = true

  tags = merge(var.tags, {
    Name                                      = "${local.cluster_domain}."
    "kubernetes.io/cluster/${var.infrastructure_name}" = "owned"
  })
}

resource "aws_route53_record" "api_int" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "api-int.${local.cluster_domain}"
  type    = "A"

  alias {
    name                   = var.internal_api_lb_dns_name
    zone_id                = var.internal_api_lb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "api_private" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "api.${local.cluster_domain}"
  type    = "A"

  alias {
    name                   = var.internal_api_lb_dns_name
    zone_id                = var.internal_api_lb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "api_public" {
  count = var.create_public_dns_records ? 1 : 0

  zone_id = var.public_hosted_zone_id
  name    = "api.${local.cluster_domain}"
  type    = "A"

  alias {
    name                   = var.external_api_lb_dns_name
    zone_id                = var.external_api_lb_zone_id
    evaluate_target_health = true
  }
}
