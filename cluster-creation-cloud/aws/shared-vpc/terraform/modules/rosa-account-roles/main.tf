# ROSA HCP Account Roles — Data Source Lookups
#
# Prerequisites: Run these commands BEFORE terraform apply:
#
#   rosa create account-roles --prefix <PREFIX> --hosted-cp --mode auto -y
#   rosa create oidc-config --mode auto --managed=false -y
#
# This module looks up the roles that `rosa` created.
# The oidc_config_id is passed through as a variable (from rosa CLI output).

data "aws_iam_role" "installer" {
  name = "${var.account_roles_prefix}-HCP-ROSA-Installer-Role"
}

data "aws_iam_role" "support" {
  name = "${var.account_roles_prefix}-HCP-ROSA-Support-Role"
}

data "aws_iam_role" "worker" {
  name = "${var.account_roles_prefix}-HCP-ROSA-Worker-Role"
}
