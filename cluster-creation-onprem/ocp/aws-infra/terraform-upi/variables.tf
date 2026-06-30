variable "region" {
  description = "AWS region for the cluster."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "OpenShift cluster name (DNS label, max 27 chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,26}$", var.cluster_name))
    error_message = "cluster_name must start with a letter and be at most 27 characters."
  }
}

variable "infrastructure_name" {
  description = "Unique infrastructure ID prefixed on AWS resources. Auto-generated when null."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.infrastructure_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,26}$", var.infrastructure_name))
    error_message = "infrastructure_name must start with a letter and be at most 27 characters."
  }
}

variable "base_domain" {
  description = "Base DNS domain (e.g. example.com). Must have a Route53 public hosted zone when create_public_dns_records is true."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "az_count" {
  description = "Number of availability zones (1-3). Use 3 for HA."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "az_count must be between 1 and 3."
  }
}

variable "availability_zones" {
  description = "Explicit AZ names. When empty, the first az_count AZs in the region are used."
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (one per AZ). Auto-calculated from vpc_cidr when empty."
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one per AZ). Auto-calculated from vpc_cidr when empty."
  type        = list(string)
  default     = []
}

variable "public_hosted_zone_id" {
  description = "Route53 public hosted zone ID for api/apps DNS. Required when create_public_dns_records is true."
  type        = string
  default     = null
  nullable    = true
}

variable "create_public_dns_records" {
  description = "Create api.<cluster>.<domain> in the public Route53 zone (requires public_hosted_zone_id)."
  type        = bool
  default     = true
}

variable "create_vpc_endpoints" {
  description = "Create S3 gateway and EC2 interface VPC endpoints in private subnets."
  type        = bool
  default     = true
}

variable "rhcos_ami" {
  description = "RHCOS AMI ID for the region. Looked up automatically when null."
  type        = string
  default     = null
  nullable    = true
}

variable "enable_cluster_install" {
  description = "Run openshift-install, launch bootstrap/control-plane nodes, and attach NLB targets."
  type        = bool
  default     = false
}

variable "openshift_pull_secret_path" {
  description = "Path to openshift pull secret JSON (required when enable_cluster_install is true)."
  type        = string
  default     = "./openshift_pull_secret.json"
}

variable "openshift_installer_url" {
  description = "Base URL to download openshift-install and oc client."
  type        = string
  default     = "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest"
}

variable "ssh_public_key" {
  description = "SSH public key for cluster nodes. Generated when null and enable_cluster_install is true."
  type        = string
  default     = null
  nullable    = true
}

variable "network_type" {
  description = "OpenShift network plugin (OVNKubernetes recommended for OCP 4.12+)."
  type        = string
  default     = "OVNKubernetes"
}

variable "cluster_network_cidr" {
  description = "Pod network CIDR."
  type        = string
  default     = "10.128.0.0/14"
}

variable "cluster_network_host_prefix" {
  description = "Pod network host prefix."
  type        = number
  default     = 23
}

variable "service_network_cidr" {
  description = "Service network CIDR."
  type        = string
  default     = "172.30.0.0/16"
}

variable "control_plane" {
  description = "Control plane node configuration."
  type = object({
    count        = optional(number, 3)
    instance_type = optional(string, "m6i.xlarge")
    disk_gb      = optional(number, 120)
  })
  default = {}
}

variable "bootstrap" {
  description = "Bootstrap node configuration."
  type = object({
    instance_type = optional(string, "m6i.xlarge")
  })
  default = {}
}

variable "worker" {
  description = "Worker configuration when use_worker_machinesets is true."
  type = object({
    count        = optional(number, 3)
    instance_type = optional(string, "m6i.large")
    disk_gb      = optional(number, 120)
  })
  default = {}
}

variable "use_worker_machinesets" {
  description = "Generate worker MachineSet manifests for the Machine API (recommended). When false, no workers are provisioned — add MachineSets manually post-install."
  type        = bool
  default     = true
}

variable "install_output_dir" {
  description = "Directory for openshift-install assets (install-config, ignition, auth)."
  type        = string
  default     = "./output"
}
