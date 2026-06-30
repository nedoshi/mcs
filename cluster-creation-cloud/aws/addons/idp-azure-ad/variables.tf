# Cluster Configuration
variable "cluster_id" {
  description = "The ROSA cluster ID where the IDP will be created. Get this from Terraform Cloud outputs or ROSA CLI."
  type        = string
}

# Azure AD OIDC Configuration
variable "azure_ad_tenant_id" {
  description = "Azure AD tenant ID (Directory ID). Found in Azure Portal > Azure AD > Overview."
  type        = string
  sensitive   = false
}

variable "azure_ad_client_id" {
  description = "Azure AD application (client) ID. Found in Azure Portal > App registrations > Your app > Overview."
  type        = string
  sensitive   = false
}

variable "azure_ad_client_secret" {
  description = "Azure AD client secret value. Created in Azure Portal > App registrations > Your app > Certificates & secrets."
  type        = string
  sensitive   = true
}

variable "idp_name" {
  description = "Name for the identity provider. This will appear in the OpenShift console login page."
  type        = string
  default     = "azure-ad"
}

# RHCS Authentication
# Either token OR client_id/client_secret must be provided
variable "token" {
  description = <<EOF
  OCM token used to authenticate against the OpenShift Cluster Manager API.
  Get your token from: https://console.redhat.com/openshift/token/rosa/show
  Alternative to client_id/client_secret.
  EOF
  type        = string
  sensitive   = true
  default     = null
}

variable "client_id" {
  description = "RHCS API client ID for authentication. Alternative to token."
  type        = string
  sensitive   = true
  default     = null
}

variable "client_secret" {
  description = "RHCS API client secret for authentication. Alternative to token."
  type        = string
  sensitive   = true
  default     = null
}

# AWS Configuration
variable "region" {
  description = "AWS region where the ROSA cluster is located."
  type        = string
  default     = "us-east-1"
}

