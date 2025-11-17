# scenarios/4-zero-egress/variables.tf

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "create_vpc" {
  description = "Create new VPC"
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "Existing VPC ID"
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "openshift_version" {
  description = "OpenShift version"
  type        = string
  default     = "4.14"
}

variable "replicas" {
  description = "Worker node replicas"
  type        = number
  default     = 3
}

variable "compute_machine_type" {
  description = "Instance type"
  type        = string
  default     = "m5.xlarge"
}

variable "rhcs_token" {
  description = "RHCS token"
  type        = string
  sensitive   = true
}

variable "rhcs_url" {
  description = "RHCS API URL"
  type        = string
  default     = "https://api.openshift.com"
}

variable "create_account_roles" {
  description = "Create account roles"
  type        = bool
  default     = false
}

variable "existing_account_role_prefix" {
  description = "Existing account role prefix"
  type        = string
  default     = null
}

variable "create_admin_user" {
  description = "Create admin user"
  type        = bool
  default     = true
}

# VPC Endpoints
variable "vpc_interface_endpoints" {
  description = "VPC interface endpoints to create"
  type        = list(string)
  default = [
    "ec2",
    "ecr.api",
    "ecr.dkr",
    "elasticloadbalancing",
    "sts",
    "logs",
    "secretsmanager",
    "kms",
    "elasticfilesystem"
  ]
}

# ECR Configuration
variable "create_ecr_repository" {
  description = "Create private ECR repository"
  type        = bool
  default     = true
}

# HTTP Proxy Configuration
variable "enable_http_proxy" {
  description = "Enable HTTP proxy"
  type        = bool
  default     = false
}

variable "proxy_instance_type" {
  description = "Proxy instance type"
  type        = string
  default     = "t3.small"
}

variable "no_proxy" {
  description = "No proxy domains"
  type        = string
  default     = ".cluster.local,.svc,10.0.0.0/16,169.254.169.254"
}

# Bastion Configuration
variable "bastion_instance_type" {
  description = "Bastion instance type"
  type        = string
  default     = "t3.micro"
}

variable "bastion_ssh_public_key" {
  description = "Bastion SSH public key"
  type        = string
}

variable "bastion_allowed_cidr_blocks" {
  description = "Allowed CIDR blocks for bastion SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# S3 Configuration
variable "create_s3_bucket" {
  description = "Create S3 bucket for cluster data"
  type        = bool
  default     = true
}

# Tags
variable "environment" {
  description = "Environment"
  type        = string
  default     = "production"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}