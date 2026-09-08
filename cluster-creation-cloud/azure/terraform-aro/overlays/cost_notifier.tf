# MCS cost-notifier tags — merged into local.tags by prepare (see Makefile).
# cost-center 468 is always applied; expires-at (+2d) and delete-after (+3d) are
# computed at apply time from time_static.cluster_created.

resource "time_static" "cluster_created" {}

locals {
  mcs_cost_center_tag = {
    "cost-center" = "468"
  }

  mcs_cost_notifier_tags = {
    "expires-at"   = formatdate("YYYY-MM-DD", timeadd(time_static.cluster_created.rfc3339, "48h"))
    "delete-after" = formatdate("YYYY-MM-DD", timeadd(time_static.cluster_created.rfc3339, "72h"))
  }

  tags = merge(local.mcs_cost_center_tag, var.tags, local.mcs_cost_notifier_tags)
}
