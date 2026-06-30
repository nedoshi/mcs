variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "base_domain" {
  type = string
}

variable "infrastructure_name" {
  type = string
}

variable "cluster_domain" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "availability_zones" {
  type = list(string)
}

variable "rhcos_ami" {
  type = string
}

variable "master_security_group_id" {
  type = string
}

variable "worker_security_group_id" {
  type = string
}

variable "master_instance_profile" {
  type = string
}

variable "worker_instance_profile" {
  type = string
}

variable "bootstrap_instance_profile" {
  type = string
}

variable "internal_api_tg_arn" {
  type = string
}

variable "internal_service_tg_arn" {
  type = string
}

variable "external_api_tg_arn" {
  type = string
}

variable "private_hosted_zone_id" {
  type = string
}

variable "openshift_pull_secret_path" {
  type = string
}

variable "openshift_installer_url" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "network_type" {
  type = string
}

variable "cluster_network_cidr" {
  type = string
}

variable "cluster_network_host_prefix" {
  type = number
}

variable "service_network_cidr" {
  type = string
}

variable "control_plane" {
  type = object({
    count         = optional(number, 3)
    instance_type = optional(string, "m6i.xlarge")
    disk_gb       = optional(number, 120)
  })
}

variable "bootstrap" {
  type = object({
    instance_type = optional(string, "m6i.xlarge")
  })
}

variable "worker" {
  type = object({
    count         = optional(number, 3)
    instance_type = optional(string, "m6i.large")
    disk_gb       = optional(number, 120)
  })
}

variable "use_worker_machinesets" {
  type = bool
}

variable "install_output_dir" {
  type = string
}

variable "tags" {
  type = map(string)
}
