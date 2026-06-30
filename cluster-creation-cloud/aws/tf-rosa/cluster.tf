data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "rhcs_versions" "hcp_versions" {
  search = "enabled='t' and rosa_enabled='t' and hosted_control_plane_enabled = 't' and channel_group='stable'"
  order  = "id"
}

locals {
  private_subnet_ids = module.network.private_subnets

  subnet_ids = var.private ? local.private_subnet_ids : concat(local.private_subnet_ids, module.network.public_subnets)

  autoscaling  = var.max_replicas != null
  hcp_replicas = var.replicas == null ? (var.multi_az ? local.network_az_count : 2) : var.replicas

  hcp_machine_pools = var.multi_az ? [
    for idx in range(local.network_az_count) : "workers-${idx}"
  ] : ["workers"]

  hcp_version = var.ocp_version != null ? var.ocp_version : element(data.rhcs_versions.hcp_versions.items, length(data.rhcs_versions.hcp_versions.items) - 1).name

  cluster_properties = merge(
    { rosa_creator_arn = data.aws_caller_identity.current.arn },
    var.zero_egress ? { zero_egress = true } : {}
  )
}

resource "rhcs_cluster_rosa_hcp" "rosa" {
  name = var.cluster_name

  cloud_region           = var.region
  aws_account_id         = data.aws_caller_identity.current.account_id
  aws_billing_account_id = var.aws_billing_account_id != null ? var.aws_billing_account_id : data.aws_caller_identity.current.account_id
  tags                   = local.tags

  replicas                 = local.hcp_replicas
  ec2_metadata_http_tokens = "required"

  private            = var.private
  aws_subnet_ids     = local.subnet_ids
  machine_cidr       = var.vpc_cidr
  availability_zones = module.network.availability_zones
  pod_cidr           = var.pod_cidr
  service_cidr       = var.service_cidr

  compute_machine_type = var.compute_machine_type
  properties           = local.cluster_properties
  version              = local.hcp_version
  sts                  = local.sts_roles

  kms_key_arn = local.cluster_kms_key_arn

  external_auth_providers_enabled = var.external_auth_providers_enabled

  disable_waiting_in_destroy          = false
  wait_for_create_complete            = true
  wait_for_std_compute_nodes_complete = true

  lifecycle {
    precondition {
      condition     = local.hcp_replicas % local.network_az_count == 0
      error_message = "HCP clusters require that 'replicas' (${local.hcp_replicas}) be a multiple of the number of private subnets (${local.network_az_count})."
    }
  }

  depends_on = [module.network, module.account_roles_hcp, module.operator_roles_hcp]
}

data "rhcs_hcp_machine_pool" "default" {
  count = length(local.hcp_machine_pools)

  cluster = rhcs_cluster_rosa_hcp.rosa.id
  name    = local.hcp_machine_pools[count.index]
}

resource "rhcs_hcp_machine_pool" "default" {
  count = length(data.rhcs_hcp_machine_pool.default)

  name        = data.rhcs_hcp_machine_pool.default[count.index].name
  cluster     = rhcs_cluster_rosa_hcp.rosa.id
  subnet_id   = data.rhcs_hcp_machine_pool.default[count.index].subnet_id
  auto_repair = data.rhcs_hcp_machine_pool.default[count.index].auto_repair

  replicas = local.autoscaling ? null : data.rhcs_hcp_machine_pool.default[count.index].replicas
  autoscaling = {
    enabled      = local.autoscaling
    min_replicas = local.autoscaling ? local.hcp_replicas : null
    max_replicas = local.autoscaling ? var.max_replicas : null
  }

  aws_node_pool = {
    instance_type            = data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type
    ec2_metadata_http_tokens = data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.ec2_metadata_http_tokens
    tags                     = local.tags
  }

  lifecycle {
    precondition {
      condition     = var.multi_az ? true : (local.hcp_replicas >= 2)
      error_message = "must have a minimum of 2 'replicas' for single az use cases."
    }

    precondition {
      condition     = local.autoscaling ? var.max_replicas >= local.hcp_replicas : true
      error_message = "'max_replicas' must be greater than 'replicas'."
    }
  }
}

locals {
  cluster_id                = rhcs_cluster_rosa_hcp.rosa.id
  cluster_name              = rhcs_cluster_rosa_hcp.rosa.name
  cluster_domain            = rhcs_cluster_rosa_hcp.rosa.domain
  cluster_oidc_config_id    = rhcs_cluster_rosa_hcp.rosa.sts.oidc_config_id
  cluster_oidc_endpoint_url = rhcs_cluster_rosa_hcp.rosa.sts.oidc_endpoint_url
  cluster_api_url           = rhcs_cluster_rosa_hcp.rosa.api_url
  cluster_console_url       = rhcs_cluster_rosa_hcp.rosa.console_url
}
