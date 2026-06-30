output "operator_role_arns" {
  description = "Map of operator role logical names to their ARNs"
  value = {
    capa_controller_manager         = data.aws_iam_role.capa_controller_manager.arn
    control_plane_operator          = data.aws_iam_role.control_plane_operator.arn
    kms_provider                    = data.aws_iam_role.kms_provider.arn
    kube_controller_manager         = data.aws_iam_role.kube_controller_manager.arn
    cloud_network_config_controller = data.aws_iam_role.cloud_network_config_controller.arn
    ebs_csi_driver                  = data.aws_iam_role.ebs_csi_driver.arn
    image_registry                  = data.aws_iam_role.image_registry.arn
    ingress_operator                = data.aws_iam_role.ingress_operator.arn
  }
}
