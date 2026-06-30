output "installer_role_arn" {
  description = "ARN of the HCP ROSA Installer Role"
  value       = data.aws_iam_role.installer.arn
}

output "support_role_arn" {
  description = "ARN of the HCP ROSA Support Role"
  value       = data.aws_iam_role.support.arn
}

output "worker_role_arn" {
  description = "ARN of the HCP ROSA Worker Role"
  value       = data.aws_iam_role.worker.arn
}

output "oidc_config_id" {
  description = "OIDC configuration ID (pass-through from variable)"
  value       = var.oidc_config_id
}

output "account_role_prefix" {
  description = "Prefix used for account roles"
  value       = var.account_roles_prefix
}
