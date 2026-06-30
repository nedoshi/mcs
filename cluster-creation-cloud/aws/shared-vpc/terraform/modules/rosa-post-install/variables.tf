# ROSA HCP Post-Install Module - Variables

variable "cluster_name" {
  description = "ROSA HCP cluster name"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key (used by GitOps StorageClass values)"
  type        = string
}
