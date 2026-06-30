.PHONY: init plan apply destroy validate

TFVARS ?= terraform.tfvars

init:
	terraform init

plan:
	terraform plan -var-file=$(TFVARS)

apply:
	terraform apply -var-file=$(TFVARS)

destroy:
	terraform destroy -var-file=$(TFVARS)

validate: init
	terraform validate
