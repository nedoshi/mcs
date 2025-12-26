.PHONY: help generate-operators generate-overlays generate-argocd validate-csv validate-all clean install-acs-central install-acs-secured-cluster acs-info install-ai-datasciencecluster ai-info ai-route install-backstage backstage-info backstage-route install-tpa tpa-info tpa-route

# Configuration
BASE_DIR := operators
OVERLAYS_DIR := overlays
ARGOCD_DIR := argocd
ENVIRONMENTS := dev staging prod
OPERATORS := pipelines rhtas acs ai virtualization developer-hub

# Operator definitions
OPERATOR_PIPELINES_NAME := openshift-pipelines-operator
OPERATOR_PIPELINES_NAMESPACE := openshift-operators
OPERATOR_PIPELINES_SUBSCRIPTION := openshift-pipelines-operator
OPERATOR_PIPELINES_CHANNEL := stable

OPERATOR_RHTAS_NAME := trusted-artifact-signer-operator
OPERATOR_RHTAS_NAMESPACE := openshift-operators
OPERATOR_RHTAS_SUBSCRIPTION := trusted-artifact-signer-operator
OPERATOR_RHTAS_CHANNEL := stable

OPERATOR_ACS_NAME := rhacs-operator
OPERATOR_ACS_NAMESPACE := rhacs-operator
OPERATOR_ACS_SUBSCRIPTION := rhacs-operator
OPERATOR_ACS_CHANNEL := stable

OPERATOR_AI_NAME := rhods-operator
OPERATOR_AI_NAMESPACE := redhat-ods-operator
OPERATOR_AI_SUBSCRIPTION := rhods-operator
OPERATOR_AI_CHANNEL := stable

OPERATOR_VIRTUALIZATION_NAME := kubevirt-hyperconverged
OPERATOR_VIRTUALIZATION_NAMESPACE := openshift-cnv
OPERATOR_VIRTUALIZATION_SUBSCRIPTION := kubevirt-hyperconverged
OPERATOR_VIRTUALIZATION_CHANNEL := stable

OPERATOR_DEVELOPER_HUB_NAME := rhdh
OPERATOR_DEVELOPER_HUB_NAMESPACE := rhdh-operator
OPERATOR_DEVELOPER_HUB_SUBSCRIPTION := rhdh
OPERATOR_DEVELOPER_HUB_CHANNEL := fast

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "OpenShift Operators Management Makefile"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

generate-operators: ## Generate operator manifests (replaces script.sh)
	@echo "➡️  Generating operator manifests..."
	@mkdir -p $(BASE_DIR)
	@$(MAKE) generate-operator-pipelines
	@$(MAKE) generate-operator-rhtas
	@$(MAKE) generate-operator-acs
	@$(MAKE) generate-operator-ai
	@$(MAKE) generate-operator-virtualization
	@$(MAKE) generate-operator-developer-hub
	@$(MAKE) generate-kustomization
	@echo "✅ Operator GitOps structure created successfully"

generate-operator-pipelines:
	@echo "  Creating pipelines operator"
	@mkdir -p $(BASE_DIR)/pipelines
	@printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: %s\n' $(OPERATOR_PIPELINES_NAMESPACE) > $(BASE_DIR)/pipelines/namespace.yaml
	@printf 'apiVersion: operators.coreos.com/v1\nkind: OperatorGroup\nmetadata:\n  name: pipelines-og\n  namespace: %s\nspec:\n  targetNamespaces:\n  - %s\n' $(OPERATOR_PIPELINES_NAMESPACE) $(OPERATOR_PIPELINES_NAMESPACE) > $(BASE_DIR)/pipelines/operatorgroup.yaml
	@printf 'apiVersion: operators.coreos.com/v1alpha1\nkind: Subscription\nmetadata:\n  name: %s\n  namespace: %s\nspec:\n  channel: %s\n  name: %s\n  source: redhat-operators\n  sourceNamespace: openshift-marketplace\n' $(OPERATOR_PIPELINES_SUBSCRIPTION) $(OPERATOR_PIPELINES_NAMESPACE) $(OPERATOR_PIPELINES_CHANNEL) $(OPERATOR_PIPELINES_SUBSCRIPTION) > $(BASE_DIR)/pipelines/subscription.yaml

