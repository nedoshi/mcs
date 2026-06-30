#!/bin/bash
set -euo pipefail

# Script to create Azure resources and service principal for ARO cluster deployment
# This script should be customized with your specific values before running

# Configuration - CUSTOMIZE THESE VALUES
# ARO cluster name prefix (lowercase alphanumeric and hyphens only, max 15 chars)
RESOURCE_PREFIX="${RESOURCE_PREFIX:-aro-dev-001}"
# ARO domain (lowercase alphanumeric and hyphens only, 1-15 chars)
ARO_DOMAIN="${ARO_DOMAIN:-${RESOURCE_PREFIX}}"
# Azure location
LOCATION="${LOCATION:-canadacentral}"
# Path to Red Hat pull secret file (optional, leave empty for public clusters)
PULL_SECRET_FILE="${PULL_SECRET_FILE:-}"

# Derived values
ARO_CLUSTER_SERVICE_PRINCIPAL_DISPLAY_NAME="${RESOURCE_PREFIX}-aro-sp-${RANDOM:-$$}"
ARO_RESOURCE_GROUP_NAME="${RESOURCE_PREFIX}-RG"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Success message function
success_msg() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

# Warning message function
warning_msg() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install it from https://stedolan.github.io/jq/download/"
    fi
    
    # Check if logged in to Azure
    if ! az account show &>/dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    success_msg "Prerequisites check passed"
}

# Validate configuration
validate_config() {
    echo "Validating configuration..."
    
    if [[ ! "${RESOURCE_PREFIX}" =~ ^[a-z0-9-]{1,15}$ ]] || [[ "${RESOURCE_PREFIX}" =~ ^- ]] || [[ "${RESOURCE_PREFIX}" =~ -$ ]]; then
        error_exit "RESOURCE_PREFIX must be lowercase alphanumeric and hyphens only, max 15 characters, and cannot start or end with a hyphen."
    fi
    
    if [[ ! "${ARO_DOMAIN}" =~ ^[a-z0-9-]{1,15}$ ]] || [[ "${ARO_DOMAIN}" =~ ^- ]] || [[ "${ARO_DOMAIN}" =~ -$ ]]; then
        error_exit "ARO_DOMAIN must be lowercase alphanumeric and hyphens only, 1-15 characters, and cannot start or end with a hyphen."
    fi
    
    if [[ -n "${PULL_SECRET_FILE}" ]] && [[ ! -f "${PULL_SECRET_FILE}" ]]; then
        error_exit "Pull secret file not found: ${PULL_SECRET_FILE}"
    fi
    
    success_msg "Configuration validation passed"
}

# Get Azure subscription information
get_subscription_info() {
    echo "Getting Azure subscription information..."
    SUBSCRIPTION_ID=$(az account show --query id --output tsv) || error_exit "Failed to get subscription ID"
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv) || error_exit "Failed to get subscription name"
    TENANT_ID=$(az account show --query tenantId --output tsv) || error_exit "Failed to get tenant ID"
    
    echo "Subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    echo "Tenant: ${TENANT_ID}"
}

# Register resource providers
register_providers() {
    echo "Registering Azure resource providers..."
    
    local providers=(
        "Microsoft.RedHatOpenShift"
        "Microsoft.Compute"
        "Microsoft.Storage"
        "Microsoft.Authorization"
    )
    
    for provider in "${providers[@]}"; do
        echo "Registering ${provider}..."
        if az provider register --namespace "${provider}" --wait; then
            success_msg "${provider} registered successfully"
        else
            error_exit "Failed to register ${provider}"
        fi
    done
}

# Create resource group
create_resource_group() {
    echo "Checking if resource group [${ARO_RESOURCE_GROUP_NAME}] exists..."
    
    if az group show --name "${ARO_RESOURCE_GROUP_NAME}" &>/dev/null; then
        warning_msg "Resource group [${ARO_RESOURCE_GROUP_NAME}] already exists"
    else
        echo "Creating resource group [${ARO_RESOURCE_GROUP_NAME}] in [${LOCATION}]..."
        if az group create --name "${ARO_RESOURCE_GROUP_NAME}" --location "${LOCATION}" &>/dev/null; then
            success_msg "Resource group [${ARO_RESOURCE_GROUP_NAME}] created successfully"
        else
            error_exit "Failed to create resource group [${ARO_RESOURCE_GROUP_NAME}]"
        fi
    fi
}

# Create service principal
create_service_principal() {
    echo "Creating service principal [${ARO_CLUSTER_SERVICE_PRINCIPAL_DISPLAY_NAME}]..."
    
    local sp_file="app-service-principal.json"
    
    if az ad sp create-for-rbac --name "${ARO_CLUSTER_SERVICE_PRINCIPAL_DISPLAY_NAME}" > "${sp_file}" 2>/dev/null; then
        ARO_CLUSTER_SERVICE_PRINCIPAL_CLIENT_ID=$(jq -r '.appId' "${sp_file}") || error_exit "Failed to extract client ID"
        ARO_CLUSTER_SERVICE_PRINCIPAL_CLIENT_SECRET=$(jq -r '.password' "${sp_file}") || error_exit "Failed to extract client secret"
        ARO_CLUSTER_SERVICE_PRINCIPAL_OBJECT_ID=$(az ad sp show --id "${ARO_CLUSTER_SERVICE_PRINCIPAL_CLIENT_ID}" --query id -o tsv) || error_exit "Failed to get object ID"
        
        success_msg "Service principal created successfully"
    else
        error_exit "Failed to create service principal"
    fi
    
    # Clean up temporary file
    rm -f "${sp_file}"
}

