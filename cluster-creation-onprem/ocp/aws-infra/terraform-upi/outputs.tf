output "infrastructure_name" {
  description = "Infrastructure ID used as a prefix on AWS resources."
  value       = local.infrastructure_name
}

output "cluster_domain" {
  description = "Cluster DNS domain (<cluster>.<base_domain>)."
  value       = local.cluster_domain
}

output "api_server_url" {
  description = "Kubernetes API server URL."
  value       = "https://api.${local.cluster_domain}:6443"
}

output "api_server_internal_url" {
  description = "Internal Kubernetes API server URL."
  value       = "https://api-int.${local.cluster_domain}:6443"
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_hosted_zone_id" {
  value = module.dns.private_hosted_zone_id
}

output "internal_api_lb_arn" {
  value = module.load_balancer.internal_api_lb_arn
}

output "external_api_lb_arn" {
  value = module.load_balancer.external_api_lb_arn
}

output "internal_api_target_group_arn" {
  value = module.load_balancer.internal_api_target_group_arn
}

output "internal_service_target_group_arn" {
  value = module.load_balancer.internal_service_target_group_arn
}

output "external_api_target_group_arn" {
  value = module.load_balancer.external_api_target_group_arn
}

output "master_security_group_id" {
  value = module.security.master_security_group_id
}

output "worker_security_group_id" {
  value = module.security.worker_security_group_id
}

output "master_instance_profile" {
  value = module.iam.master_instance_profile_name
}

output "worker_instance_profile" {
  value = module.iam.worker_instance_profile_name
}

output "rhcos_ami" {
  description = "RHCOS AMI used for cluster nodes."
  value       = coalesce(var.rhcos_ami, try(data.aws_ami.rhcos[0].id, null))
}

output "install_output_dir" {
  description = "Directory containing openshift-install assets (when enable_cluster_install is true)."
  value       = var.enable_cluster_install ? var.install_output_dir : null
}

output "kubeconfig_path" {
  description = "Path to kubeconfig after cluster install completes."
  value       = var.enable_cluster_install ? "${var.install_output_dir}/${local.infrastructure_name}/auth/kubeconfig" : null
}

output "ssh_private_key_path" {
  description = "Path to generated SSH private key (when enable_cluster_install and no ssh_public_key provided)."
  value       = var.enable_cluster_install && var.ssh_public_key == null ? "${var.install_output_dir}/${local.infrastructure_name}/id_ed25519" : null
}