generate-operator-rhtas:
	@echo "  Creating rhtas operator"
	@mkdir -p $(BASE_DIR)/rhtas
	@printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: %s\n' $(OPERATOR_RHTAS_NAMESPACE) > $(BASE_DIR)/rhtas/namespace.yaml
	@printf 'apiVersion: operators.coreos.com/v1\nkind: OperatorGroup\nmetadata:\n  name: rhtas-og\n  namespace: %s\nspec:\n  targetNamespaces:\n  - %s\n' $(OPERATOR_RHTAS_NAMESPACE) $(OPERATOR_RHTAS_NAMESPACE) > $(BASE_DIR)/rhtas/operatorgroup.yaml
	@printf 'apiVersion: operators.coreos.com/v1alpha1\nkind: Subscription\nmetadata:\n  name: %s\n  namespace: %s\nspec:\n  channel: %s\n  name: %s\n  source: redhat-operators\n  sourceNamespace: openshift-marketplace\n' $(OPERATOR_RHTAS_SUBSCRIPTION) $(OPERATOR_RHTAS_NAMESPACE) $(OPERATOR_RHTAS_CHANNEL) $(OPERATOR_RHTAS_SUBSCRIPTION) > $(BASE_DIR)/rhtas/subscription.yaml

generate-operator-acs:
	@echo "  Creating acs operator"
	@mkdir -p $(BASE_DIR)/acs
	@printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: %s\n' $(OPERATOR_ACS_NAMESPACE) > $(BASE_DIR)/acs/namespace.yaml
	@printf 'apiVersion: operators.coreos.com/v1\nkind: OperatorGroup\nmetadata:\n  name: acs-og\n  namespace: %s\nspec:\n  targetNamespaces:\n  - %s\n' $(OPERATOR_ACS_NAMESPACE) $(OPERATOR_ACS_NAMESPACE) > $(BASE_DIR)/acs/operatorgroup.yaml
	@printf 'apiVersion: operators.coreos.com/v1alpha1\nkind: Subscription\nmetadata:\n  name: %s\n  namespace: %s\nspec:\n  channel: %s\n  name: %s\n  source: redhat-operators\n  sourceNamespace: openshift-marketplace\n' $(OPERATOR_ACS_SUBSCRIPTION) $(OPERATOR_ACS_NAMESPACE) $(OPERATOR_ACS_CHANNEL) $(OPERATOR_ACS_SUBSCRIPTION) > $(BASE_DIR)/acs/subscription.yaml

generate-operator-ai:
	@echo "  Creating ai operator"
	@mkdir -p $(BASE_DIR)/ai
	@printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: %s\n' $(OPERATOR_AI_NAMESPACE) > $(BASE_DIR)/ai/namespace.yaml
	@printf 'apiVersion: operators.coreos.com/v1\nkind: OperatorGroup\nmetadata:\n  name: ai-og\n  namespace: %s\nspec:\n  targetNamespaces:\n  - %s\n' $(OPERATOR_AI_NAMESPACE) $(OPERATOR_AI_NAMESPACE) > $(BASE_DIR)/ai/operatorgroup.yaml
	@printf 'apiVersion: operators.coreos.com/v1alpha1\nkind: Subscription\nmetadata:\n  name: %s\n  namespace: %s\nspec:\n  channel: %s\n  name: %s\n  source: redhat-operators\n  sourceNamespace: openshift-marketplace\n' $(OPERATOR_AI_SUBSCRIPTION) $(OPERATOR_AI_NAMESPACE) $(OPERATOR_AI_CHANNEL) $(OPERATOR_AI_SUBSCRIPTION) > $(BASE_DIR)/ai/subscription.yaml

