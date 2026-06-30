# tf-rosa-idp-terraform-cloud-setup
# Azure AD OIDC identity provider for ROSA; Terraform Cloud backend.

.PHONY: help init plan apply destroy validate

TFVARS ?= terraform.tfvars

help:
	@echo "ROSA IDP (Azure AD) + Terraform Cloud"
	@echo "  make init plan apply destroy validate [TFVARS=file.tfvars]"
	@echo "  Set TF_TOKEN_app_terraform_io and TF_VAR_token (or client_id/client_secret)."

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
