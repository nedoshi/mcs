# ROSA HCP Demo Cluster 2 — us-east-2 (Ohio)

cluster_name          = "demo2"
region                = "us-east-2"
openshift_version     = "4.18.32"
cluster_account_id    = "<CLUSTER_ACCOUNT_ID>"
shared_vpc_account_id = "<SHARED_VPC_ACCOUNT_ID>"
account_roles_prefix  = "demo2"
operator_roles_prefix = "demo2"
oidc_config_id        = ""  # Set from: rosa create oidc-config --mode auto --managed=false -y
vpc_cidr              = "10.221.0.0/24"
availability_zones    = ["us-east-2a", "us-east-2b", "us-east-2c"]
shared_vpc_role_arn   = "arn:aws:iam::<SHARED_VPC_ACCOUNT_ID>:role/ROSA-SharedVPC-TerraformRole"