generate-operator-virtualization:
	@echo "  Creating virtualization operator"
	@mkdir -p $(BASE_DIR)/virtualization
	@printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: %s\n' $(OPERATOR_VIRTUALIZATION_NAMESPACE) > $(BASE_DIR)/virtualization/namespace.yaml
	@printf 'apiVersion: operators.coreos.com/v1\nkind: OperatorGroup\nmetadata:\n  name: virtualization-og\n  namespace: %s\nspec:\n  targetNamespaces:\n  - %s\n' $(OPERATOR_VIRTUALIZATION_NAMESPACE) $(OPERATOR_VIRTUALIZATION_NAMESPACE) > $(BASE_DIR)/virtualization/operatorgroup.yaml
	@printf 'apiVersion: operators.coreos.com/v1alpha1\nkind: Subscription\nmetadata:\n  name: %s\n  namespace: %s\nspec:\n  channel: %s\n  name: %s\n  source: redhat-operators\n  sourceNamespace: openshift-marketplace\n' $(OPERATOR_VIRTUALIZATION_SUBSCRIPTION) $(OPERATOR_VIRTUALIZATION_NAMESPACE) $(OPERATOR_VIRTUALIZATION_CHANNEL) $(OPERATOR_VIRTUALIZATION_SUBSCRIPTION) > $(BASE_DIR)/virtualization/subscription.yaml

generate-operator-developer-hub:
	@echo "  Creating developer-hub operator"
	@mkdir -p $(BASE_DIR)/developer-hub
	@printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: %s\n  labels:\n    app.kubernetes.io/name: backstage\n    managed-by: kustomize\n' $(OPERATOR_DEVELOPER_HUB_NAMESPACE) > $(BASE_DIR)/developer-hub/namespace.yaml
	@printf 'apiVersion: operators.coreos.com/v1\nkind: OperatorGroup\nmetadata:\n  name: developer-hub-og\n  namespace: %s\nspec:\n  targetNamespaces:\n  - %s\n' $(OPERATOR_DEVELOPER_HUB_NAMESPACE) $(OPERATOR_DEVELOPER_HUB_NAMESPACE) > $(BASE_DIR)/developer-hub/operatorgroup.yaml
	@printf 'apiVersion: operators.coreos.com/v1alpha1\nkind: Subscription\nmetadata:\n  name: %s\n  namespace: %s\nspec:\n  channel: %s\n  name: %s\n  source: redhat-operators\n  sourceNamespace: openshift-marketplace\n' $(OPERATOR_DEVELOPER_HUB_SUBSCRIPTION) $(OPERATOR_DEVELOPER_HUB_NAMESPACE) $(OPERATOR_DEVELOPER_HUB_CHANNEL) $(OPERATOR_DEVELOPER_HUB_SUBSCRIPTION) > $(BASE_DIR)/developer-hub/subscription.yaml

generate-kustomization:
	@printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n\nresources:\n- pipelines\n- rhtas\n- acs\n- ai\n- virtualization\n- developer-hub\n' > $(BASE_DIR)/kustomization.yaml

generate-overlays: ## Generate environment overlays (dev, staging, prod)
	@echo "➡️  Generating environment overlays..."
	@for env in $(ENVIRONMENTS); do \
		echo "  Creating overlay for $$env"; \
		mkdir -p $(OVERLAYS_DIR)/$$env; \
		$(MAKE) generate-overlay-$$env; \
	done
	@echo "✅ Environment overlays created successfully"

generate-overlay-dev:
	@printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n\nnamespace: openshift-operators-dev\n\nresources:\n- ../../operators\n\npatchesStrategicMerge:\n- patches.yaml\n\ncommonLabels:\n  environment: dev\n  managed-by: kustomize\n' > $(OVERLAYS_DIR)/dev/kustomization.yaml
	@printf '# Environment-specific patches for dev\n# Example: Override channel to fast for faster updates in dev\n---\napiVersion: operators.coreos.com/v1alpha1\nkind: Subscription\nmetadata:\n  name: openshift-pipelines-operator\n  namespace: openshift-operators\nspec:\n  channel: fast\n' > $(OVERLAYS_DIR)/dev/patches.yaml

generate-overlay-staging:
	@printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n\nnamespace: openshift-operators-staging\n\nresources:\n- ../../operators\n\npatchesStrategicMerge:\n- patches.yaml\n\ncommonLabels:\n  environment: staging\n  managed-by: kustomize\n' > $(OVERLAYS_DIR)/staging/kustomization.yaml
	@printf '# Environment-specific patches for staging\n# Example: Use stable channel for staging\n---\napiVersion: operators.coreos.com/v1alpha1\nkind: Subscription\nmetadata:\n  name: openshift-pipelines-operator\n  namespace: openshift-operators\nspec:\n  channel: stable\n' > $(OVERLAYS_DIR)/staging/patches.yaml

