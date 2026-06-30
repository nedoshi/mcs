#
# IAM account roles (HCP) - optional: create in-repo or use existing shared roles
#

module "account_roles_hcp" {
  count = var.create_account_roles ? 1 : 0

  source  = "terraform-redhat/rosa-hcp/rhcs//modules/account-iam-resources"
  version = "~> 1.7"

  account_role_prefix = var.account_role_prefix != "" ? var.account_role_prefix : var.cluster_name
  tags                = local.tags
}

#
# IAM operator roles and OIDC provider (HCP, per-cluster)
#

module "oidc_config_and_provider_hcp" {
  source  = "terraform-redhat/rosa-hcp/rhcs//modules/oidc-config-and-provider"
  version = "~> 1.7"

  managed = true
  tags    = local.tags
}

module "operator_roles_hcp" {
  source  = "terraform-redhat/rosa-hcp/rhcs//modules/operator-roles"
  version = "~> 1.7"

  oidc_endpoint_url    = module.oidc_config_and_provider_hcp.oidc_endpoint_url
  operator_role_prefix = var.cluster_name
  tags                 = local.tags
}

# When using existing shared roles, all three ARNs must be provided.
check "shared_account_roles_require_arns" {
  assert {
    condition     = var.create_account_roles || (var.installer_role_arn != null && var.support_role_arn != null && var.worker_role_arn != null)
    error_message = "When create_account_roles is false, installer_role_arn, support_role_arn, and worker_role_arn must all be set."
  }
}

#
# STS role block passed into cluster creation
#
locals {
  # When creating account roles, use cluster name as prefix (roles are per-cluster name).
  # When using existing shared roles, ARNs come from variables.
  account_role_prefix_for_arn = var.account_role_prefix != "" ? var.account_role_prefix : var.cluster_name
  installer_role_arn          = var.create_account_roles ? "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.account_role_prefix_for_arn}-HCP-ROSA-Installer-Role" : var.installer_role_arn
  support_role_arn            = var.create_account_roles ? "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.account_role_prefix_for_arn}-HCP-ROSA-Support-Role" : var.support_role_arn
  worker_role_arn             = var.create_account_roles ? "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.account_role_prefix_for_arn}-HCP-ROSA-Worker-Role" : var.worker_role_arn

  sts_roles = {
    role_arn         = local.installer_role_arn
    support_role_arn = local.support_role_arn
    instance_iam_roles = {
      master_role_arn = null
      worker_role_arn = local.worker_role_arn
    },
    operator_role_prefix = var.cluster_name
    oidc_config_id       = module.oidc_config_and_provider_hcp.oidc_config_id
    oidc_endpoint_url    = module.oidc_config_and_provider_hcp.oidc_endpoint_url
  }
}
