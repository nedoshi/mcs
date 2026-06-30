# ROSA HCP Post-Install Module - Outputs

output "storage_class_names" {
  description = "List of created StorageClass names"
  value       = [for k, v in kubernetes_storage_class_v1.kms_encrypted : k]
}
