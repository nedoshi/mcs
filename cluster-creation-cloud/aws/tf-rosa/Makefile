# tf-rosa: ROSA HCP Terraform
# Auth (recommended): TF_VAR_client_id + TF_VAR_client_secret
# Auth (optional):    TF_VAR_token (or Bitwarden ocm-api-key fallback)

.PHONY: help init plan apply destroy output validate fmt test check-env cluster-private cluster-public

TFVARS ?= terraform.tfvars

help:
	@echo "ROSA HCP Terraform - tf-rosa"
	@echo ""
	@echo "Usage: make [target] [TFVARS=file.tfvars]"
	@echo ""
	@echo "Targets:"
	@echo "  init       - terraform init"
	@echo "  check-env  - verify TFVARS or RHCS credentials in environment"
	@echo "  plan       - terraform plan"
	@echo "  apply      - terraform apply"
	@echo "  destroy    - terraform destroy"
	@echo "  output     - terraform output"
	@echo "  validate   - terraform validate"
	@echo "  fmt        - terraform fmt -check -recursive"
	@echo "  test       - fmt + validate"
	@echo ""
	@echo "Auth (pick one):"
	@echo "  export TF_VAR_client_id=... TF_VAR_client_secret=...   # recommended"
	@echo "  export TF_VAR_token=...                              # optional"
	@echo ""
	@echo "Example: make plan TFVARS=examples/standard.tfvars.example"

init:
	terraform init

check-env:
	@if [ -n "$$TF_VAR_client_id" ] && [ -n "$$TF_VAR_client_secret" ]; then \
		exit 0; \
	elif [ -n "$$TF_VAR_token" ]; then \
		exit 0; \
	elif [ -f "$(TFVARS)" ]; then \
		exit 0; \
	else \
		echo "ERROR: Set TF_VAR_client_id+TF_VAR_client_secret, TF_VAR_token, or create $(TFVARS)"; \
		exit 1; \
	fi

plan: check-env
	@if [ -n "$$TF_VAR_client_id" ] && [ -n "$$TF_VAR_client_secret" ]; then \
		terraform plan -var-file=$(TFVARS) -out=terraform.tfplan; \
	else \
		export TF_VAR_token="$${TF_VAR_token:-$$(bw get password ocm-api-key 2>/dev/null)}"; \
		terraform plan -var-file=$(TFVARS) -out=terraform.tfplan; \
	fi

apply: check-env
	@if [ -n "$$TF_VAR_client_id" ] && [ -n "$$TF_VAR_client_secret" ]; then \
		terraform apply -var-file=$(TFVARS) $(ARGS); \
	else \
		export TF_VAR_token="$${TF_VAR_token:-$$(bw get password ocm-api-key 2>/dev/null)}"; \
		terraform apply -var-file=$(TFVARS) $(ARGS); \
	fi

destroy: check-env
	@if [ -n "$$TF_VAR_client_id" ] && [ -n "$$TF_VAR_client_secret" ]; then \
		terraform destroy -var-file=$(TFVARS) $(ARGS); \
	else \
		export TF_VAR_token="$${TF_VAR_token:-$$(bw get password ocm-api-key 2>/dev/null)}"; \
		terraform destroy -var-file=$(TFVARS) $(ARGS); \
	fi

output:
	terraform output $(ARGS)

validate: init
	terraform validate

fmt:
	terraform fmt -check -recursive

test: fmt validate

cluster-private:
	$(MAKE) apply TFVARS=$(TFVARS) ARGS="-var=private=true"

cluster-public:
	$(MAKE) apply TFVARS=$(TFVARS) ARGS="-var=private=false"
