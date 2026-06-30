# ROSA HCP Demo Cluster 1 — us-east-1 (Virginia)
# Shared VPC mode: same account simulating cross-account for testing

cluster_name          = "demo1"
region                = "us-east-1"
openshift_version     = "4.21.0"
cluster_account_id    = "<CLUSTER_ACCOUNT_ID>"
shared_vpc_account_id = "<SHARED_VPC_ACCOUNT_ID>"
account_roles_prefix  = "demo1"
operator_roles_prefix = "demo1"
oidc_config_id        = ""  # Set from: rosa create oidc-config --mode auto --managed=false -y
vpc_cidr              = "10.220.228.0/24"
availability_zones    = ["us-east-1a", "us-east-1b", "us-east-1c"]
base_dns_domain       = "<BASE_DNS_DOMAIN>"
shared_vpc_role_arn   = "arn:aws:iam::<SHARED_VPC_ACCOUNT_ID>:role/ROSA-SharedVPC-TerraformRole"
