# Shared VPC Module - Variables

variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "cluster_account_id" {
  description = "AWS account ID of the cluster (for RAM share)"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones for subnets"
  type        = list(string)
}

variable "installer_role_arn" {
  description = "ARN of the HCP ROSA Installer Role (trusted to assume Route53/VPC endpoint roles)"
  type        = string
}

variable "base_dns_domain" {
  description = "Base DNS domain reserved via 'rosa create dns-domain --hosted-cp' (e.g. xxxx.p3.openshiftapps.com)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
