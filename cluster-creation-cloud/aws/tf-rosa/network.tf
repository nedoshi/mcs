locals {
  network_az_count = var.multi_az ? 3 : 1
}

module "network" {
  source  = "terraform-redhat/rosa-hcp/rhcs//modules/vpc"
  version = "~> 1.7"

  name_prefix              = var.cluster_name
  vpc_cidr                 = var.vpc_cidr
  availability_zones_count = local.network_az_count

  tags = local.tags
}
