resource "aws_security_group" "master" {
  name        = "${var.infrastructure_name}-master"
  description = "OpenShift control plane"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name                                      = "${var.infrastructure_name}-master"
    "kubernetes.io/cluster/${var.infrastructure_name}" = "shared"
  })
}

resource "aws_security_group" "worker" {
  name        = "${var.infrastructure_name}-worker"
  description = "OpenShift worker"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name                                      = "${var.infrastructure_name}-worker"
    "kubernetes.io/cluster/${var.infrastructure_name}" = "shared"
  })
}

locals {
  master_vpc_ingress = [
    { proto = "icmp", from = 0, to = 0 },
    { proto = "tcp", from = 22, to = 22 },
    { proto = "tcp", from = 6443, to = 6443 },
    { proto = "tcp", from = 22623, to = 22623 },
  ]

  master_sg_ingress = [
    { proto = "tcp", from = 2379, to = 2380, desc = "etcd" },
    { proto = "udp", from = 4789, to = 4789, desc = "vxlan" },
    { proto = "udp", from = 6081, to = 6081, desc = "geneve" },
    { proto = "udp", from = 500, to = 500, desc = "ipsec-ike" },
    { proto = "udp", from = 4500, to = 4500, desc = "ipsec-nat" },
    { proto = "50", from = 0, to = 0, desc = "ipsec-esp" },
    { proto = "tcp", from = 9000, to = 9999, desc = "cluster-internal" },
    { proto = "udp", from = 9000, to = 9999, desc = "cluster-internal-udp" },
    { proto = "tcp", from = 10250, to = 10259, desc = "kubelet" },
    { proto = "tcp", from = 30000, to = 32767, desc = "nodeport-tcp" },
    { proto = "udp", from = 30000, to = 32767, desc = "nodeport-udp" },
  ]

  worker_vpc_ingress = [
    { proto = "icmp", from = 0, to = 0 },
    { proto = "tcp", from = 22, to = 22 },
    { proto = "tcp", from = 80, to = 80 },
    { proto = "tcp", from = 443, to = 443 },
  ]

  worker_sg_ingress = [
    { proto = "udp", from = 4789, to = 4789, desc = "vxlan" },
    { proto = "udp", from = 6081, to = 6081, desc = "geneve" },
    { proto = "udp", from = 500, to = 500, desc = "ipsec-ike" },
    { proto = "udp", from = 4500, to = 4500, desc = "ipsec-nat" },
    { proto = "50", from = 0, to = 0, desc = "ipsec-esp" },
    { proto = "tcp", from = 9000, to = 9999, desc = "cluster-internal" },
    { proto = "udp", from = 9000, to = 9999, desc = "cluster-internal-udp" },
    { proto = "tcp", from = 10250, to = 10250, desc = "kubelet" },
    { proto = "tcp", from = 30000, to = 32767, desc = "nodeport-tcp" },
    { proto = "udp", from = 30000, to = 32767, desc = "nodeport-udp" },
  ]
}

resource "aws_vpc_security_group_ingress_rule" "master_vpc" {
  for_each = { for r in local.master_vpc_ingress : "${r.proto}-${r.from}-${r.to}" => r }

  security_group_id = aws_security_group.master.id
  ip_protocol       = each.value.proto
  from_port         = each.value.from
  to_port           = each.value.to
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "master_from_master" {
  for_each = { for r in local.master_sg_ingress : "${r.proto}-${r.from}-${r.to}" => r }

  security_group_id            = aws_security_group.master.id
  ip_protocol                  = each.value.proto
  from_port                    = each.value.from
  to_port                      = each.value.to
  referenced_security_group_id = aws_security_group.master.id
  description                  = each.value.desc
}

resource "aws_vpc_security_group_ingress_rule" "master_from_worker" {
  for_each = { for r in local.master_sg_ingress : "${r.proto}-${r.from}-${r.to}" => r }

  security_group_id            = aws_security_group.master.id
  ip_protocol                  = each.value.proto
  from_port                    = each.value.from
  to_port                      = each.value.to
  referenced_security_group_id = aws_security_group.worker.id
  description                  = each.value.desc
}

resource "aws_vpc_security_group_egress_rule" "master_egress" {
  security_group_id = aws_security_group.master.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "worker_vpc" {
  for_each = { for r in local.worker_vpc_ingress : "${r.proto}-${r.from}-${r.to}" => r }

  security_group_id = aws_security_group.worker.id
  ip_protocol       = each.value.proto
  from_port         = each.value.from
  to_port           = each.value.to
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "worker_from_worker" {
  for_each = { for r in local.worker_sg_ingress : "${r.proto}-${r.from}-${r.to}" => r }

  security_group_id            = aws_security_group.worker.id
  ip_protocol                  = each.value.proto
  from_port                    = each.value.from
  to_port                      = each.value.to
  referenced_security_group_id = aws_security_group.worker.id
  description                  = each.value.desc
}

resource "aws_vpc_security_group_ingress_rule" "worker_from_master" {
  for_each = { for r in local.worker_sg_ingress : "${r.proto}-${r.from}-${r.to}" => r }

  security_group_id            = aws_security_group.worker.id
  ip_protocol                  = each.value.proto
  from_port                    = each.value.from
  to_port                      = each.value.to
  referenced_security_group_id = aws_security_group.master.id
  description                  = each.value.desc
}

resource "aws_vpc_security_group_egress_rule" "worker_egress" {
  security_group_id = aws_security_group.worker.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