generate-overlay-prod:
	@printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n\nnamespace: openshift-operators-prod\n\nresources:\n- ../../operators\n\npatchesStrategicMerge:\n- patches.yaml\n\ncommonLabels:\n  environment: prod\n  managed-by: kustomize\n' > $(OVERLAYS_DIR)/prod/kustomization.yaml
	@printf '# Environment-specific patches for prod\n# Example: Use stable channel and add approval strategy\n---\napiVersion: operators.coreos.com/v1alpha1\nkind: Subscription\nmetadata:\n  name: openshift-pipelines-operator\n  namespace: openshift-operators\nspec:\n  channel: stable\n  installPlanApproval: Manual\n' > $(OVERLAYS_DIR)/prod/patches.yaml

generate-argocd: ## Generate Argo CD Application manifests
	@echo "➡️  Generating Argo CD Application manifests..."
	@mkdir -p $(ARGOCD_DIR)
	@$(MAKE) generate-argocd-app-dev
	@$(MAKE) generate-argocd-app-staging
	@$(MAKE) generate-argocd-app-prod
	@$(MAKE) generate-argocd-app-root
	@echo "✅ Argo CD Application manifests created successfully"

generate-argocd-app-dev:
	@./generate-argocd-app.sh dev $(ARGOCD_DIR)/operators-dev.yaml

generate-argocd-app-staging:
	@./generate-argocd-app.sh staging $(ARGOCD_DIR)/operators-staging.yaml

generate-argocd-app-prod:
	@./generate-argocd-app.sh prod $(ARGOCD_DIR)/operators-prod.yaml

generate-argocd-app-root:
	@printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n\nresources:\n- operators-dev.yaml\n- operators-staging.yaml\n- operators-prod.yaml\n' > $(ARGOCD_DIR)/kustomization.yaml

validate-csv: ## Validate CSV health for all operators
	@echo "➡️  Validating ClusterServiceVersion health..."
	@$(MAKE) validate-csv-pipelines
	@$(MAKE) validate-csv-rhtas
	@$(MAKE) validate-csv-acs
	@$(MAKE) validate-csv-ai
	@$(MAKE) validate-csv-virtualization
	@$(MAKE) validate-csv-developer-hub
	@echo "✅ CSV validation completed"

validate-csv-pipelines:
	@echo "  Checking pipelines operator CSV..."
	@oc get csv -n openshift-operators -l operators.coreos.com/openshift-pipelines-operator.openshift-operators= -o jsonpath='{.items[*].status.phase}' | grep -q Succeeded || (echo "❌ Pipelines CSV not in Succeeded phase" && exit 1)
	@echo "  ✅ Pipelines CSV is healthy"

validate-csv-rhtas:
	@echo "  Checking rhtas operator CSV..."
	@oc get csv -n openshift-operators -l operators.coreos.com/trusted-artifact-signer-operator.openshift-operators= -o jsonpath='{.items[*].status.phase}' | grep -q Succeeded || (echo "❌ RHTAS CSV not in Succeeded phase" && exit 1)
	@echo "  ✅ RHTAS CSV is healthy"

validate-csv-acs:
	@echo "  Checking acs operator CSV..."
	@oc get csv -n rhacs-operator -l operators.coreos.com/rhacs-operator.rhacs-operator= -o jsonpath='{.items[*].status.phase}' | grep -q Succeeded || (echo "❌ ACS CSV not in Succeeded phase" && exit 1)
	@echo "  ✅ ACS CSV is healthy"

validate-csv-ai:
	@echo "  Checking ai operator CSV..."
	@oc get csv -n redhat-ods-operator -l operators.coreos.com/rhods-operator.redhat-ods-operator= -o jsonpath='{.items[*].status.phase}' | grep -q Succeeded || (echo "❌ AI CSV not in Succeeded phase" && exit 1)
	@echo "  ✅ AI CSV is healthy"

validate-csv-virtualization:
	@echo "  Checking virtualization operator CSV..."
	@oc get csv -n openshift-cnv -l operators.coreos.com/kubevirt-hyperconverged.openshift-cnv= -o jsonpath='{.items[*].status.phase}' | grep -q Succeeded || (echo "❌ Virtualization CSV not in Succeeded phase" && exit 1)
	@echo "  ✅ Virtualization CSV is healthy"

