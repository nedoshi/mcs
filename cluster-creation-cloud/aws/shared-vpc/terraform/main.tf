# ROSA HCP Cluster Automation - Root Module
# Orchestrates shared VPC -> account roles -> operator roles -> KMS -> cluster

locals {
  operator_role_arns = module.rosa_operator_roles.operator_role_arns
  is_shared_vpc      = var.shared_vpc_role_arn != ""
}

# 1. VPC infrastructure — always creates VPC, subnets, NAT, hosted zones, IAM roles
module "shared_vpc" {
  source = "./modules/shared-vpc"

  providers = {
    aws = aws.shared_vpc_account
  }

  cluster_name       = var.cluster_name
  region             = var.region
  vpc_cidr           = var.vpc_cidr
  cluster_account_id = var.cluster_account_id
  installer_role_arn = "arn:aws:iam::${var.cluster_account_id}:role/${var.account_roles_prefix}-HCP-ROSA-Installer-Role"
  base_dns_domain    = var.base_dns_domain
  availability_zones = var.availability_zones
  tags               = var.tags
}

# 2. Account roles — looks up roles created by `rosa create account-roles`
module "rosa_account_roles" {
  source = "./modules/rosa-account-roles"

  account_roles_prefix = var.account_roles_prefix
  oidc_config_id       = var.oidc_config_id
}

# 3. Operator roles — looks up roles created by `rosa create operator-roles`
module "rosa_operator_roles" {
  source = "./modules/rosa-operator-roles"

  operator_roles_prefix = var.operator_roles_prefix
}

# 4. KMS - depends on operator roles (needs operator role ARNs for policy)
module "rosa_kms" {
  source = "./modules/rosa-kms"

  cluster_name        = var.cluster_name
  aws_account_id      = var.cluster_account_id
  aws_region          = var.region
  account_roles_prefix = var.account_roles_prefix
  installer_role_arn  = module.rosa_account_roles.installer_role_arn
  support_role_arn    = module.rosa_account_roles.support_role_arn
  operator_role_arns = {
    capa_controller_manager         = local.operator_role_arns.capa_controller_manager
    control_plane_operator          = local.operator_role_arns.control_plane_operator
    kms_provider                     = local.operator_role_arns.kms_provider
    kube_controller_manager         = local.operator_role_arns.kube_controller_manager
    ebs_csi_driver                   = local.operator_role_arns.ebs_csi_driver
  }
  tags = var.tags

  depends_on = [module.rosa_operator_roles]
}

# 4b. Grant operator roles permission to assume shared VPC roles.
#     The operator roles are created by `rosa create operator-roles` but don't
#     include sts:AssumeRole for shared VPC roles — we must add it ourselves.
locals {
  shared_vpc_role_arns = local.is_shared_vpc ? [
    module.shared_vpc.vpc_endpoint_role_arn,
    module.shared_vpc.route53_role_arn
  ] : []

  operator_roles_needing_shared_vpc = local.is_shared_vpc ? {
    control_plane_operator = "${var.operator_roles_prefix}-kube-system-control-plane-operator"
    ingress_operator       = "${var.operator_roles_prefix}-openshift-ingress-operator-cloud-credentials"
  } : {}
}

resource "aws_iam_role_policy" "operator_assume_shared_vpc" {
  for_each = local.operator_roles_needing_shared_vpc

  name = "AssumeSharedVPCRoles"
  role = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = local.shared_vpc_role_arns
      }
    ]
  })
}

# 5. ROSA HCP Cluster - depends on shared VPC, account roles, operator roles, KMS
module "rosa_cluster" {
  source = "./modules/rosa-cluster"

  cluster_name          = var.cluster_name
  region                = var.region
  aws_account_id        = var.cluster_account_id
  openshift_version     = var.openshift_version
  availability_zones    = var.availability_zones
  subnet_ids            = module.shared_vpc.private_subnet_ids
  machine_cidr          = var.vpc_cidr
  kms_key_arn           = module.rosa_kms.kms_key_arn
  etcd_kms_key_arn      = module.rosa_kms.kms_key_arn
  oidc_config_id        = module.rosa_account_roles.oidc_config_id
  operator_roles_prefix = var.operator_roles_prefix
  installer_role_arn    = module.rosa_account_roles.installer_role_arn
  support_role_arn      = module.rosa_account_roles.support_role_arn
  worker_role_arn       = module.rosa_account_roles.worker_role_arn

  base_dns_domain       = local.is_shared_vpc ? var.base_dns_domain : ""
  hcp_internal_hz_id    = local.is_shared_vpc ? module.shared_vpc.hcp_internal_hosted_zone_id : null
  ingress_hz_id         = local.is_shared_vpc ? module.shared_vpc.ingress_hosted_zone_id : null
  vpc_endpoint_role_arn = local.is_shared_vpc ? module.shared_vpc.vpc_endpoint_role_arn : null
  route53_role_arn      = local.is_shared_vpc ? module.shared_vpc.route53_role_arn : null

  external_auth_providers_enabled = var.external_auth_providers_enabled

  depends_on = [
    module.shared_vpc,
    module.rosa_account_roles,
    module.rosa_operator_roles,
    module.rosa_kms,
    aws_iam_role_policy.operator_assume_shared_vpc
  ]
}

# 6. Entra ID OIDC Identity Provider — configures built-in OAuth with Entra IdP,
#    creates the admin group, binds it to cluster-admin, and disables kubeadmin.
locals {
  cluster_apps_domain = replace(module.rosa_cluster.cluster_console_url, "https://console-openshift-console.", "")
  oauth_callback_url  = "https://oauth.${local.cluster_apps_domain}/oauth2callback/${var.entra_idp_name}"
}

module "rosa_entra_idp" {
  count  = var.entra_idp_enabled ? 1 : 0
  source = "./modules/rosa-entra-idp"

  cluster_id   = module.rosa_cluster.cluster_id
  cluster_name = var.cluster_name

  oauth_callback_url = local.oauth_callback_url
  idp_name           = var.entra_idp_name

  admin_group_name              = var.entra_admin_group_name
  admin_group_member_object_ids = var.entra_admin_group_member_object_ids
  disable_kubeadmin             = var.disable_kubeadmin

  manage_entra_resources               = var.manage_entra_resources
  entra_existing_client_id             = var.entra_existing_client_id
  entra_existing_client_secret         = var.entra_existing_client_secret
  entra_existing_tenant_id             = var.entra_existing_tenant_id
  entra_existing_admin_group_object_id = var.entra_existing_admin_group_object_id

  depends_on = [module.rosa_cluster]
}

# 7. Post-install — demotes gp3-csi default StorageClass.
#    KMS-encrypted StorageClasses (gp3-csi-kms, gp3-csi-kms-retain) are created
#    by the GitOps rosa-platform-config Helm chart to avoid ownership conflicts.
module "rosa_post_install" {
  source = "./modules/rosa-post-install"

  cluster_name = var.cluster_name
  kms_key_arn  = module.rosa_kms.kms_key_arn

  depends_on = [module.rosa_cluster]
}
