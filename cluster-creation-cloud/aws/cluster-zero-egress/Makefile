# tf-rosa-hcp-zero-egress
# ROSA HCP cluster with zero egress (VPC endpoints only).

.PHONY: help init plan apply destroy validate

TFVARS ?= terraform.tfvars

help:
	@echo "ROSA HCP Zero Egress"
	@echo "  make init plan apply destroy validate [TFVARS=file.tfvars]"
	@echo "  Set TF_VAR_token or use: export TF_VAR_token=\$$(bw get password ocm-api-key)"

init:
	terraform init

plan:
	terraform plan -var-file=$(TFVARS)

apply:
	terraform apply -var-file=$(TFVARS)

destroy:
	terraform destroy -var-file=$(TFVARS)

validate:
	terraform init -backend=false
	terraform validate
