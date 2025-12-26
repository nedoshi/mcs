variable "cluster_name" {
  type        = string
  default     = null
  description = "The name of the ROSA cluster. If not provided, a random name will be generated."
}

#AWS Info
variable "aws_region" {
  type        = string
  default     = "us-east-2"
  description = "The AWS region to provision resources into."
}

variable "admin_username" {
  type        = string
  description = "The username for the admin user"
}

variable "admin_password" {
  type = string
  description = "The password for the admin user"
  sensitive = true
}

variable "custom_domain" {
  type        = string
  description = "Custom domain name for the private hosted zone"
}

variable "token" {
  type        = string
  description = "OCM token used to authenticate against the OpenShift Cluster Manager API. See https://console.redhat.com/openshift/token/rosa/show to access your token."
  default     = null
  sensitive   = true
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
