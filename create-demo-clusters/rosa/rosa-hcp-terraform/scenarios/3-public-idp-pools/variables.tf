# scenarios/3-public-idp-pools/variables.tf

# AWS Configuration
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# VPC Configuration
variable "create_vpc" {
  description = "Create new VPC"
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "Existing VPC ID"
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway"
  type        = bool
  default     = true  # Cost savings for dev
}

# ROSA Cluster Configuration
variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "openshift_version" {
  description = "OpenShift version"
  type        = string
  default     = "4.14"
}

variable "default_replicas" {
  description = "Default worker replicas"
  type        = number
  default     = 2
}

variable "default_compute_machine_type" {
  description = "Default instance type"
  type        = string
  default     = "m5.xlarge"
}

# RHCS Configuration
variable "rhcs_token" {
  description = "Red Hat Cloud Services token"
  type        = string
  sensitive   = true
}

variable "rhcs_url" {
  description = "RHCS API URL"
  type        = string
  default     = "https://api.openshift.com"
}

variable "create_account_roles" {
  description = "Create account roles"
  type        = bool
  default     = false
}

variable "existing_account_role_prefix" {
  description = "Existing account role prefix"
  type        = string
  default     = null
}

# Development Pool
variable "create_dev_pool" {
  description = "Create development pool"
  type        = bool
  default     = true
}

variable "dev_instance_type" {
  description = "Dev pool instance type"
  type        = string
  default     = "m5.large"
}

variable "dev_pool_replicas" {
  description = "Dev pool replicas"
  type        = number
  default     = 2
}

variable "enable_dev_autoscaling" {
  description = "Enable dev pool autoscaling"
  type        = bool
  default     = true
}

variable "dev_pool_min_replicas" {
  description = "Dev pool min replicas"
  type        = number
  default     = 1
}

variable "dev_pool_max_replicas" {
  description = "Dev pool max replicas"
  type        = number
  default     = 5
}

# Production Pool
variable "create_prod_pool" {
  description = "Create production pool"
  type        = bool
  default     = true
}

variable "prod_instance_type" {
  description = "Prod pool instance type"
  type        = string
  default     = "m5.2xlarge"
}

variable "prod_pool_replicas" {
  description = "Prod pool replicas"
  type        = number
  default     = 3
}

variable "enable_prod_autoscaling" {
  description = "Enable prod pool autoscaling"
  type        = bool
  default     = true
}

variable "prod_pool_min_replicas" {
  description = "Prod pool min replicas"
  type        = number
  default     = 2
}

variable "prod_pool_max_replicas" {
  description = "Prod pool max replicas"
  type        = number
  default     = 10
}

# Testing Pool
variable "create_test_pool" {
  description = "Create testing pool"
  type        = bool
  default     = false
}

variable "test_instance_type" {
  description = "Test pool instance type"
  type        = string
  default     = "m5.large"
}

variable "test_pool_replicas" {
  description = "Test pool replicas"
  type        = number
  default     = 2
}

variable "enable_test_autoscaling" {
  description = "Enable test pool autoscaling"
  type        = bool
  default     = true
}

variable "test_pool_min_replicas" {
  description = "Test pool min replicas"
  type        = number
  default     = 1
}

variable "test_pool_max_replicas" {
  description = "Test pool max replicas"
  type        = number
  default     = 5
}

# HTPasswd IDP (Emergency Access)
variable "htpasswd_username" {
  description = "HTPasswd admin username"
  type        = string
  default     = "kubeadmin"
}

# GitHub IDP
variable "enable_github_idp" {
  description = "Enable GitHub IDP"
  type        = bool
  default     = false
}

variable "github_client_id" {
  description = "GitHub OAuth client ID"
  type        = string
  default     = ""
}

variable "github_client_secret" {
  description = "GitHub OAuth client secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_organizations" {
  description = "GitHub organizations"
  type        = list(string)
  default     = []
}

variable "github_teams" {
  description = "GitHub teams"
  type        = list(string)
  default     = []
}

variable "github_hostname" {
  description = "GitHub hostname (for enterprise)"
  type        = string
  default     = ""
}

variable "github_ca" {
  description = "GitHub CA certificate"
  type        = string
  default     = ""
}

# GitLab IDP
variable "enable_gitlab_idp" {
  description = "Enable GitLab IDP"
  type        = bool
  default     = false
}

variable "gitlab_client_id" {
  description = "GitLab OAuth client ID"
  type        = string
  default     = ""
}

variable "gitlab_client_secret" {
  description = "GitLab OAuth client secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitlab_url" {
  description = "GitLab URL"
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_ca" {
  description = "GitLab CA certificate"
  type        = string
  default     = ""
}

# Google IDP
variable "enable_google_idp" {
  description = "Enable Google IDP"
  type        = bool
  default     = false
}

variable "google_client_id" {
  description = "Google OAuth client ID"
  type        = string
  default     = ""
}

variable "google_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "google_hosted_domain" {
  description = "Google hosted domain"
  type        = string
  default     = ""
}

# LDAP IDP
variable "enable_ldap_idp" {
  description = "Enable LDAP IDP"
  type        = bool
  default     = false
}

variable "ldap_bind_dn" {
  description = "LDAP bind DN"
  type        = string
  default     = ""
}

variable "ldap_bind_password" {
  description = "LDAP bind password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ldap_url" {
  description = "LDAP URL"
  type        = string
  default     = ""
}

variable "ldap_insecure" {
  description = "LDAP insecure connection"
  type        = bool
  default     = false
}

variable "ldap_ca" {
  description = "LDAP CA certificate"
  type        = string
  default     = ""
}

variable "ldap_id_attributes" {
  description = "LDAP ID attributes"
  type        = list(string)
  default     = ["dn"]
}

variable "ldap_email_attributes" {
  description = "LDAP email attributes"
  type        = list(string)
  default     = ["mail"]
}

variable "ldap_name_attributes" {
  description = "LDAP name attributes"
  type        = list(string)
  default     = ["cn"]
}

variable "ldap_preferred_username_attributes" {
  description = "LDAP preferred username attributes"
  type        = list(string)
  default     = ["uid"]
}

# OpenID Connect IDP
variable "enable_oidc_idp" {
  description = "Enable OpenID Connect IDP"
  type        = bool
  default     = false
}

variable "oidc_idp_name" {
  description = "OIDC IDP name"
  type        = string
  default     = "oidc"
}

variable "oidc_client_id" {
  description = "OIDC client ID"
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "OIDC client secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "oidc_issuer" {
  description = "OIDC issuer URL"
  type        = string
  default     = ""
}

variable "oidc_ca" {
  description = "OIDC CA certificate"
  type        = string
  default     = ""
}

variable "oidc_email_claims" {
  description = "OIDC email claims"
  type        = list(string)
  default     = ["email"]
}

variable "oidc_name_claims" {
  description = "OIDC name claims"
  type        = list(string)
  default     = ["name"]
}

variable "oidc_preferred_username_claims" {
  description = "OIDC preferred username claims"
  type        = list(string)
  default     = ["preferred_username"]
}

variable "oidc_groups_claims" {
  description = "OIDC groups claims"
  type        = list(string)
  default     = ["groups"]
}

variable "oidc_extra_scopes" {
  description = "OIDC extra scopes"
  type        = list(string)
  default     = ["email", "profile"]
}

# RBAC
variable "cluster_admin_users" {
  description = "Users to grant cluster-admin role"
  type        = list(string)
  default     = []
}

# Tags
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "development"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}