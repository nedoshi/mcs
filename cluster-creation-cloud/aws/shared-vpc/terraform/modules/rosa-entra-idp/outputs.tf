output "entra_app_client_id" {
  description = "Application (client) ID of the Entra ID OIDC app registration"
  value       = local.client_id
}

output "entra_app_object_id" {
  description = "Object ID of the Entra ID application (null when using pre-created resources)"
  value       = local.manage ? azuread_application.rosa_oidc[0].object_id : null
}

output "admin_group_object_id" {
  description = "Object ID of the Entra ID admin security group"
  value       = local.admin_group_id
}

output "admin_group_display_name" {
  description = "Display name of the Entra ID admin security group"
  value       = local.manage ? azuread_group.rosa_cluster_admins[0].display_name : var.admin_group_name
}

output "idp_name" {
  description = "Name of the OIDC identity provider configured on the ROSA cluster"
  value       = rhcs_identity_provider.entra_oidc.name
}

output "entra_tenant_id" {
  description = "Entra ID tenant ID used for the OIDC issuer"
  value       = local.tenant_id
}
