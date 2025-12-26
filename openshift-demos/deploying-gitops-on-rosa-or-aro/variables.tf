variable admin_username {
  description = "OpenShift cluster admin username"
  type        = string
}

variable admin_password {
  description = "OpenShift cluster admin password"
  type        = string
  sensitive   = true
}

variable cluster_name {
  description = "Name of the ROSA/ARO cluster"
  type        = string
}

variable default_aws_tags {
  description = "Default tags to apply to AWS resources"
  type        = map(string)
}

variable aws_region {
  description = "AWS region where the cluster will be deployed"
  type        = string
}
