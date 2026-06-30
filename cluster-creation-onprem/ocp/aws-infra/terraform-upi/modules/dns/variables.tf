variable "cluster_name" {
  type = string
}

variable "base_domain" {
  type = string
}

variable "cluster_domain" {
  type    = string
  default = null
}

variable "infrastructure_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "internal_api_lb_dns_name" {
  type = string
}

variable "internal_api_lb_zone_id" {
  type = string
}

variable "external_api_lb_dns_name" {
  type = string
}

variable "external_api_lb_zone_id" {
  type = string
}

variable "public_hosted_zone_id" {
  type    = string
  default = null
  nullable = true
}

variable "create_public_dns_records" {
  type = bool
}

variable "tags" {
  type = map(string)
}

locals {
  cluster_domain = coalesce(var.cluster_domain, "${var.cluster_name}.${var.base_domain}")
}
