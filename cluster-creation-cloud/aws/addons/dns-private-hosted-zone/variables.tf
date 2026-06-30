variable "region" {
  description = "AWS region of the existing cluster and VPC."
  type        = string
}

variable "cluster_name" {
  description = "ROSA cluster name (used to discover the ingress NLB by tag)."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster runs (associated with the private hosted zone)."
  type        = string
}

variable "custom_domain" {
  description = "Private hosted zone name (e.g. apps.example.com)."
  type        = string
}

variable "tags" {
  description = "Tags applied to Route53 resources."
  type        = map(string)
  default     = {}
}
