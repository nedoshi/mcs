variable "cluster_name" {
  description = "Name of the cluster (used as prefix for all bastion resources)"
  type        = string
}

variable "region" {
  description = "AWS region where the bastion will be deployed"
  type        = string
}

variable "private" {
  description = "Set to true to deploy a truly private bastion (no public IP + SSM-only access). false = traditional public bastion with direct SSH."
  type        = bool
  default     = true
}

variable "bastion_public_ip" {
  description = "Only matters when var.private = true. If true → bastion in private subnet but still gets a public IP (useful as a fallback). If false → fully private, no public IP, SSM-only."
  type        = bool
  default     = false
}

variable "bastion_public_ssh_key" {
  description = "Path to your public SSH key (e.g. ~/.ssh/id_rsa.pub). Required even in fully private mode in case you ever enable direct SSH."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR of the VPC – used in the sshuttle command in output"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all bastion resources"
  type        = map(string)
  default     = {}
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed to SSH to the bastion (only used when a public IP is assigned). Defaults to your current IP if null."
  type        = list(string)
  default     = null
}

# The network module is assumed to output these
variable "network" {
  description = "Object from the network module containing vpc_id, public_subnet_ids, private_subnet_ids"
  type = object({
    vpc_id             = string
    public_subnet_ids  = list(string)
    private_subnet_ids = list(string)
  })
}

# Optional: override instance type (defaults to t3.micro)
variable "bastion_instance_type" {
  description = "EC2 instance type for the bastion host"
  type        = string
  default     = "t3.micro"
}
