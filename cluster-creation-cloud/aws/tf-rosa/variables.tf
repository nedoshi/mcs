variable "private" {
  description = "Set to true to provision a private cluster, which restricts access from the public internet."
  type        = bool
  default     = false
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

variable "aws_billing_account_id" {
  description = "The AWS billing account identifier where all resources are billed. If no information is provided, the data will be retrieved from the currently connected account."
  type        = string
  default     = null
}

variable "region" {
  description = "The AWS region to provision a ROSA cluster and required components into."
  type        = string
  default     = "us-east-1"
}

variable "multi_az" {
  description = <<EOF
  Configure the cluster to use a highly available, multi availability zone configuration.  It should be noted that use
  of the 'multi_az' variable may affect minimum requirements for 'replicas' and may restrict regions that do not have
  three availability zones.
  EOF
  type        = bool
  default     = false
}

variable "create_account_roles" {
  description = "Create HCP account roles in this Terraform run. Set to false to use existing shared account roles (e.g. created via 'rosa create account-roles --hosted-cp'). When false, installer_role_arn, support_role_arn, and worker_role_arn must be set."
  type        = bool
  default     = true
}

variable "account_role_prefix" {
  description = "Prefix for HCP account role names when create_account_roles is true. Defaults to cluster_name when empty. For shared roles (create_account_roles = false), use the prefix used when roles were created (e.g. ManagedOpenShift)."
  type        = string
  default     = ""
}

variable "installer_role_arn" {
  description = "ARN of the HCP ROSA Installer role. Required when create_account_roles is false."
  type        = string
  default     = null
}

variable "support_role_arn" {
  description = "ARN of the HCP ROSA Support role. Required when create_account_roles is false."
  type        = string
  default     = null
}

variable "worker_role_arn" {
  description = "ARN of the HCP ROSA Worker role. Required when create_account_roles is false."
  type        = string
  default     = null
}

variable "autoscaling" {
  description = <<EOF
  Enable autoscaling for the default machine pool, this is ignored for HCP clusters as autoscaling is not supported
  for Hosted Control Plane clusters at this time.

  WARN: this variable is deprecated.  Simply setting 'max_replicas' will enable autoscaling.  This will be removed
  in a future version of this module.
  EOF
  type        = bool
  nullable    = true
  default     = null
}

variable "replicas" {
  description = <<EOF
  Minimum number of replicas for the default machine pool.  If unset, a default value is configured based on the
  'multi_az' value.
  EOF
  type        = number
  nullable    = true
  default     = null
}

variable "max_replicas" {
  description = <<EOF
  Maximum number of replicas for the default machine pool.  If set, autoscaling is enabled.  If 
  For HCP, 'max_replicas' is per subnet: e.g. multi_az with 3 subnets and max_replicas = 3 gives up to 9 total replicas.
  EOF
  type        = number
  nullable    = true
  default     = null
}

variable "token" {
  description = <<EOF
  OCM token for the OpenShift Cluster Manager API. Optional; use instead of client_id/client_secret.
  Service account credentials are preferred for automation/CI. Do not set both token and client credentials.
  https://console.redhat.com/openshift/token/show
  EOF
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "client_id" {
  description = "RHCS API service account client ID (recommended). Required with client_secret when token is not set."
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "client_secret" {
  description = "RHCS API service account client secret (recommended). Required with client_id when token is not set."
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "cluster_name" {
  description = "The name of the cluster.  This is also used as a prefix to name related components."
  type        = string
}

variable "ocp_version" {
  description = <<EOF
  The version of OpenShift to use.  You can use the command 'rosa list versions' to see all available OpenShift
  versions available to ROSA.
  EOF
  type        = string
  # default     = "4.15.18"
  default = null
}

variable "vpc_cidr" {
  description = "The CIDR of the VPC that will be created."
  type        = string
  default     = "10.10.0.0/16"
}

variable "subnet_cidr_size" {
  description = <<EOF
  The CIDR size of each of the individual subnets that will be created.  Must be within range of the 'vpc_cidr'
  variable.
  EOF
  type        = number
  default     = 20
}

variable "pod_cidr" {
  description = "The internal pod CIDR network used for assigning IP addresses to pods."
  type        = string
  default     = "10.128.0.0/14"
}

variable "service_cidr" {
  description = "The internal service CIDR network used for assigning IP addresses to services."
  type        = string
  default     = "172.30.0.0/16"
}

variable "tags" {
  description = "Tags applied to all objects (also set as AWS provider default_tags). Merged with cost-center 468 and cloud-cost-notifier lifecycle tags expires-at (+2d) and delete-after (+3d) from cluster creation."
  type        = map(string)
  default     = {}
}

variable "admin_password" {
  description = <<EOF
  Password for the 'admin' user. IDP is not created if unspecified.  Password must be 14 characters or more, contain
  one uppercase letter and a symbol or number.
  EOF
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "developer_password" {
  description = <<EOF
  Password for the 'developer' user. IDP is not created if unspecified.  Password must be 14 characters or more, contain
  one uppercase letter and a symbol or number.
  EOF
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "compute_machine_type" {
  description = <<EOF
  The machine type used by the initial worker nodes, for example, m5.xlarge.  You can use the command 'rosa list
  instance-types' to see all available instance types available to ROSA.
  EOF
  type        = string
  default     = "m5.xlarge"
}

#------------------------------------------------------------------------------
# KMS (optional customer-managed key for cluster)
#------------------------------------------------------------------------------

variable "cluster_kms_mode" {
  description = "KMS mode for cluster (worker EBS, etc.): provider_managed (default), create (Terraform creates key), or existing (use cluster_kms_key_arn)."
  type        = string
  default     = "provider_managed"

  validation {
    condition     = contains(["provider_managed", "create", "existing"], var.cluster_kms_mode)
    error_message = "cluster_kms_mode must be provider_managed, create, or existing."
  }
}

variable "cluster_kms_key_arn" {
  description = "ARN of existing KMS key for cluster. Required when cluster_kms_mode is existing."
  type        = string
  default     = null
}

variable "etcd_encryption" {
  description = "Enable etcd encryption at rest. Only applies when using customer-managed KMS (cluster_kms_mode create or existing)."
  type        = bool
  default     = false
}

variable "external_auth_providers_enabled" {
  description = <<-EOT
    Enable external authentication providers at cluster creation (irreversible).
    Configure providers after install with: rosa create external-auth-provider
  EOT
  type        = bool
  default     = false
}

variable "create_break_glass_credential" {
  description = "Create break-glass credential when external_auth_providers_enabled is true."
  type        = bool
  default     = false
}

variable "break_glass_username" {
  description = "Username for break glass credential."
  type        = string
  default     = "emergency-admin"
}

variable "break_glass_expiration" {
  description = "Expiration duration for break glass credential (e.g. 24h)."
  type        = string
  default     = "24h"
}

variable "zero_egress" {
  description = <<-EOT
    Set ROSA HCP zero_egress cluster property. Requires VPC endpoints and no NAT.
    For full zero-egress networking use the standalone cluster-zero-egress pattern instead.
  EOT
  type        = bool
  default     = false
}
