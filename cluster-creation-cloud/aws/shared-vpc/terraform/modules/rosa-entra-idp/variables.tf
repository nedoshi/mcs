variable "cluster_id" {
  description = "ROSA HCP cluster ID (from rhcs_cluster_rosa_hcp)"
  type        = string
}

variable "cluster_name" {
  description = "ROSA HCP cluster name, used for naming Entra ID resources"
  type        = string
}

variable "oauth_callback_url" {
  description = "Full OAuth callback URL: https://oauth.<apps_domain>/oauth2callback/<idp_name>"
  type        = string
}

variable "idp_name" {
  description = "Display name for the identity provider in ROSA"
  type        = string
  default     = "Entra-ID"
}

variable "admin_group_name" {
  description = "Display name for the Entra ID security group that maps to cluster-admin"
  type        = string
}

variable "admin_group_member_object_ids" {
  description = "Object IDs of Entra ID users/principals to add to the admin group"
  type        = list(string)
  default     = []
}

variable "disable_kubeadmin" {
  description = "Delete the kubeadmin secret after the IdP is configured"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Pre-created Entra ID resources (Option B — when SP lacks Graph permissions)
# Set manage_entra_resources = false and supply these values from resources
# created manually in the Azure Portal or via az CLI.
# ---------------------------------------------------------------------------

variable "manage_entra_resources" {
  description = "If true (default), Terraform creates the Entra ID app, service principal, secret, and group. If false, supply pre-created values via the entra_existing_* variables."
  type        = bool
  default     = true
}

variable "entra_existing_client_id" {
  description = "Client ID of a pre-created Entra ID app registration (required when manage_entra_resources = false)"
  type        = string
  default     = ""
}

variable "entra_existing_client_secret" {
  description = "Client secret of a pre-created Entra ID app registration (required when manage_entra_resources = false)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "entra_existing_tenant_id" {
  description = "Entra ID tenant ID (required when manage_entra_resources = false)"
  type        = string
  default     = ""
}

variable "entra_existing_admin_group_object_id" {
  description = "Object ID of a pre-created Entra ID security group (required when manage_entra_resources = false)"
  type        = string
  default     = ""
}
