# ROSA HCP Post-Install Module
# Demotes the default gp3-csi StorageClass so GitOps-managed KMS StorageClasses
# can be set as default. StorageClass creation is handled by the GitOps
# rosa-platform-config Helm chart (gitops/charts/rosa-platform-config).

# -----------------------------------------------------------------------------
# Demote gp3-csi as default StorageClass
# -----------------------------------------------------------------------------
resource "null_resource" "demote_default_storageclass" {
  provisioner "local-exec" {
    command = <<-EOT
      oc patch storageclass gp3-csi -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true
    EOT
  }

  triggers = {
    cluster_name = var.cluster_name
  }
}
