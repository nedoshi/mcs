.PHONY: help init validate format plan apply destroy clean check

# Default environment
ENVIRONMENT ?= Development
TF_VAR_FILE ?= $(ENVIRONMENT)/dev.tfvars

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize Terraform
	@echo "Initializing Terraform..."
	terraform init

validate: ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	terraform validate

format: ## Format Terraform files
	@echo "Formatting Terraform files..."
	terraform fmt -recursive

format-check: ## Check Terraform formatting
	@echo "Checking Terraform formatting..."
	terraform fmt -check -recursive -diff

plan: init ## Run Terraform plan
	@echo "Running Terraform plan for $(ENVIRONMENT) environment..."
	terraform plan -var-file=$(TF_VAR_FILE) -out=tfplan

apply: plan ## Run Terraform apply
	@echo "Applying Terraform configuration for $(ENVIRONMENT) environment..."
	terraform apply tfplan

destroy: ## Destroy Terraform-managed infrastructure
	@echo "WARNING: This will destroy all infrastructure!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		terraform destroy -var-file=$(TF_VAR_FILE) -auto-approve; \
	fi

clean: ## Clean Terraform files
	@echo "Cleaning Terraform files..."
	rm -rf .terraform
	rm -f .terraform.lock.hcl
	rm -f tfplan
	rm -f *.tfstate
	rm -f *.tfstate.backup

check: format-check validate ## Run all checks (format and validate)

outputs: ## Show Terraform outputs
	@echo "Showing Terraform outputs..."
	terraform output

refresh: ## Refresh Terraform state
	@echo "Refreshing Terraform state..."
	terraform refresh -var-file=$(TF_VAR_FILE)

show: ## Show Terraform state
	@echo "Showing Terraform state..."
	terraform show

