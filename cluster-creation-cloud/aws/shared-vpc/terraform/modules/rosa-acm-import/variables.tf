# ROSA ACM Import Module - Variables

variable "cluster_name" {
  description = "Name of the ROSA HCP cluster to import into ACM"
  type        = string
}

variable "region" {
  description = "AWS region where the ROSA cluster is deployed"
  type        = string
}

variable "environment" {
  description = "Environment label for the managed cluster (e.g. lab, dev, qa, prod)"
  type        = string
}

variable "cluster_role" {
  description = "Role of the cluster in the ACM topology (hub or spoke)"
  type        = string
  default     = "spoke"

  validation {
    condition     = contains(["hub", "spoke"], var.cluster_role)
    error_message = "cluster_role must be 'hub' or 'spoke'."
  }
}

variable "managed_cluster_set" {
  description = "Name of the ManagedClusterSet to assign the imported cluster to"
  type        = string
}

variable "rosa_kubeconfig" {
  description = "Kubeconfig content for the ROSA cluster (used by auto-import-secret). Provide either this or rosa_api_token + rosa_api_url."
  type        = string
  sensitive   = true
  default     = ""
}

variable "rosa_api_url" {
  description = "API server URL of the ROSA cluster (used with token-based import)"
  type        = string
  default     = ""
}

variable "rosa_api_token" {
  description = "Service account token with cluster-admin privileges on the ROSA cluster (used with token-based import)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "klusterlet_addon_config" {
  description = "Feature toggles for KlusterletAddonConfig"
  type = object({
    application_manager  = optional(bool, true)
    search_collector     = optional(bool, true)
    policy_controller    = optional(bool, true)
    cert_policy_controller = optional(bool, true)
    iam_policy_controller  = optional(bool, true)
  })
  default = {}
}

variable "additional_labels" {
  description = "Extra labels to apply to the ManagedCluster resource"
  type        = map(string)
  default     = {}
}
