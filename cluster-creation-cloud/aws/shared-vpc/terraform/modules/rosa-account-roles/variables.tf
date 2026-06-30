variable "account_roles_prefix" {
  description = "Prefix used when creating ROSA account roles via `rosa create account-roles --prefix <PREFIX>`"
  type        = string
}

variable "oidc_config_id" {
  description = "OIDC config ID from `rosa create oidc-config` output"
  type        = string
}
