# AWS Configuration
aws_region         = "us-east-1"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

# Cluster Configuration
cluster_name          = "rosa-private-prod"
openshift_version     = "4.14"
replicas              = 3
compute_machine_type  = "m5.xlarge"

# VPC Configuration
create_vpc        = true
vpc_cidr          = "10.0.0.0/16"
single_nat_gateway = false  # Use one NAT per AZ for HA

# RHCS Token (from console.redhat.com/openshift/token)
rhcs_token = "eyJhbGc..."

# Account Roles (set to true only first time)
create_account_roles = false
existing_account_role_prefix = "rosa-account"  # If roles exist

# Admin User
create_admin_user = true

# Bastion Configuration
bastion_instance_type = "t3.micro"
bastion_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EA..."
bastion_allowed_cidr_blocks = ["203.0.113.0/24"]  # Your office IP

# Tags
environment = "production"
tags = {
  Owner       = "platform-team"
  CostCenter  = "engineering"
  Compliance  = "pci-dss"
}