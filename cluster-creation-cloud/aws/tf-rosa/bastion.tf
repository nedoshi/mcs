locals {
  bastion_tags   = merge(local.tags, { "Name" = "${var.cluster_name}-bastion" })
  bastion_subnet = var.bastion_public_ip ? module.network.public_subnets[0] : module.network.private_subnets[0]
  bastion_ssh    = <<EOF
You can SSH to your bastion via

    ssh ec2-user@${(var.private && var.bastion_public_ip) ? aws_instance.bastion_host[0].public_ip : ""}
    or
    sshuttle --remote ec2-user@${(var.private && var.bastion_public_ip) ? aws_instance.bastion_host[0].public_ip : ""} --dns ${var.vpc_cidr}
EOF
  bastion_ssm    = <<EOF
Congratulations on securely deploying your bastion to a private subnet with no public internet ingress!

It's so secure you can't even SSH to it.

Uhhh so how do I access my cluster?  Glad you asked!

1. Install the AWS Session Manager Plugin for the AWS CLI

    - https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

2. Install sshuttle

    - For mac `brew install sshuttle`
    - Otherwise - https://sshuttle.readthedocs.io/en/stable/installation.html

3. Create an SSH VPN over AWS Session Manager

    sshuttle --ssh-cmd="ssh -o ProxyCommand='sh -c \"aws --region ${var.region} ssm start-session --target %h --document-name AWS-StartSSHSession --parameters \
    portNumber=22\"'" --remote ec2-user@${(var.private && !var.bastion_public_ip) ? aws_instance.bastion_host[0].id : ""} --dns ${var.vpc_cidr}
EOF
  bastion_output = var.private ? (var.bastion_public_ip ? local.bastion_ssh : local.bastion_ssm) : null
}

resource "aws_iam_instance_profile" "bastion_iam_profile" {
  count = var.private ? 1 : 0
  name  = "${var.cluster_name}-bastion-ec2_profile"
  role  = aws_iam_role.bastion_iam_role[0].name

  tags = local.bastion_tags
}

data "aws_iam_policy_document" "bastion_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion_iam_role" {
  count              = var.private ? 1 : 0
  name               = "${var.cluster_name}-bastion-iam-role"
  description        = "The role for the bastion EC2"
  assume_role_policy = data.aws_iam_policy_document.bastion_assume_role.json

  tags = local.bastion_tags
}

resource "aws_iam_role_policy_attachment" "bastion_iam_ssm_policy" {
  count      = var.private ? 1 : 0
  role       = aws_iam_role.bastion_iam_role[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Prefer Amazon Linux 2023 for bastion hosts because SSM Agent is preinstalled.
data "aws_ssm_parameter" "bastion_al2023_ami" {
  count = var.private ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_key_pair" "bastion_host" {
  count = var.private ? 1 : 0

  key_name   = "${var.cluster_name}-bastion"
  public_key = file(var.bastion_public_ssh_key)

  tags = local.bastion_tags
}

resource "aws_security_group" "bastion_host" {
  count = var.private ? 1 : 0

  description = "Security group for Bastion access"
  name        = "${var.cluster_name}-bastion"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "Bastion SSH Ingress"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_public_ip ? ["0.0.0.0/0"] : []
  }

  egress {
    description = "Bastion Egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.bastion_tags
}

resource "aws_security_group" "bastion_ssm_vpc_endpoints" {
  count = (var.private && !var.bastion_public_ip) ? 1 : 0

  description = "Security group for SSM VPC interface endpoints"
  name        = "${var.cluster_name}-bastion-ssm-endpoints"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "HTTPS from VPC to SSM endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.bastion_tags
}

resource "aws_vpc_endpoint" "bastion_ssm" {
  count = (var.private && !var.bastion_public_ip) ? 1 : 0

  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.network.private_subnets
  security_group_ids  = [aws_security_group.bastion_ssm_vpc_endpoints[0].id]

  tags = merge(local.bastion_tags, { "Name" = "${var.cluster_name}-vpce-ssm" })
}

resource "aws_vpc_endpoint" "bastion_ssmmessages" {
  count = (var.private && !var.bastion_public_ip) ? 1 : 0

  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.network.private_subnets
  security_group_ids  = [aws_security_group.bastion_ssm_vpc_endpoints[0].id]

  tags = merge(local.bastion_tags, { "Name" = "${var.cluster_name}-vpce-ssmmessages" })
}

resource "aws_vpc_endpoint" "bastion_ec2messages" {
  count = (var.private && !var.bastion_public_ip) ? 1 : 0

  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.network.private_subnets
  security_group_ids  = [aws_security_group.bastion_ssm_vpc_endpoints[0].id]

  tags = merge(local.bastion_tags, { "Name" = "${var.cluster_name}-vpce-ec2messages" })
}

resource "aws_instance" "bastion_host" {
  count = var.private ? 1 : 0

  ami                         = data.aws_ssm_parameter.bastion_al2023_ami[0].value
  instance_type               = "t3.micro"
  iam_instance_profile        = aws_iam_instance_profile.bastion_iam_profile[0].name
  subnet_id                   = local.bastion_subnet
  associate_public_ip_address = var.bastion_public_ip
  user_data_replace_on_change = true
  key_name                    = aws_key_pair.bastion_host[0].key_name
  vpc_security_group_ids      = [aws_security_group.bastion_host[0].id]

  tags = local.bastion_tags

  user_data = <<EOF
#!/bin/bash
set -x

# Amazon Linux 2023 ships with SSM Agent preinstalled; restart to ensure registration.
sudo systemctl enable amazon-ssm-agent || true
sudo systemctl restart amazon-ssm-agent || true

# useful system packages
sudo dnf install -y wget curl python3.12 python3.12-devel net-tools gcc libffi-devel openssl-devel jq bind-utils podman || true

# openshift/kubernetes clients
wget -q https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz || true
mkdir openshift
tar -zxvf openshift-client-linux.tar.gz -C openshift || true
sudo install openshift/oc /usr/local/bin/oc || true
sudo install openshift/kubectl /usr/local/bin/kubectl || true
EOF
}
