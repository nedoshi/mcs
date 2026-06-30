module "network" {
  source = "./modules/network"

  infrastructure_name  = local.infrastructure_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = local.availability_zones
  private_subnet_cidrs = local.private_subnet_cidrs
  public_subnet_cidrs  = local.public_subnet_cidrs
  create_vpc_endpoints = var.create_vpc_endpoints
  tags                 = local.tags
}

module "load_balancer" {
  source = "./modules/load_balancer"

  infrastructure_name = local.infrastructure_name
  vpc_id              = module.network.vpc_id
  private_subnet_ids  = module.network.private_subnet_ids
  public_subnet_ids   = module.network.public_subnet_ids
  tags                = local.tags
}

module "dns" {
  source = "./modules/dns"

  cluster_name                = var.cluster_name
  base_domain                 = var.base_domain
  infrastructure_name         = local.infrastructure_name
  vpc_id                      = module.network.vpc_id
  internal_api_lb_dns_name    = module.load_balancer.internal_api_lb_dns_name
  internal_api_lb_zone_id     = module.load_balancer.internal_api_lb_zone_id
  external_api_lb_dns_name    = module.load_balancer.external_api_lb_dns_name
  external_api_lb_zone_id     = module.load_balancer.external_api_lb_zone_id
  public_hosted_zone_id       = var.public_hosted_zone_id
  create_public_dns_records   = var.create_public_dns_records
  tags                        = local.tags
}

module "security" {
  source = "./modules/security"

  infrastructure_name = local.infrastructure_name
  vpc_id              = module.network.vpc_id
  vpc_cidr            = var.vpc_cidr
  tags                = local.tags
}

module "iam" {
  source = "./modules/iam"

  infrastructure_name = local.infrastructure_name
  tags                = local.tags
}

module "cluster" {
  count  = var.enable_cluster_install ? 1 : 0
  source = "./modules/cluster"

  region                      = var.region
  cluster_name                = var.cluster_name
  base_domain                 = var.base_domain
  infrastructure_name         = local.infrastructure_name
  cluster_domain              = local.cluster_domain
  vpc_id                      = module.network.vpc_id
  vpc_cidr                    = var.vpc_cidr
  private_subnet_ids          = module.network.private_subnet_ids
  availability_zones          = local.availability_zones
  rhcos_ami                   = coalesce(var.rhcos_ami, data.aws_ami.rhcos[0].id)
  master_security_group_id    = module.security.master_security_group_id
  worker_security_group_id    = module.security.worker_security_group_id
  bootstrap_instance_profile  = module.iam.bootstrap_instance_profile_name
  master_instance_profile     = module.iam.master_instance_profile_name
  worker_instance_profile     = module.iam.worker_instance_profile_name
  internal_api_tg_arn         = module.load_balancer.internal_api_target_group_arn
  internal_service_tg_arn     = module.load_balancer.internal_service_target_group_arn
  external_api_tg_arn         = module.load_balancer.external_api_target_group_arn
  private_hosted_zone_id        = module.dns.private_hosted_zone_id
  openshift_pull_secret_path  = var.openshift_pull_secret_path
  openshift_installer_url     = var.openshift_installer_url
  ssh_public_key              = coalesce(var.ssh_public_key, tls_private_key.install[0].public_key_openssh)
  network_type                = var.network_type
  cluster_network_cidr        = var.cluster_network_cidr
  cluster_network_host_prefix = var.cluster_network_host_prefix
  service_network_cidr        = var.service_network_cidr
  control_plane               = var.control_plane
  bootstrap                   = var.bootstrap
  worker                      = var.worker
  use_worker_machinesets      = var.use_worker_machinesets
  install_output_dir          = var.install_output_dir
  tags                        = local.tags
}

data "aws_ami" "rhcos" {
  count = var.rhcos_ami == null ? 1 : 0

  most_recent = true
  owners      = ["704266488367"]

  filter {
    name   = "name"
    values = ["rhcos-hvm-*-x86_64-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "tls_private_key" "install" {
  count = var.enable_cluster_install && var.ssh_public_key == null ? 1 : 0

  algorithm = "ED25519"
}
