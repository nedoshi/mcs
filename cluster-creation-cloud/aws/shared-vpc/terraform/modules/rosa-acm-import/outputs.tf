# ROSA ACM Import Module - Outputs

output "managed_cluster_name" {
  description = "Name of the ManagedCluster resource created on the ACM hub"
  value       = var.cluster_name
}

output "managed_cluster_namespace" {
  description = "Namespace created for the managed cluster on the ACM hub"
  value       = kubernetes_namespace_v1.managed_cluster.metadata[0].name
}

output "managed_cluster_labels" {
  description = "Labels applied to the ManagedCluster resource"
  value       = local.labels
}
