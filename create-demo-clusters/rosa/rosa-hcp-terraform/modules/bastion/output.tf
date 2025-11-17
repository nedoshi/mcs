output "bastion_instance_id" {
  description = "Instance ID of the bastion host (empty if var.private = false)"
  value       = var.private ? aws_instance.bastion_host[0].id : null
}

output "bastion_public_ip" {
  description = "Public IP of the bastion (only if it has one)"
  value       = var.private && var.bastion_public_ip ? aws_instance.bastion_host[0].public_ip : null
}

output "bastion_private_ip" {
  description = "Private IP of the bastion host"
  value       = var.private ? aws_instance.bastion_host[0].private_ip : null
}

output "bastion_security_group_id" {
  description = "Security group ID attached to the bastion"
  value       = var.private ? aws_security_group.bastion_host[0].id : null
}

output "bastion_access_instructions" {
  description = "Ready-to-copy instructions for accessing the bastion (SSH or SSM + sshuttle)"
  value       = var.private ? local.bastion_output : "Direct SSH access is not configured when var.private = false"
}

# Helpful one-liner you can echo right after apply
output "bastion_ssh_command" {
  description = "One-liner SSH command (only when bastion has a public IP)"
  value = var.private && var.bastion_public_ip ? (
    "ssh ec2-user@${aws_instance.bastion_host[0].public_ip}"
  ) : null
}

output "bastion_sshuttle_command" {
  description = "Full sshuttle command for VPN-over-SSM access (only when fully private)"
  value = var.private && !var.bastion_public_ip ? replace(
    local.bastion_ssm,
    "--remote ec2-user@${aws_instance.bastion_host[0].id}",
    "--remote ec2-user@${aws_instance.bastion_host[0].id}"
  ) : null
}