# tf-rosa-private-cluster-with-public-zone
# ROSA Classic private cluster with public Route53 zone for API resolution.

.PHONY: help init plan apply destroy validate

TFVARS ?= terraform.tfvars

help:
	@echo "ROSA Private Cluster + Public Zone"
	@echo "  make init plan apply destroy validate [TFVARS=file.tfvars]"
	@echo "  Set TF_VAR_token or client_id/client_secret for RHCS."

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