validate-csv-developer-hub:
	@echo "  Checking developer-hub operator CSV..."
	@oc get csv -n $(OPERATOR_DEVELOPER_HUB_NAMESPACE) -l operators.coreos.com/rhdh.rhdh-operator= -o jsonpath='{.items[*].status.phase}' | grep -q Succeeded || (echo "❌ Developer Hub CSV not in Succeeded phase" && exit 1)
	@echo "  ✅ Developer Hub CSV is healthy"

validate-all: validate-csv ## Validate all operators (CSV health)
	@echo "✅ All validations passed"

validate-csv-detailed: ## Detailed CSV validation with status reporting
	@echo "➡️  Detailed CSV validation..."
	@echo ""
	@for op in pipelines rhtas acs ai virtualization developer-hub; do \
		echo "=== $$op Operator ==="; \
		$(MAKE) validate-csv-detailed-$$op || true; \
		echo ""; \
	done

validate-csv-detailed-pipelines:
	@oc get csv -n openshift-operators -l operators.coreos.com/openshift-pipelines-operator.openshift-operators= -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,REASON:.status.reason,MESSAGE:.status.message --no-headers 2>/dev/null || echo "No CSV found"

validate-csv-detailed-rhtas:
	@oc get csv -n openshift-operators -l operators.coreos.com/trusted-artifact-signer-operator.openshift-operators= -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,REASON:.status.reason,MESSAGE:.status.message --no-headers 2>/dev/null || echo "No CSV found"

validate-csv-detailed-acs:
	@oc get csv -n rhacs-operator -l operators.coreos.com/rhacs-operator.rhacs-operator= -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,REASON:.status.reason,MESSAGE:.status.message --no-headers 2>/dev/null || echo "No CSV found"

validate-csv-detailed-ai:
	@oc get csv -n redhat-ods-operator -l operators.coreos.com/rhods-operator.redhat-ods-operator= -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,REASON:.status.reason,MESSAGE:.status.message --no-headers 2>/dev/null || echo "No CSV found"

validate-csv-detailed-virtualization:
	@oc get csv -n openshift-cnv -l operators.coreos.com/kubevirt-hyperconverged.openshift-cnv= -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,REASON:.status.reason,MESSAGE:.status.message --no-headers 2>/dev/null || echo "No CSV found"

validate-csv-detailed-developer-hub:
	@oc get csv -n $(OPERATOR_DEVELOPER_HUB_NAMESPACE) -l operators.coreos.com/rhdh.rhdh-operator= -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,REASON:.status.reason,MESSAGE:.status.message --no-headers 2>/dev/null || echo "No CSV found"

build: generate-operators generate-overlays generate-argocd ## Build all manifests (operators, overlays, Argo CD)

clean: ## Clean generated files
	@echo "➡️  Cleaning generated files..."
	@rm -rf $(BASE_DIR) $(OVERLAYS_DIR) $(ARGOCD_DIR)
	@echo "✅ Clean completed"

all: build ## Build everything (default: all)

# ================================================
# ACS (Advanced Cluster Security) Targets
# ================================================

install-acs-central: ## Install ACS Central (requires operator to be installed)
	@echo "➡️  Installing ACS Central..."
	@if ! oc get csv -n $(OPERATOR_ACS_NAMESPACE) -l operators.coreos.com/rhacs-operator.rhacs-operator= -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Succeeded; then \
		echo "❌ Error: ACS Operator must be installed and in Succeeded phase first"; \
		echo "   Run: make validate-csv-acs"; \
		exit 1; \
	fi
	@oc apply -f $(BASE_DIR)/acs/central.yaml
	@echo "✅ ACS Central installation initiated"
	@echo ""
	@echo "Waiting for Central to be deployed (this may take 10-15 minutes)..."
	@oc wait --for=condition=Deployed central/stackrox-central-services -n $(OPERATOR_ACS_NAMESPACE) --timeout=15m || \
		(echo "⚠️  Warning: Central deployment may still be in progress. Check status with: oc get central -n $(OPERATOR_ACS_NAMESPACE)" && exit 0)
	@echo "✅ ACS Central deployed successfully"
	@$(MAKE) acs-info

