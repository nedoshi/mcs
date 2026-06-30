resource "aws_lb" "internal_api" {
  name               = "${var.infrastructure_name}-int"
  load_balancer_type = "network"
  internal           = true
  subnets            = var.private_subnet_ids

  tags = var.tags
}

resource "aws_lb" "external_api" {
  name               = "${var.infrastructure_name}-ext"
  load_balancer_type = "network"
  internal           = false
  subnets            = var.public_subnet_ids

  tags = var.tags
}

resource "aws_lb_target_group" "internal_api" {
  name             = "${var.infrastructure_name}-6443-int-tg"
  port             = 6443
  protocol         = "TCP"
  vpc_id           = var.vpc_id
  target_type      = "ip"
  deregistration_delay = 60

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    protocol            = "HTTPS"
    port                = "6443"
    path                = "/readyz"
  }

  tags = var.tags
}

resource "aws_lb_target_group" "internal_service" {
  name             = "${var.infrastructure_name}-22623-int-tg"
  port             = 22623
  protocol         = "TCP"
  vpc_id           = var.vpc_id
  target_type      = "ip"
  deregistration_delay = 60

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    protocol            = "HTTPS"
    port                = "22623"
    path                = "/healthz"
  }

  tags = var.tags
}

resource "aws_lb_target_group" "external_api" {
  name             = "${var.infrastructure_name}-6443-ext-tg"
  port             = 6443
  protocol         = "TCP"
  vpc_id           = var.vpc_id
  target_type      = "ip"
  deregistration_delay = 60

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    protocol            = "HTTPS"
    port                = "6443"
    path                = "/readyz"
  }

  tags = var.tags
}

resource "aws_lb_listener" "internal_api_6443" {
  load_balancer_arn = aws_lb.internal_api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal_api.arn
  }
}

resource "aws_lb_listener" "internal_api_22623" {
  load_balancer_arn = aws_lb.internal_api.arn
  port              = 22623
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal_service.arn
  }
}

resource "aws_lb_listener" "external_api_6443" {
  load_balancer_arn = aws_lb.external_api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.external_api.arn
  }
}
