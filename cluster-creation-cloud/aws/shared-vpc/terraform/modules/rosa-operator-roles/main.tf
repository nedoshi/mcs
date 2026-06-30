# ROSA HCP Operator Roles — Data Source Lookups
#
# Prerequisites: Run these commands BEFORE terraform apply:
#
#   rosa create operator-roles --prefix <PREFIX> --hosted-cp \
#     --oidc-config-id <OIDC_CONFIG_ID> --installer-role-arn <INSTALLER_ROLE_ARN> \
#     --mode auto -y
#
# This module looks up the 8 operator roles that `rosa` created.

data "aws_iam_role" "capa_controller_manager" {
  name = "${var.operator_roles_prefix}-kube-system-capa-controller-manager"
}

data "aws_iam_role" "control_plane_operator" {
  name = "${var.operator_roles_prefix}-kube-system-control-plane-operator"
}

data "aws_iam_role" "kms_provider" {
  name = "${var.operator_roles_prefix}-kube-system-kms-provider"
}

data "aws_iam_role" "kube_controller_manager" {
  name = "${var.operator_roles_prefix}-kube-system-kube-controller-manager"
}

data "aws_iam_role" "cloud_network_config_controller" {
  name = "${var.operator_roles_prefix}-openshift-cloud-network-config-controller-cloud-credentials"
}

data "aws_iam_role" "ebs_csi_driver" {
  name = "${var.operator_roles_prefix}-openshift-cluster-csi-drivers-ebs-cloud-credentials"
}

data "aws_iam_role" "image_registry" {
  name = "${var.operator_roles_prefix}-openshift-image-registry-installer-cloud-credentials"
}

data "aws_iam_role" "ingress_operator" {
  name = "${var.operator_roles_prefix}-openshift-ingress-operator-cloud-credentials"
}
