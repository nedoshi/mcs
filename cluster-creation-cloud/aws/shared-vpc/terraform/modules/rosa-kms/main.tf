# ROSA HCP KMS Module
# Customer-managed KMS key with policy granting ROSA operator roles required permissions

# -----------------------------------------------------------------------------
# KMS Key Policy
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "kms" {
  # Root account - full administrative access
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Installer role - CreateGrant, DescribeKey, GenerateDataKeyWithoutPlaintext
  statement {
    sid    = "AllowROSAInstallerRole"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.installer_role_arn]
    }
    actions = [
      "kms:CreateGrant",
      "kms:DescribeKey",
      "kms:GenerateDataKeyWithoutPlaintext"
    ]
    resources = ["*"]
  }

  # Support role - DescribeKey
  statement {
    sid    = "AllowROSASupportRole"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.support_role_arn]
    }
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
  }

  # Kube Controller Manager - DescribeKey
  statement {
    sid    = "AllowKubeControllerManager"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.operator_role_arns.kube_controller_manager]
    }
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
  }

  # KMS Provider - Encrypt, Decrypt, DescribeKey (etcd)
  statement {
    sid    = "AllowKMSProviderForEtcd"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.operator_role_arns.kms_provider]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }

  # CAPA Controller Manager - DescribeKey, GenerateDataKeyWithoutPlaintext, CreateGrant
  statement {
    sid    = "AllowCAPAControllerForNodes"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.operator_role_arns.capa_controller_manager]
    }
    actions = [
      "kms:DescribeKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:CreateGrant"
    ]
    resources = ["*"]
  }

  # EBS CSI Driver - data-plane KMS operations (called by EC2 on behalf of CSI driver)
  statement {
    sid    = "AllowEBSCSIDriverKMSOperations"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.operator_role_arns.ebs_csi_driver]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }

  # EBS CSI Driver - CreateGrant (restricted to AWS service grants only)
  statement {
    sid    = "AllowEBSCSIDriverCreateGrant"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.operator_role_arns.ebs_csi_driver]
    }
    actions = [
      "kms:CreateGrant",
      "kms:RevokeGrant",
      "kms:ListGrants"
    ]
    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

# -----------------------------------------------------------------------------
# KMS Key
# -----------------------------------------------------------------------------
resource "aws_kms_key" "rosa" {
  description             = "ROSA HCP encryption key for cluster ${var.cluster_name}"
  deletion_window_in_days  = var.deletion_window_in_days
  enable_key_rotation     = var.enable_key_rotation
  multi_region            = false
  policy                  = data.aws_iam_policy_document.kms.json

  tags = merge(var.tags, {
    "Name"    = "${var.cluster_name}-kms"
    "red-hat" = "true"
  })
}

# -----------------------------------------------------------------------------
# KMS Alias
# -----------------------------------------------------------------------------
resource "aws_kms_alias" "rosa" {
  name          = "alias/${var.cluster_name}-key"
  target_key_id = aws_kms_key.rosa.key_id
}
