output "cluster_api_url" {
  description = "API URL of the ROSA HCP cluster"
  value       = module.rosa_cluster.cluster_api_url
}

output "cluster_console_url" {
  description = "Web console URL of the ROSA HCP cluster"
  value       = module.rosa_cluster.cluster_console_url
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for cluster encryption"
  value       = module.rosa_kms.kms_key_arn
}

output "cluster_id" {
  description = "ID of the ROSA HCP cluster"
  value       = module.rosa_cluster.cluster_id
}

output "oidc_config_id" {
  description = "OIDC configuration ID"
  value       = module.rosa_account_roles.oidc_config_id
}

# ---------------------------------------------------------------------------
# Entra ID OIDC outputs (only populated when entra_idp_enabled = true)
# ---------------------------------------------------------------------------

output "entra_app_client_id" {
  description = "Entra ID application (client) ID used for OIDC"
  value       = var.entra_idp_enabled ? module.rosa_entra_idp[0].entra_app_client_id : null
}

output "entra_admin_group_object_id" {
  description = "Object ID of the Entra ID admin group bound to cluster-admin"
  value       = var.entra_idp_enabled ? module.rosa_entra_idp[0].admin_group_object_id : null
}

output "entra_tenant_id" {
  description = "Entra ID tenant ID used for the OIDC issuer"
  value       = var.entra_idp_enabled ? module.rosa_entra_idp[0].entra_tenant_id : null
}

output "entra_idp_name" {
  description = "Name of the OIDC identity provider on the ROSA cluster"
  value       = var.entra_idp_enabled ? module.rosa_entra_idp[0].idp_name : null
}