install-acs-secured-cluster: ## Install ACS SecuredCluster (connects cluster to Central)
	@echo "➡️  Installing ACS SecuredCluster..."
	@if ! oc get central stackrox-central-services -n $(OPERATOR_ACS_NAMESPACE) -o jsonpath='{.status.conditions[?(@.type=="Deployed")].status}' 2>/dev/null | grep -q True; then \
		echo "❌ Error: ACS Central must be deployed first"; \
		echo "   Run: make install-acs-central"; \
		exit 1; \
	fi
	@oc apply -f $(BASE_DIR)/acs/secured-cluster.yaml
	@echo "✅ ACS SecuredCluster installation initiated"
	@echo ""
	@echo "Waiting for SecuredCluster to be deployed..."
	@oc wait --for=condition=Deployed securedcluster/secured-cluster -n $(OPERATOR_ACS_NAMESPACE) --timeout=10m || \
		(echo "⚠️  Warning: SecuredCluster deployment may still be in progress. Check status with: oc get securedcluster -n $(OPERATOR_ACS_NAMESPACE)" && exit 0)
	@echo "✅ ACS SecuredCluster deployed successfully"

acs-info: ## Get ACS Central route and connection information
	@./scripts/acs-get-info.sh

acs-route: ## Get ACS Central route URL
	@oc get route central -n $(OPERATOR_ACS_NAMESPACE) -o jsonpath='{.spec.host}' 2>/dev/null || echo "Route not found - Central may still be deploying"

acs-password: ## Get ACS Central admin password
	@oc get secret central-htpasswd -n $(OPERATOR_ACS_NAMESPACE) -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "Password not available - Central may still be initializing"

# ================================================
# OpenShift AI (Data Science) Targets
# ================================================

install-ai-datasciencecluster: ## Install DataScienceCluster for AI dashboard (requires operator installed)
	@echo "➡️  Installing DataScienceCluster for OpenShift AI..."
	@if ! oc get csv -n $(OPERATOR_AI_NAMESPACE) -l operators.coreos.com/rhods-operator.redhat-ods-operator= -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Succeeded; then \
		echo "❌ Error: OpenShift AI Operator must be installed and in Succeeded phase first"; \
		echo "   Run: make validate-csv-ai"; \
		exit 1; \
	fi
	@oc apply -f $(BASE_DIR)/ai/datasciencecluster.yaml
	@echo "✅ DataScienceCluster installation initiated"
	@echo ""
	@echo "Waiting for DataScienceCluster to be ready (this may take 10-15 minutes)..."
	@oc wait --for=condition=Ready datasciencecluster/default-dsc -n $(OPERATOR_AI_NAMESPACE) --timeout=15m || \
		(echo "⚠️  Warning: DataScienceCluster deployment may still be in progress. Check status with: oc get datasciencecluster -n $(OPERATOR_AI_NAMESPACE)" && exit 0)
	@echo "✅ DataScienceCluster deployed successfully"
	@echo ""
	@echo "Waiting for dashboard route to be created..."
	@for i in {1..30}; do \
		if oc get route rhods-dashboard -n redhat-ods-applications &>/dev/null; then \
			break; \
		fi; \
		echo "  Waiting for route... (attempt $$i/30)"; \
		sleep 10; \
	done
	@$(MAKE) ai-info

ai-info: ## Get OpenShift AI dashboard route and connection information
	@./scripts/ai-get-info.sh

ai-route: ## Get OpenShift AI dashboard route URL
	@oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || echo "Route not found - Dashboard may still be deploying"

# ================================================
# Developer Hub (Backstage) Targets
# ================================================

