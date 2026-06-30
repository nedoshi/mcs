#------------------------------------------------------------------------------
# Cluster KMS key (optional) for ROSA HCP worker EBS and etcd encryption.
# When cluster_kms_mode = "create", Terraform creates a customer-managed key
# with policy aligned to Red Hat ROSA HCP requirements.
#------------------------------------------------------------------------------

data "aws_caller_identity" "kms" {
  count = var.cluster_kms_mode == "create" ? 1 : 0
}

data "aws_partition" "kms" {
  count = var.cluster_kms_mode == "create" ? 1 : 0
}

locals {
  create_cluster_kms = var.cluster_kms_mode == "create"
  # Effective ARN for cluster (null = provider-managed)
  cluster_kms_key_arn = (
    var.cluster_kms_mode == "provider_managed" ? null :
    var.cluster_kms_mode == "create" ? aws_kms_key.cluster[0].arn :
    var.cluster_kms_key_arn
  )
  account_role_prefix_kms  = var.account_role_prefix != "" ? var.account_role_prefix : var.cluster_name
  operator_role_prefix_kms = var.cluster_name
}

resource "aws_kms_key" "cluster" {
  count = local.create_cluster_kms ? 1 : 0

  description             = "ROSA HCP cluster KMS key for ${var.cluster_name} - workers and etcd"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.cluster_kms_policy[0].json

  tags = merge(local.tags, {
    Name = "${var.cluster_name}-cluster-kms"
  })
}

resource "aws_kms_alias" "cluster" {
  count = local.create_cluster_kms ? 1 : 0

  name          = "alias/${var.cluster_name}-cluster"
  target_key_id = aws_kms_key.cluster[0].key_id
}

data "aws_iam_policy_document" "cluster_kms_policy" {
  count = local.create_cluster_kms ? 1 : 0

  statement {
    sid    = "Root"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.kms[0].partition}:iam::${data.aws_caller_identity.kms[0].account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "ROSAAccountRoles"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:${data.aws_partition.kms[0].partition}:iam::${data.aws_caller_identity.kms[0].account_id}:role/${local.account_role_prefix_kms}-*-Role"]
    }
  }

  statement {
    sid    = "ROSAAccountRolesCreateGrant"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:${data.aws_partition.kms[0].partition}:iam::${data.aws_caller_identity.kms[0].account_id}:role/${local.account_role_prefix_kms}-*-Role"]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    sid    = "ROSAOperatorRoles"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:${data.aws_partition.kms[0].partition}:iam::${data.aws_caller_identity.kms[0].account_id}:role/${local.operator_role_prefix_kms}-openshift-*"]
    }
  }

  statement {
    sid    = "ROSAOperatorRolesCreateGrant"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:${data.aws_partition.kms[0].partition}:iam::${data.aws_caller_identity.kms[0].account_id}:role/${local.operator_role_prefix_kms}-openshift-*"]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  # HCP EC2 / Auto Scaling / CAPA
  statement {
    sid    = "HCPEC2"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
  }
  statement {
    sid    = "HCPEC2CreateGrant"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
  statement {
    sid    = "HCPAutoScaling"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["autoscaling.amazonaws.com"]
    }
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
  }
  statement {
    sid    = "HCPAutoScalingCreateGrant"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["autoscaling.amazonaws.com"]
    }
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
  statement {
    sid    = "HCPCAPA"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:DescribeKey", "kms:GenerateDataKeyWithoutPlaintext", "kms:CreateGrant"]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:${data.aws_partition.kms[0].partition}:iam::${data.aws_caller_identity.kms[0].account_id}:role/${local.operator_role_prefix_kms}-kube-system-capa-controller-manager"]
    }
  }

  # etcd encryption (when enabled)
  dynamic "statement" {
    for_each = var.etcd_encryption ? [1] : []
    content {
      sid    = "HCPKubeControllerManager"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = ["*"]
      }
      actions   = ["kms:DescribeKey"]
      resources = ["*"]
      condition {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values   = ["arn:${data.aws_partition.kms[0].partition}:iam::${data.aws_caller_identity.kms[0].account_id}:role/${local.operator_role_prefix_kms}-kube-system-kube-controller-manager"]
      }
    }
  }
  dynamic "statement" {
    for_each = var.etcd_encryption ? [1] : []
    content {
      sid    = "HCPKMSProvider"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = ["*"]
      }
      actions   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
      resources = ["*"]
      condition {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values   = ["arn:${data.aws_partition.kms[0].partition}:iam::${data.aws_caller_identity.kms[0].account_id}:role/${local.operator_role_prefix_kms}-kube-system-kms-provider"]
      }
    }
  }
}

check "cluster_kms_existing_requires_arn" {
  assert {
    condition     = var.cluster_kms_mode != "existing" || var.cluster_kms_key_arn != null
    error_message = "cluster_kms_key_arn must be set when cluster_kms_mode is existing."
  }
}
