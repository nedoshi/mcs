# MCS wrapper for rh-mobb/terraform-aro (upstream submodule)
# Terraform runs in .terraform-root/ (upstream + MCS overlays merged at prepare time)
# State is stored in this directory (terraform.tfstate), not in .terraform-root/

.DEFAULT_GOAL := help

TF_ROOT      := .terraform-root
UPSTREAM     := upstream
OVERLAYS     := overlays
TFVARS       ?= terraform.tfvars
STATE_FILE   := $(CURDIR)/terraform.tfstate
UPSTREAM_TAG ?= v2.0.0-preview

TF_ARGS := -state="$(STATE_FILE)" -var-file="$(CURDIR)/$(TFVARS)"

.PHONY: help prepare submodule-update reference-sync
.PHONY: init plan apply destroy output validate fmt test pr clean tfvars
.PHONY: create create-private create-private-noegress
.PHONY: create-managed-identity create-private-managed-identity destroy-managed-identity
.PHONY: login show_credentials

help:
	@echo "MCS terraform-aro — wrapper around rh-mobb/terraform-aro @ $(UPSTREAM_TAG)"
	@echo ""
	@echo "Usage: make [target] [TFVARS=file.tfvars]"
	@echo ""
	@echo "Setup:"
	@echo "  submodule-update  - init/update upstream/ submodule at pinned tag"
	@echo "  prepare           - merge upstream + MCS overlays into $(TF_ROOT)/"
	@echo "  tfvars            - copy terraform.tfvars.example -> terraform.tfvars"
	@echo ""
	@echo "Terraform (state: ./terraform.tfstate):"
	@echo "  init plan apply destroy output validate fmt test pr"
	@echo ""
	@echo "Upstream shortcuts (Azure CLI; subscription from az account):"
	@echo "  create | create-private | create-private-noegress"
	@echo "  create-managed-identity | create-private-managed-identity"
	@echo "  destroy-managed-identity | login | show_credentials"
	@echo ""
	@echo "Examples:"
	@echo "  make plan TFVARS=examples/mobb-lab.tfvars.example"
	@echo "  make apply TFVARS=../../cross-cloud-dr/environments/aro-primary.tfvars.example"

submodule-update:
	@if [ ! -d "$(UPSTREAM)/.git" ]; then \
		git submodule update --init --recursive "$(UPSTREAM)" 2>/dev/null || \
		git clone --depth 1 --branch "$(UPSTREAM_TAG)" https://github.com/rh-mobb/terraform-aro.git "$(UPSTREAM)"; \
	else \
		cd "$(UPSTREAM)" && git fetch --tags && git checkout "$(UPSTREAM_TAG)"; \
	fi

prepare: submodule-update
	@mkdir -p "$(TF_ROOT)"
	@rsync -a "$(UPSTREAM)/" "$(TF_ROOT)/" \
		--exclude .git \
		--exclude 'terraform.tfstate*' \
		--exclude .terraform
	@set +e; \
	for f in "$(TF_ROOT)"/*.tf; do \
		[ -f "$$f" ] && perl -pi -e 's/var\.tags/local.tags/g' "$$f"; \
	done; \
	true
	@cp "$(OVERLAYS)"/*.tf "$(TF_ROOT)/"
	@echo "Prepared $(TF_ROOT) from $(UPSTREAM_TAG) + overlays/"

init: prepare
	@cd "$(TF_ROOT)" && terraform init -upgrade

plan: init
	@cd "$(TF_ROOT)" && terraform plan $(TF_ARGS) -out="$(CURDIR)/aro.plan" $(ARGS)

apply: init
	@cd "$(TF_ROOT)" && terraform apply $(TF_ARGS) $(ARGS)

apply-plan: init
	@cd "$(TF_ROOT)" && terraform apply "$(CURDIR)/aro.plan"

destroy: init
	@cd "$(TF_ROOT)" && terraform destroy $(TF_ARGS) $(ARGS)

output: init
	@cd "$(TF_ROOT)" && terraform output -state="$(STATE_FILE)" $(ARGS)

validate: init
	@cd "$(TF_ROOT)" && terraform validate

fmt:
	@$(MAKE) prepare
	@cd "$(TF_ROOT)" && terraform fmt -check -recursive

test: init
	@cd "$(TF_ROOT)" && $(MAKE) test

pr: init
	@cd "$(TF_ROOT)" && $(MAKE) pr

clean:
	@rm -rf "$(TF_ROOT)" aro.plan test.plan

tfvars:
	@cp terraform.tfvars.example terraform.tfvars
	@echo "Edit terraform.tfvars — do not commit secrets."

# Upstream Makefile targets (symlink state so upstream login/show_credentials work)
define upstream_target
$(1): init
	@ln -sf "$(STATE_FILE)" "$(TF_ROOT)/terraform.tfstate"
	@cd "$(TF_ROOT)" && $(MAKE) $(1)
endef

$(eval $(call upstream_target,create))
$(eval $(call upstream_target,create-private))
$(eval $(call upstream_target,create-private-noegress))
$(eval $(call upstream_target,create-managed-identity))
$(eval $(call upstream_target,create-private-managed-identity))
$(eval $(call upstream_target,destroy-managed-identity))
$(eval $(call upstream_target,destroy-managed-identity.force))
$(eval $(call upstream_target,login))
$(eval $(call upstream_target,show_credentials))

reference-sync: prepare
	@if grep -q '^reference-sync:' "$(TF_ROOT)/Makefile" 2>/dev/null; then \
		cd "$(TF_ROOT)" && $(MAKE) reference-sync; \
	else \
		echo "reference-sync not required for pinned upstream $(UPSTREAM_TAG) (ARM-template managed identities)."; \
		echo "When bumping to main/AzAPI upstream, set REFERENCE_ARO_AZAPI_URL and run:"; \
		echo "  REFERENCE_ARO_AZAPI_URL=https://github.com/your-org/terraform-aro-reference-aro-azapi.git make reference-sync"; \
	fi
