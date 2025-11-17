# modules/vpc/output.tf

# VPC ID (either created or existing)
output "vpc_id" {
  description = "ID of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].id : data.aws_vpc.existing[0].id
}

# Private Subnet IDs
output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = var.create_vpc ? aws_subnet.private[*].id : data.aws_subnets.existing_private[0].ids
}

# Public Subnet IDs
output "public_subnet_ids" {
  description = "List of public subnet IDs (empty if create_public_subnets is false)"
  value       = var.create_vpc && var.create_public_subnets ? aws_subnet.public[*].id : (var.create_vpc ? [] : data.aws_subnets.existing_public[0].ids)
}

# VPC CIDR Block
output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].cidr_block : data.aws_vpc.existing[0].cidr_block
}

# NAT Gateway IDs (optional, useful for reference)
output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = var.create_vpc && var.create_public_subnets && !var.zero_egress ? aws_nat_gateway.main[*].id : []
}

# Internet Gateway ID (optional, useful for reference)
output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = var.create_vpc && var.create_public_subnets ? aws_internet_gateway.main[0].id : null
}

# Private Route Table IDs
output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = var.create_vpc ? aws_route_table.private[*].id : []
}

# Public Route Table ID
output "public_route_table_id" {
  description = "ID of the public route table"
  value       = var.create_vpc && var.create_public_subnets ? aws_route_table.public[0].id : null
}