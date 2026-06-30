# Create account IAM resources first (required before creating the cluster)
module "account_iam_resources" {
  source              = "terraform-redhat/rosa-hcp/rhcs//modules/account-iam-resources"
  version             = "1.6.3"
  account_role_prefix = local.cluster_name
}

# Attach ECR read-only policy to worker role (required for zero egress)
resource "aws_iam_role_policy_attachment" "attach-ecr-policy" {
  role       = "${local.cluster_name}-HCP-ROSA-Worker-Role"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  depends_on = [module.account_iam_resources]
}

# Create ROSA HCP cluster with zero egress configuration
module "rosa-hcp" {
  source                 = "terraform-redhat/rosa-hcp/rhcs"
  version                = "1.6.3"
  cluster_name           = local.cluster_name
  openshift_version      = var.openshift_version
  account_role_prefix    = local.cluster_name
  operator_role_prefix   = local.cluster_name
  replicas               = local.worker_node_replicas
  aws_availability_zones = local.region_azs
  create_oidc            = true
  private                = var.private_cluster
  aws_subnet_ids         = var.private_cluster ? module.vpc.private_subnets : concat(module.vpc.public_subnets, module.vpc.private_subnets)
  create_account_roles   = false
  create_operator_roles  = true
  
  # Zero egress configuration
  properties = {
    rosa_creator_arn = data.aws_caller_identity.current.arn
    zero_egress      = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.attach-ecr-policy,
    module.account_iam_resources,
    aws_vpc_endpoint.sts,
    aws_vpc_endpoint.ecr_api,
    aws_vpc_endpoint.ecr_dkr,
    aws_vpc_endpoint.s3
  ]
}

