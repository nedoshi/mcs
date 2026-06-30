variable "cluster_name" {
  description = "Name of the ROSA HCP cluster (max 15 characters)"
  type        = string
}

variable "region" {
  description = "AWS region for the cluster"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID where the ROSA cluster is deployed"
  type        = string
}

variable "openshift_version" {
  description = "OpenShift version (e.g. 4.18.32)"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the cluster"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones for the cluster"
  type        = list(string)
}

variable "machine_cidr" {
  description = "CIDR block for the machine network"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for cluster encryption"
  type        = string
}

variable "etcd_kms_key_arn" {
  description = "ARN of the KMS key for etcd encryption"
  type        = string
}

variable "oidc_config_id" {
  description = "OIDC configuration ID"
  type        = string
}

variable "operator_roles_prefix" {
  description = "Prefix for operator roles"
  type        = string
}

variable "installer_role_arn" {
  description = "ARN of the installer account role"
  type        = string
}

variable "support_role_arn" {
  description = "ARN of the support account role"
  type        = string
}

variable "worker_role_arn" {
  description = "ARN of the worker account role"
  type        = string
}

variable "base_dns_domain" {
  description = "Base DNS domain for the cluster (e.g. rosa.example.com)"
  type        = string
  default     = ""
}

variable "hcp_internal_hz_id" {
  description = "Route53 hosted zone ID for HCP internal (hypershift.local)"
  type        = string
  default     = null
}

variable "ingress_hz_id" {
  description = "Route53 hosted zone ID for ingress (*.apps)"
  type        = string
  default     = null
}

variable "vpc_endpoint_role_arn" {
  description = "ARN of the VPC endpoint IAM role in shared VPC account"
  type        = string
  default     = null
}

variable "route53_role_arn" {
  description = "ARN of the Route53 IAM role in shared VPC account"
  type        = string
  default     = null
}

variable "replicas" {
  description = "Number of compute node replicas"
  type        = number
  default     = 3
}

variable "external_auth_providers_enabled" {
  description = "Enable external authentication providers for GitOps-managed OAuth"
  type        = bool
  default     = true
}
