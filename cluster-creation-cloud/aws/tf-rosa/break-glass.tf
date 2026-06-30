resource "rhcs_break_glass_credential" "emergency" {
  count = var.external_auth_providers_enabled && var.create_break_glass_credential ? 1 : 0

  cluster             = rhcs_cluster_rosa_hcp.rosa.id
  username            = var.break_glass_username
  expiration_duration = var.break_glass_expiration
}

output "break_glass_credential_id" {
  description = "ID of the break glass credential"
  value       = try(rhcs_break_glass_credential.emergency[0].id, null)
}

output "break_glass_kubeconfig" {
  description = "Kubeconfig for break glass emergency access"
  value       = try(rhcs_break_glass_credential.emergency[0].kubeconfig, null)
  sensitive   = true
}

output "break_glass_expiration" {
  description = "Expiration timestamp of the break glass credential"
  value       = try(rhcs_break_glass_credential.emergency[0].expiration_timestamp, null)
}
