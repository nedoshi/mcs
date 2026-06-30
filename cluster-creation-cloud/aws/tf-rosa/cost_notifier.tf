resource "time_static" "cluster_created" {}

locals {
  cost_center_tag = {
    "cost-center" = "468"
  }

  cost_notifier_tags = {
    "expires-at"   = formatdate("YYYY-MM-DD", timeadd(time_static.cluster_created.rfc3339, "48h"))
    "delete-after" = formatdate("YYYY-MM-DD", timeadd(time_static.cluster_created.rfc3339, "72h"))
  }

  tags = merge(local.cost_center_tag, var.tags, local.cost_notifier_tags)
}