# Assign roles to service principal
assign_roles() {
    echo "Assigning roles to service principal..."
    
    local roles=("User Access Administrator" "Contributor")
    
    for role in "${roles[@]}"; do
        echo "Assigning role [${role}]..."
        if az role assignment create \
            --role "${role}" \
            --assignee-object-id "${ARO_CLUSTER_SERVICE_PRINCIPAL_OBJECT_ID}" \
            --resource-group "${ARO_RESOURCE_GROUP_NAME}" \
            --assignee-principal-type "ServicePrincipal" &>/dev/null; then
            success_msg "Role [${role}] assigned successfully"
        else
            error_exit "Failed to assign role [${role}]"
        fi
    done
}

# Get ARO resource provider service principal
get_aro_rp_sp() {
    echo "Getting Azure Red Hat OpenShift Resource Provider service principal..."
    ARO_RESOURCE_PROVIDER_SERVICE_PRINCIPAL_OBJECT_ID=$(az ad sp list --display-name "Azure Red Hat OpenShift RP" --query "[0].id" -o tsv) || error_exit "Failed to get ARO RP service principal"
    
    if [[ -z "${ARO_RESOURCE_PROVIDER_SERVICE_PRINCIPAL_OBJECT_ID}" ]] || [[ "${ARO_RESOURCE_PROVIDER_SERVICE_PRINCIPAL_OBJECT_ID}" == "null" ]]; then
        error_exit "Azure Red Hat OpenShift Resource Provider service principal not found"
    fi
    
    success_msg "ARO RP service principal retrieved"
}

# Read pull secret
read_pull_secret() {
    if [[ -n "${PULL_SECRET_FILE}" ]] && [[ -f "${PULL_SECRET_FILE}" ]]; then
        PULL_SECRET=$(cat "${PULL_SECRET_FILE}")
        success_msg "Pull secret loaded from ${PULL_SECRET_FILE}"
    else
        PULL_SECRET=""
        warning_msg "No pull secret file provided. Cluster will be public."
    fi
}

# Generate variables_secrets file
generate_variables_file() {
    local vars_file="variables_secrets"
    
    echo "Generating ${vars_file} file..."
    
    cat > "${vars_file}" <<EOF
# IMPORTANT: This file contains sensitive information!
# Ensure this file is in .gitignore before pushing to repository
# This file is automatically generated by create.sh

## Variables for tfvars file ##

domain                        = "${ARO_DOMAIN}"
location                      = "${LOCATION}"
resource_group_name           = "${ARO_RESOURCE_GROUP_NAME}"
resource_prefix               = "${RESOURCE_PREFIX}"
virtual_network_address_space = ["10.0.0.0/22"]  # CUSTOMIZE THIS
master_subnet_address_space   = ["10.0.0.0/23"]  # CUSTOMIZE THIS
worker_subnet_address_space   = ["10.0.2.0/23"]  # CUSTOMIZE THIS

## Sensitive Terraform variables for Terraform Cloud Workspace ##

aro_cluster_aad_sp_client_id     = "${ARO_CLUSTER_SERVICE_PRINCIPAL_CLIENT_ID}"
aro_cluster_aad_sp_client_secret = "${ARO_CLUSTER_SERVICE_PRINCIPAL_CLIENT_SECRET}"
aro_cluster_aad_sp_object_id      = "${ARO_CLUSTER_SERVICE_PRINCIPAL_OBJECT_ID}"
aro_rp_aad_sp_object_id           = "${ARO_RESOURCE_PROVIDER_SERVICE_PRINCIPAL_OBJECT_ID}"
pull_secret                       = "${PULL_SECRET}"

## Environment variables for Terraform Cloud Workspace ##

ARM_CLIENT_ID     = "${ARO_CLUSTER_SERVICE_PRINCIPAL_CLIENT_ID}"
ARM_CLIENT_SECRET = "${ARO_CLUSTER_SERVICE_PRINCIPAL_CLIENT_SECRET}"
ARM_SUBSCRIPTION_ID = "${SUBSCRIPTION_ID}"
ARM_TENANT_ID     = "${TENANT_ID}"

## Secrets for GitHub repository (Settings > Secrets and variables > Actions) ##

ARM_CLIENT_ID     = "${ARO_CLUSTER_SERVICE_PRINCIPAL_CLIENT_ID}"
ARM_CLIENT_SECRET = "${ARO_CLUSTER_SERVICE_PRINCIPAL_CLIENT_SECRET}"
ARM_SUBSCRIPTION_ID = "${SUBSCRIPTION_ID}"
ARM_TENANT_ID     = "${TENANT_ID}"
EOF

    success_msg "Variables file generated: ${vars_file}"
    warning_msg "Please review and customize the network address spaces in ${vars_file}"
    warning_msg "Ensure ${vars_file} is in .gitignore before committing"
}

# Main execution
main() {
    echo "=========================================="
    echo "ARO Cluster Setup Script"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    validate_config
    get_subscription_info
    register_providers
    create_resource_group
    create_service_principal
    assign_roles
    get_aro_rp_sp
    read_pull_secret
    generate_variables_file
    
    echo ""
    echo "=========================================="
    success_msg "Setup completed successfully!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. Review and customize variables_secrets file"
    echo "2. Ensure variables_secrets is in .gitignore"
    echo "3. Set variables in Terraform Cloud workspace"
    echo "4. Set secrets in GitHub repository"
    echo "5. Update Development/dev.tfvars with your values"
    echo ""
}

# Run main function
main
