resource "aws_vpc" "cluster" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name                                      = "${var.infrastructure_name}-vpc"
    "kubernetes.io/cluster/${var.infrastructure_name}" = "shared"
  })
}

resource "aws_internet_gateway" "cluster" {
  vpc_id = aws_vpc.cluster.id

  tags = merge(var.tags, {
    Name = "${var.infrastructure_name}-igw"
  })
}

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.cluster.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name                                      = "${var.infrastructure_name}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.infrastructure_name}" = "shared"
    "kubernetes.io/role/internal-elb"         = "1"
  })
}

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.cluster.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                      = "${var.infrastructure_name}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.infrastructure_name}" = "shared"
    "kubernetes.io/role/elb"                  = "1"
  })
}

resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.infrastructure_name}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.cluster]
}

resource "aws_nat_gateway" "cluster" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.infrastructure_name}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.cluster]
}

resource "aws_route_table" "public" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.cluster.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cluster.id
  }

  tags = merge(var.tags, {
    Name = "${var.infrastructure_name}-public-rt-${var.availability_zones[count.index]}"
  })
}

resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.cluster.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.cluster[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.infrastructure_name}-private-rt-${var.availability_zones[count.index]}"
  })
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[count.index].id
}

resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

data "aws_vpc_endpoint_service" "s3" {
  count = var.create_vpc_endpoints ? 1 : 0

  service = "s3"
}

resource "aws_vpc_endpoint" "s3" {
  count = var.create_vpc_endpoints ? 1 : 0

  vpc_id            = aws_vpc.cluster.id
  service_name      = data.aws_vpc_endpoint_service.s3[0].service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(var.tags, {
    Name = "${var.infrastructure_name}-s3-endpoint"
  })
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.create_vpc_endpoints ? 1 : 0

  name        = "${var.infrastructure_name}-vpc-endpoints"
  description = "Allow HTTPS to VPC interface endpoints"
  vpc_id      = aws_vpc.cluster.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.infrastructure_name}-vpc-endpoints"
  })
}

data "aws_vpc_endpoint_service" "ec2" {
  count = var.create_vpc_endpoints ? 1 : 0

  service = "ec2"
}

resource "aws_vpc_endpoint" "ec2" {
  count = var.create_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.cluster.id
  service_name        = data.aws_vpc_endpoint_service.ec2[0].service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.infrastructure_name}-ec2-endpoint"
  })
}
