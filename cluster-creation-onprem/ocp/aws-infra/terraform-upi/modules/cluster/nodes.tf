resource "random_id" "ignition_bucket" {
  byte_length = 4
}

resource "aws_s3_bucket" "ignition" {
  bucket = "${var.infrastructure_name}-ign-${random_id.ignition_bucket.hex}"

  tags = merge(var.tags, {
    Name = "${var.infrastructure_name}-ignition"
  })
}

resource "aws_s3_bucket_public_access_block" "ignition" {
  bucket = aws_s3_bucket.ignition.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "bootstrap_ign" {
  bucket  = aws_s3_bucket.ignition.id
  key     = "bootstrap.ign"
  content = file("${local.install_dir}/bootstrap.ign")

  depends_on = [null_resource.generate_ignition_configs]
}

resource "aws_security_group" "bootstrap" {
  name        = "${var.infrastructure_name}-bootstrap"
  description = "OpenShift bootstrap node"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name                                      = "${var.infrastructure_name}-bootstrap"
    "kubernetes.io/cluster/${var.infrastructure_name}" = "shared"
  })
}

resource "aws_vpc_security_group_ingress_rule" "bootstrap_ssh" {
  security_group_id = aws_security_group.bootstrap.id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "bootstrap_egress" {
  security_group_id = aws_security_group.bootstrap.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "bootstrap" {
  ami                  = var.rhcos_ami
  instance_type        = var.bootstrap.instance_type
  subnet_id            = var.private_subnet_ids[0]
  iam_instance_profile = var.bootstrap_instance_profile
  availability_zone    = var.availability_zones[0]

  vpc_security_group_ids = [
    aws_security_group.bootstrap.id,
    var.master_security_group_id,
  ]

  user_data = file("${local.install_dir}/bootstrap.ign")

  tags = merge(var.tags, {
    Name = "${var.infrastructure_name}-bootstrap"
  })

  depends_on = [
    null_resource.generate_ignition_configs,
    aws_s3_object.bootstrap_ign,
  ]

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "aws_instance" "master" {
  count = local.cp_count

  ami                  = var.rhcos_ami
  instance_type        = var.control_plane.instance_type
  subnet_id            = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  iam_instance_profile = var.master_instance_profile
  availability_zone    = var.availability_zones[count.index % length(var.availability_zones)]

  vpc_security_group_ids = [var.master_security_group_id]

  root_block_device {
    volume_size = var.control_plane.disk_gb
    volume_type = "gp3"
  }

  user_data = base64decode(file("${local.install_dir}/master.ign"))

  tags = merge(var.tags, {
    Name                                      = "${var.infrastructure_name}-master-${format("%02d", count.index + 1)}"
    "kubernetes.io/cluster/${var.infrastructure_name}" = "shared"
  })

  depends_on = [null_resource.generate_ignition_configs]

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "aws_lb_target_group_attachment" "bootstrap_internal_api" {
  target_group_arn = var.internal_api_tg_arn
  target_id        = aws_instance.bootstrap.private_ip
}

resource "aws_lb_target_group_attachment" "bootstrap_internal_service" {
  target_group_arn = var.internal_service_tg_arn
  target_id        = aws_instance.bootstrap.private_ip
}

resource "aws_lb_target_group_attachment" "bootstrap_external_api" {
  target_group_arn = var.external_api_tg_arn
  target_id        = aws_instance.bootstrap.private_ip
}

resource "aws_lb_target_group_attachment" "master_internal_api" {
  count = local.cp_count

  target_group_arn = var.internal_api_tg_arn
  target_id        = aws_instance.master[count.index].private_ip
}

resource "aws_lb_target_group_attachment" "master_internal_service" {
  count = local.cp_count

  target_group_arn = var.internal_service_tg_arn
  target_id        = aws_instance.master[count.index].private_ip
}

resource "aws_lb_target_group_attachment" "master_external_api" {
  count = local.cp_count

  target_group_arn = var.external_api_tg_arn
  target_id        = aws_instance.master[count.index].private_ip
}
