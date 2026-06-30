variable "token" {
  type        = string
  description = "OCM token used to authenticate against the OpenShift Cluster Manager API. See https://console.redhat.com/openshift/token/rosa/show to access your token."
  sensitive   = true
}

variable "region" {
  description = "The AWS region to provision a ROSA HCP cluster and required components into."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "The name of the ROSA HCP cluster to create. If not provided, a random name will be generated."
  type        = string
  default     = null
}

variable "openshift_version" {
  type        = string
  default     = "4.19.4"
  description = "Desired version of OpenShift for the cluster, for example '4.19.4'. If version is greater than the currently running version, an upgrade will be scheduled."
}

variable "multi_az" {
  type        = bool
  description = "Multi AZ Cluster for High Availability. For zero egress, this should typically be true."
  default     = true
}

variable "private_cluster" {
  type        = bool
  description = "Do you want this cluster to be private? For zero egress, this should be true."
  default     = true
}

variable "machine_type" {
  description = "The AWS instance type used for your default worker pool"
  type        = string
  default     = "m5.xlarge"
}

variable "worker_node_replicas" {
  default     = null
  description = "Number of worker nodes to provision. Single zone clusters need at least 2 nodes, multizone clusters need at least 3 nodes. If null, defaults to 3 for multi-AZ or 2 for single-AZ."
  type        = number
  nullable    = true
}

variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block to use for the VPC"
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "The CIDR blocks to use for the private subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "The CIDR blocks to use for the public subnets"
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "path" {
  description = "(Optional) The arn path for the account/operator roles as well as their policies."
  type        = string
  default     = null
}

variable "additional_tags" {
  default = {
    Terraform   = "true"
    Environment = "dev"
  }
  description = "Additional AWS resource tags"
  type        = map(string)
}

variable "autoscaling_enabled" {
  description = "Enables autoscaling. This variable requires you to set a maximum and minimum replicas range using the `max_replicas` and `min_replicas` variables."
  type        = string
  default     = "false"
}

variable "min_replicas" {
  description = "The minimum number of replicas for autoscaling."
  type        = number
  default     = 3
}

variable "max_replicas" {
  description = "The maximum number of replicas not exceeded by the autoscaling functionality."
  type        = number
  default     = 3
}

variable "bastion_public_ssh_key" {
  description = <<EOF
  Location to an SSH public key file on the local system which is used to provide connectivity to the bastion host
  when the 'private' variable is set to 'true'.
  EOF
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "bastion_public_ip" {
  description = "Should the Bastion have a public ip?"
  type        = bool
  default     = false
}

variable "proxy" {
  default     = null
  description = "cluster-wide HTTP or HTTPS proxy settings"
  type = object({
    http_proxy              = string           # required  http proxy
    https_proxy             = string           # required  https proxy
    additional_trust_bundle = optional(string) # a string contains contains a PEM-encoded X.509 certificate bundle that will be added to the nodes' trusted certificate store.
    no_proxy                = optional(string) # no proxy
  })
}

variable "vpc_name" {
  type        = string
  description = "VPC Name"
  default     = null
}

variable "single_nat_gateway" {
  type        = bool
  description = "Single NAT or per NAT for subnet (not used for zero egress, but kept for compatibility)"
  default     = false
}

variable "client_id" {
  type        = string
  description = "The client id for the RHCS provider (alternative to token)"
  default     = null
  sensitive   = true
}

variable "client_secret" {
  type        = string
  description = "The client secret for the RHCS provider (alternative to token)"
  default     = null
  sensitive   = true
}