install-backstage: ## Install Backstage instance (requires operator installed)
	@echo "➡️  Installing Developer Hub (Backstage)..."
	@if ! oc get csv -n $(OPERATOR_DEVELOPER_HUB_NAMESPACE) -l operators.coreos.com/rhdh.rhdh-operator= -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Succeeded; then \
		echo "❌ Error: Developer Hub Operator must be installed and in Succeeded phase first"; \
		echo "   Run: make validate-csv-developer-hub"; \
		exit 1; \
	fi
	@oc apply -f $(BASE_DIR)/developer-hub/backstage.yaml
	@echo "✅ Backstage installation initiated"
	@echo ""
	@echo "Waiting for Backstage to be deployed (this may take 5-10 minutes)..."
	@oc wait --for=condition=Deployed backstage/developer-hub -n $(OPERATOR_DEVELOPER_HUB_NAMESPACE) --timeout=15m || \
		(echo "⚠️  Warning: Backstage deployment may still be in progress. Check status with: oc get backstage -n $(OPERATOR_DEVELOPER_HUB_NAMESPACE)" && exit 0)
	@echo "✅ Backstage deployed successfully"
	@echo ""
	@echo "Waiting for route to be created..."
	@for i in {1..30}; do \
		if oc get route -n $(OPERATOR_DEVELOPER_HUB_NAMESPACE) -l app.kubernetes.io/name=backstage &>/dev/null; then \
			break; \
		fi; \
		echo "  Waiting for route... (attempt $$i/30)"; \
		sleep 10; \
	done
	@$(MAKE) backstage-info

backstage-info: ## Get Developer Hub (Backstage) route and connection information
	@./scripts/backstage-get-info.sh

backstage-route: ## Get Developer Hub (Backstage) route URL
	@oc get route -n $(OPERATOR_DEVELOPER_HUB_NAMESPACE) -l app.kubernetes.io/name=backstage -o jsonpath='{.items[0].spec.host}' 2>/dev/null || \
	oc get route -n $(OPERATOR_DEVELOPER_HUB_NAMESPACE) -o jsonpath='{.items[0].spec.host}' 2>/dev/null || \
	echo "Route not found - Backstage may still be deploying"

# ================================================
# Trusted Profile Analyzer (TPA) Targets
# ================================================

TPA_NAMESPACE := trustification

install-tpa: ## Install Trusted Profile Analyzer (TPA) service
	@echo "➡️  Installing Trusted Profile Analyzer (TPA)..."
	@oc apply -f $(BASE_DIR)/tpa/namespace.yaml
	@echo "✅ Namespace created"
	@echo ""
	@echo "Creating PVCs for TPA storage..."
	@oc apply -f $(BASE_DIR)/tpa/pvc.yaml
	@echo "✅ PVCs created"
	@echo ""
	@echo "Waiting for PVCs to be bound..."
	@for i in {1..30}; do \
		SBOM_BOUND=$$(oc get pvc tpa-sbom-pvc -n $(TPA_NAMESPACE) -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending"); \
		VEX_BOUND=$$(oc get pvc tpa-vex-pvc -n $(TPA_NAMESPACE) -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending"); \
		if [ "$$SBOM_BOUND" = "Bound" ] && [ "$$VEX_BOUND" = "Bound" ]; then \
			echo "✅ PVCs bound successfully"; \
			break; \
		fi; \
		echo "  Waiting for PVCs... (attempt $$i/30)"; \
		sleep 5; \
	done
	@echo ""
	@echo "Deploying TPA service..."
	@oc apply -f $(BASE_DIR)/tpa/deployment.yaml
	@oc apply -f $(BASE_DIR)/tpa/service.yaml
	@oc apply -f $(BASE_DIR)/tpa/route.yaml
	@echo "✅ TPA service deployed"
	@echo ""
	@echo "Waiting for TPA deployment to be ready (this may take 2-3 minutes)..."
	@oc wait --for=condition=Available deployment/tpa-service -n $(TPA_NAMESPACE) --timeout=5m || \
		(echo "⚠️  Warning: TPA deployment may still be starting. Check status with: oc get deployment tpa-service -n $(TPA_NAMESPACE)" && exit 0)
	@echo "✅ TPA deployment ready"
	@echo ""
	@echo "Waiting for route to be created..."
	@for i in {1..20}; do \
		if oc get route tpa-service -n $(TPA_NAMESPACE) &>/dev/null; then \
			break; \
		fi; \
		echo "  Waiting for route... (attempt $$i/20)"; \
		sleep 5; \
	done
	@$(MAKE) tpa-info

tpa-info: ## Get Trusted Profile Analyzer (TPA) route and connection information
	@./scripts/tpa-get-info.sh

tpa-route: ## Get Trusted Profile Analyzer (TPA) route URL
	@oc get route tpa-service -n $(TPA_NAMESPACE) -o jsonpath='{.spec.host}' 2>/dev/null || echo "Route not found - TPA may still be deploying"
