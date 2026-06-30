# ROSA HCP KMS Module - Variables

variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID where the ROSA cluster is deployed"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the KMS key (must match cluster region)"
  type        = string
}

variable "account_roles_prefix" {
  description = "Prefix used when creating ROSA account roles"
  type        = string
}

variable "installer_role_arn" {
  description = "ARN of the HCP ROSA Installer role"
  type        = string
}

variable "support_role_arn" {
  description = "ARN of the HCP ROSA Support role"
  type        = string
}

variable "operator_role_arns" {
  description = "ARNs of operator roles that need KMS access"
  type = object({
    capa_controller_manager = string
    control_plane_operator   = string
    kms_provider            = string
    kube_controller_manager = string
    ebs_csi_driver          = string
  })
}

variable "enable_key_rotation" {
  description = "Enable automatic annual key rotation"
  type        = bool
  default     = true
}

variable "deletion_window_in_days" {
  description = "Waiting period before key deletion (7-30 days)"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags for the KMS key"
  type        = map(string)
  default     = {}
}
