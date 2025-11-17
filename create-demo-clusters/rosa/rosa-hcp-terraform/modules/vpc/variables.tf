# modules/vpc/variables.tf

variable "cluster_name" {
  description = "Name of the ROSA cluster (used for resource naming)"
  type        = string
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
}

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

variable "availability_zones" {
  description = "List of availability zones for subnets"
  type        = list(string)
}

variable "create_public_subnets" {
  description = "Whether to create public subnets (required for NAT gateways and bastion hosts)"
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Whether to use a single NAT gateway for all private subnets (cost optimization) or one per AZ (high availability)"
  type        = bool
  default     = false
}

variable "zero_egress" {
  description = "Whether to configure zero egress (no NAT gateway routes for private subnets)"
  type        = bool
  default     = false
}

variable "create_vpc_endpoints" {
  description = "Whether to create VPC endpoints for zero egress scenarios"
  type        = bool
  default     = false
}

variable "vpc_interface_endpoints" {
  description = "List of VPC interface endpoint service names (e.g., ['ec2', 'ecr.api', 'ecr.dkr', 's3'])"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}