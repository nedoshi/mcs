# ROSA ACM Import Module
# Imports a ROSA HCP cluster into an ACM hub by creating a ManagedCluster,
# KlusterletAddonConfig, and auto-import-secret on the hub cluster.
#
# Prerequisites:
#   - The kubernetes provider must be configured to target the ACM hub cluster.
#   - The target ManagedClusterSet must already exist.
#   - A kubeconfig or service-account token for the ROSA cluster must be provided.

locals {
  use_kubeconfig = var.rosa_kubeconfig != ""

  base_labels = {
    "cloud"                                         = "Amazon"
    "vendor"                                        = "OpenShift"
    "platform"                                      = "rosa-hcp"
    "region"                                        = var.region
    "environment"                                   = var.environment
    "role"                                          = var.cluster_role
    "cluster.open-cluster-management.io/clusterset" = var.managed_cluster_set
  }

  labels = merge(local.base_labels, var.additional_labels)
}

# ---------------------------------------------------------------------------
# 1. Namespace — ACM requires a namespace matching the ManagedCluster name
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "managed_cluster" {
  metadata {
    name = var.cluster_name
    labels = {
      "cluster.open-cluster-management.io/managedCluster" = var.cluster_name
    }
  }
}

# ---------------------------------------------------------------------------
# 2. ManagedCluster — registers the ROSA cluster with ACM
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "managed_cluster" {
  manifest = {
    apiVersion = "cluster.open-cluster-management.io/v1"
    kind       = "ManagedCluster"
    metadata = {
      name   = var.cluster_name
      labels = local.labels
    }
    spec = {
      hubAcceptsClient = true
    }
  }

  depends_on = [kubernetes_namespace_v1.managed_cluster]
}

# ---------------------------------------------------------------------------
# 3. KlusterletAddonConfig — enables ACM addon agents on the spoke cluster
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "klusterlet_addon_config" {
  manifest = {
    apiVersion = "agent.open-cluster-management.io/v1"
    kind       = "KlusterletAddonConfig"
    metadata = {
      name      = var.cluster_name
      namespace = var.cluster_name
    }
    spec = {
      clusterName      = var.cluster_name
      clusterNamespace = var.cluster_name
      applicationManager   = { enabled = var.klusterlet_addon_config.application_manager }
      searchCollector      = { enabled = var.klusterlet_addon_config.search_collector }
      policyController     = { enabled = var.klusterlet_addon_config.policy_controller }
      certPolicyController = { enabled = var.klusterlet_addon_config.cert_policy_controller }
      iamPolicyController  = { enabled = var.klusterlet_addon_config.iam_policy_controller }
    }
  }

  depends_on = [kubernetes_manifest.managed_cluster]
}

# ---------------------------------------------------------------------------
# 4. Auto-import secret — provides credentials ACM uses to install the
#    klusterlet agent on the ROSA cluster. Supports kubeconfig or token mode.
# ---------------------------------------------------------------------------

resource "kubernetes_secret_v1" "auto_import" {
  metadata {
    name      = "auto-import-secret"
    namespace = var.cluster_name
  }

  type = "Opaque"

  data = local.use_kubeconfig ? {
    kubeconfig = var.rosa_kubeconfig
    } : {
    token  = var.rosa_api_token
    server = var.rosa_api_url
  }

  depends_on = [kubernetes_manifest.managed_cluster]
}
