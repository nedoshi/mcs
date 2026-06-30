locals {
  tags = merge(
    {
      "openshift-cluster" = var.cluster_name
    },
    var.tags,
  )

  infrastructure_name = coalesce(
    var.infrastructure_name,
    "${var.cluster_name}-${random_id.infrastructure.hex}",
  )

  cluster_domain = "${var.cluster_name}.${var.base_domain}"

  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(
    data.aws_availability_zones.available.names,
    0,
    var.az_count,
  )

  private_subnet_cidrs = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [
    for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 10)
  ]

  public_subnet_cidrs = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : [
    for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 20)
  ]
}

resource "random_id" "infrastructure" {
  byte_length = 2
}

data "aws_availability_zones" "available" {
  state = "available"
}
