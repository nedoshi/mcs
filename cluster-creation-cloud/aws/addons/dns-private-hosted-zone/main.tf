resource "aws_route53_zone" "private" {
  name = var.custom_domain

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(var.tags, {
    Name        = var.custom_domain
    ClusterName = var.cluster_name
  })
}

data "aws_lbs" "cluster_ingress" {
  tags = {
    cluster_name = var.cluster_name
  }
}

locals {
  ingress_nlb_arn = one([
    for arn in data.aws_lbs.cluster_ingress.arns : arn
    if can(regex(var.cluster_name, arn))
  ])
}

data "aws_lb" "ingress" {
  arn = local.ingress_nlb_arn
}

resource "aws_route53_record" "wildcard" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "*"
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress.dns_name
    zone_id                = data.aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}
