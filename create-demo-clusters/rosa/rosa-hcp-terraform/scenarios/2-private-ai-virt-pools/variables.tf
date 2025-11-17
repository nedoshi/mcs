# AWS Configuration
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones for subnets"
  type        = list(string)
}

# RHCS Configuration
variable "rhcs_token" {
  description = "RHCS API token from console.redhat.com/openshift/token"
  type        = string
  sensitive   = true
}

variable "rhcs_url" {
  description = "RHCS API URL (default: https://api.openshift.com)"
  type        = string
  default     = "https://api.openshift.com"
}

# Cluster Configuration
variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
}

variable "openshift_version" {
  description = "OpenShift version for the cluster"
  type        = string
  default     = "4.14"
}

variable "default_replicas" {
  description = "Number of default compute node replicas"
  type        = number
  default     = 3
}

variable "default_compute_machine_type" {
  description = "EC2 instance type for default compute nodes"
  type        = string
  default     = "m5.xlarge"
}

# VPC Configuration
variable "create_vpc" {
  description = "Whether to create a new VPC or use an existing one"
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "ID of existing VPC to use when create_vpc is false"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "Whether to use a single NAT gateway for all private subnets (cost optimization)"
  type        = bool
  default     = false
}

# Account Roles Configuration
variable "create_account_roles" {
  description = "Whether to create account roles (only needed once per AWS account)"
  type        = bool
  default     = false
}

variable "existing_account_role_prefix" {
  description = "Prefix of existing account roles when create_account_roles is false (e.g., 'rosa-account')"
  type        = string
  default     = ""
}

# AI Machine Pool Configuration
variable "ai_instance_type" {
  description = "EC2 instance type for AI/GPU nodes (e.g., p3.2xlarge, p4d.24xlarge, g5.xlarge)"
  type        = string
  default     = "g5.xlarge"
}

variable "ai_pool_replicas" {
  description = "Number of replicas in AI machine pool"
  type        = number
  default     = 1
}

variable "enable_ai_autoscaling" {
  description = "Enable autoscaling for AI machine pool"
  type        = bool
  default     = false
}

variable "ai_pool_min_replicas" {
  description = "Minimum replicas for AI machine pool autoscaling"
  type        = number
  default     = 1
}

variable "ai_pool_max_replicas" {
  description = "Maximum replicas for AI machine pool autoscaling"
  type        = number
  default     = 10
}

variable "taint_ai_nodes" {
  description = "Whether to taint AI nodes to dedicate them to AI workloads"
  type        = bool
  default     = true
}

# Virtualization Machine Pool Configuration
variable "virt_instance_type" {
  description = "EC2 instance type for virtualization nodes (e.g., m5.metal, m5zn.metal, c5n.metal)"
  type        = string
  default     = "m5.metal"
}

variable "virt_pool_replicas" {
  description = "Number of replicas in virtualization machine pool"
  type        = number
  default     = 1
}

variable "enable_virt_autoscaling" {
  description = "Enable autoscaling for virtualization machine pool"
  type        = bool
  default     = false
}

variable "virt_pool_min_replicas" {
  description = "Minimum replicas for virtualization machine pool autoscaling"
  type        = number
  default     = 1
}

variable "virt_pool_max_replicas" {
  description = "Maximum replicas for virtualization machine pool autoscaling"
  type        = number
  default     = 10
}

variable "taint_virt_nodes" {
  description = "Whether to taint virtualization nodes to dedicate them to virtualization workloads"
  type        = bool
  default     = true
}

# High Memory Machine Pool Configuration
variable "create_highmem_pool" {
  description = "Whether to create a high-memory machine pool"
  type        = bool
  default     = false
}

variable "highmem_instance_type" {
  description = "EC2 instance type for high-memory nodes (e.g., r5.4xlarge, x1e.xlarge)"
  type        = string
  default     = "r5.4xlarge"
}

variable "highmem_pool_replicas" {
  description = "Number of replicas in high-memory machine pool"
  type        = number
  default     = 1
}

# Admin User Configuration
variable "create_admin_user" {
  description = "Whether to create an admin user for the cluster"
  type        = bool
  default     = false
}

# Bastion Configuration
variable "bastion_instance_type" {
  description = "EC2 instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "bastion_ssh_public_key" {
  description = "SSH public key for bastion host access"
  type        = string
}

variable "bastion_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Tags
variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  default     = "production"
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

