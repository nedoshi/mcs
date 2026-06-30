# Root Module Variables - ROSA HCP Automation

variable "cluster_name" {
  description = "Name of the ROSA HCP cluster (max 15 characters)"
  type        = string
}

variable "region" {
  description = "AWS region for the cluster"
  type        = string
}

variable "openshift_version" {
  description = "OpenShift version for the cluster"
  type        = string
  default     = "4.18.32"
}

variable "cluster_account_id" {
  description = "AWS account ID where the cluster will run"
  type        = string
}

variable "shared_vpc_account_id" {
  description = "AWS account ID of the shared VPC"
  type        = string
}

variable "account_roles_prefix" {
  description = "Prefix for account IAM roles"
  type        = string
}

variable "operator_roles_prefix" {
  description = "Prefix for operator IAM roles"
  type        = string
}

variable "oidc_config_id" {
  description = "OIDC config ID from `rosa create oidc-config` output"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones for the cluster"
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to all objects."
  type        = map(string)
  default = {
    "cost-center"   = "468"
    "service-phase" = "lab"
    "app-code"      = "MOBB-001"
    "owner"         = "nedoshi@redhat.com"
  }
}

variable "rhcs_token" {
  description = "Red Hat Cloud Services (OCM) API token"
  type        = string
  sensitive   = true
}

variable "shared_vpc_role_arn" {
  description = "ARN of the role to assume in shared VPC account"
  type        = string
}

variable "base_dns_domain" {
  description = "Base DNS domain for the ROSA cluster (e.g. rosa.example.com)"
  type        = string
  default     = ""
}

variable "external_auth_providers_enabled" {
  description = "Enable external authentication providers (bypasses built-in OAuth). Set to false to use the ROSA built-in OAuth server with IdP integration."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Microsoft Entra ID / OIDC Identity Provider
# ---------------------------------------------------------------------------

variable "entra_idp_enabled" {
  description = "Enable Microsoft Entra ID OIDC identity provider on the ROSA cluster"
  type        = bool
  default     = false
}

variable "entra_idp_name" {
  description = "Display name of the OIDC IdP shown on the ROSA login page"
  type        = string
  default     = "Entra-ID"
}

variable "entra_admin_group_name" {
  description = "Display name for the Entra ID security group mapped to cluster-admin"
  type        = string
  default     = "ROSA-Cluster-Admins"
}

variable "entra_admin_group_member_object_ids" {
  description = "Entra ID object IDs of users/principals to add to the admin group"
  type        = list(string)
  default     = []
}

variable "disable_kubeadmin" {
  description = "Delete the kubeadmin credential after Entra ID IdP is configured"
  type        = bool
  default     = true
}

# Set to false when the Terraform SP lacks Graph API permissions.
# Pre-create the app registration + group in the Azure Portal, then supply
# the entra_existing_* values below.
variable "manage_entra_resources" {
  description = "If true, Terraform creates Entra ID app & group. If false, use pre-created resources."
  type        = bool
  default     = true
}

variable "entra_existing_client_id" {
  description = "Client ID of a pre-created Entra ID app registration"
  type        = string
  default     = ""
}

variable "entra_existing_client_secret" {
  description = "Client secret of a pre-created Entra ID app registration"
  type        = string
  sensitive   = true
  default     = ""
}

variable "entra_existing_tenant_id" {
  description = "Entra ID tenant ID for the pre-created app"
  type        = string
  default     = ""
}

variable "entra_existing_admin_group_object_id" {
  description = "Object ID of a pre-created Entra ID security group for cluster-admin"
  type        = string
  default     = ""
}
