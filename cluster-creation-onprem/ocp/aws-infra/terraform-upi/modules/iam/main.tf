data "aws_iam_policy_document" "master_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "master" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteVolume",
      "ec2:Describe*",
      "ec2:DetachVolume",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyVolume",
      "ec2:RevokeSecurityGroupIngress",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:AttachLoadBalancerToSubnets",
      "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateLoadBalancerPolicy",
      "elasticloadbalancing:CreateLoadBalancerListeners",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:ConfigureHealthCheck",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancerListeners",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:Describe*",
      "elasticloadbalancing:DetachLoadBalancerFromSubnets",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
      "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
      "elasticloadbalancing:SetSecurityGroups",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "master" {
  name               = "${var.infrastructure_name}-master-role"
  assume_role_policy = data.aws_iam_policy_document.master_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy" "master" {
  name   = "${var.infrastructure_name}-master-policy"
  role   = aws_iam_role.master.id
  policy = data.aws_iam_policy_document.master.json
}

resource "aws_iam_instance_profile" "master" {
  name = "${var.infrastructure_name}-master-profile"
  role = aws_iam_role.master.name
}

data "aws_iam_policy_document" "worker_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "worker" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "worker" {
  name               = "${var.infrastructure_name}-worker-role"
  assume_role_policy = data.aws_iam_policy_document.worker_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy" "worker" {
  name   = "${var.infrastructure_name}-worker-policy"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.infrastructure_name}-worker-profile"
  role = aws_iam_role.worker.name
}

data "aws_iam_policy_document" "bootstrap_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "bootstrap" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "s3:GetObject",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "bootstrap" {
  name               = "${var.infrastructure_name}-bootstrap-role"
  assume_role_policy = data.aws_iam_policy_document.bootstrap_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy" "bootstrap" {
  name   = "${var.infrastructure_name}-bootstrap-policy"
  role   = aws_iam_role.bootstrap.id
  policy = data.aws_iam_policy_document.bootstrap.json
}

resource "aws_iam_instance_profile" "bootstrap" {
  name = "${var.infrastructure_name}-bootstrap-profile"
  role = aws_iam_role.bootstrap.name
}
