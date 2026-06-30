# ROSA HCP Cluster Module
# Creates ROSA with Hosted Control Plane using RHCS provider
# Supports shared VPC deployment with customer-managed KMS

data "aws_caller_identity" "current" {}

resource "rhcs_cluster_rosa_hcp" "main" {
  name           = var.cluster_name
  cloud_region   = var.region
  aws_account_id = var.aws_account_id
  version        = var.openshift_version

  properties = {
    rosa_creator_arn = data.aws_caller_identity.current.arn
  }

  aws_billing_account_id = var.aws_account_id
  aws_subnet_ids         = var.subnet_ids
  availability_zones     = var.availability_zones
  machine_cidr           = var.machine_cidr

  sts = {
    role_arn         = var.installer_role_arn
    support_role_arn = var.support_role_arn
    instance_iam_roles = {
      worker_role_arn = var.worker_role_arn
    }
    operator_role_prefix = var.operator_roles_prefix
    oidc_config_id       = var.oidc_config_id
  }

  etcd_encryption     = true
  kms_key_arn         = var.kms_key_arn
  etcd_kms_key_arn    = var.etcd_kms_key_arn

  private  = true
  replicas = var.replicas

  external_auth_providers_enabled = var.external_auth_providers_enabled

  base_dns_domain = var.base_dns_domain

  shared_vpc = var.hcp_internal_hz_id != null ? {
    ingress_private_hosted_zone_id                 = var.ingress_hz_id
    internal_communication_private_hosted_zone_id  = var.hcp_internal_hz_id
    route53_role_arn                               = var.route53_role_arn
    vpce_role_arn                                  = var.vpc_endpoint_role_arn
  } : null

  aws_additional_allowed_principals = var.hcp_internal_hz_id != null ? compact([
    var.route53_role_arn,
    var.vpc_endpoint_role_arn,
  ]) : null

  tags = {
    "red-hat-managed" = "true"
    "ManagedBy"       = "terraform"
  }

  wait_for_create_complete = true
}
