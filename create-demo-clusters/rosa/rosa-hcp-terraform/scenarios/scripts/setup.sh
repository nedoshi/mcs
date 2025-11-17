#!/bin/bash
# Setup script for ROSA HCP Terraform deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ROSA HCP Terraform Setup${NC}"
echo -e "${GREEN}========================================${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

MISSING_TOOLS=()

if ! command_exists terraform; then
    MISSING_TOOLS+=("terraform")
fi

if ! command_exists aws; then
    MISSING_TOOLS+=("aws")
fi

if ! command_exists rosa; then
    MISSING_TOOLS+=("rosa")
fi

if ! command_exists oc; then
    MISSING_TOOLS+=("oc")
fi

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo -e "${RED}Missing required tools:${NC}"
    for tool in "${MISSING_TOOLS[@]}"; do
        echo -e "  - $tool"
    done
    echo ""
    echo "Install instructions:"
    echo "  Terraform: https://www.terraform.io/downloads"
    echo "  AWS CLI: https://aws.amazon.com/cli/"
    echo "  ROSA CLI: https://console.redhat.com/openshift/downloads"
    echo "  OC CLI: https://console.redhat.com/openshift/downloads"
    exit 1
fi

echo -e "${GREEN}✓ All required tools installed${NC}"

# Check AWS credentials
echo -e "\n${YELLOW}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}✗ AWS credentials not configured${NC}"
    echo "Run: aws configure"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
echo -e "${GREEN}✓ AWS Account: ${AWS_ACCOUNT}${NC}"
echo -e "${GREEN}✓ AWS Region: ${AWS_REGION}${NC}"

# Check ROSA login
echo -e "\n${YELLOW}Checking ROSA login...${NC}"
if ! rosa whoami &>/dev/null; then
    echo -e "${RED}✗ Not logged in to ROSA${NC}"
    echo "Get your token from: https://console.redhat.com/openshift/token"
    echo "Run: rosa login --token=<your-token>"
    exit 1
fi

ROSA_USER=$(rosa whoami | grep "AWS Account ID" | awk '{print $NF}')
echo -e "${GREEN}✓ ROSA logged in (Account: ${ROSA_USER})${NC}"

# Verify ROSA quota
echo -e "\n${YELLOW}Verifying ROSA quota...${NC}"
if ! rosa verify quota --region="${AWS_REGION}" &>/dev/null; then
    echo -e "${RED}✗ ROSA quota verification failed${NC}"
    echo "Run: rosa verify quota --region=${AWS_REGION}"
    exit 1
fi
echo -e "${GREEN}✓ ROSA quota verified${NC}"

# Check for account roles
echo -e "\n${YELLOW}Checking for ROSA account roles...${NC}"
ACCOUNT_ROLES=$(rosa list account-roles --region="${AWS_REGION}" 2>/dev/null | grep -v "^I:" | wc -l)
if [ "$ACCOUNT_ROLES" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No account roles found${NC}"
    echo "You'll need to set 'create_account_roles = true' in your terraform.tfvars"
    echo "Or create them manually with: rosa create account-roles"
else
    echo -e "${GREEN}✓ Account roles exist${NC}"
fi

# Select scenario
echo -e "\n${YELLOW}Available scenarios:${NC}"
echo "  1. Private cluster with PrivateLink"
echo "  2. Private cluster with AI/Virtualization pools"
echo "  3. Public cluster with IDP and machine pools"
echo "  4. Zero egress configuration"

read -p "Select scenario (1-4): " SCENARIO

case $SCENARIO in
    1)
        SCENARIO_DIR="${PROJECT_ROOT}/scenarios/1-private-privatelink"
        SCENARIO_NAME="Private PrivateLink"
        ;;
    2)
        SCENARIO_DIR="${PROJECT_ROOT}/scenarios/2-private-ai-virt-pools"
        SCENARIO_NAME="AI/Virtualization Pools"
        ;;
    3)
        SCENARIO_DIR="${PROJECT_ROOT}/scenarios/3-public-idp-pools"
        SCENARIO_NAME="Public with IDP"
        ;;
    4)
        SCENARIO_DIR="${PROJECT_ROOT}/scenarios/4-zero-egress"
        SCENARIO_NAME="Zero Egress"
        ;;
    *)
        echo -e "${RED}Invalid scenario${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}Selected: ${SCENARIO_NAME}${NC}"

# Check if scenario directory exists
if [ ! -d "$SCENARIO_DIR" ]; then
    echo -e "${RED}✗ Scenario directory not found: ${SCENARIO_DIR}${NC}"
    exit 1
fi

cd "$SCENARIO_DIR"

# Check for terraform.tfvars
if [ ! -f "terraform.tfvars" ]; then
    echo -e "\n${YELLOW}Creating terraform.tfvars from example...${NC}"
    if [ -f "terraform.tfvars.example" ]; then
        cp terraform.tfvars.example terraform.tfvars
        echo -e "${GREEN}✓ Created terraform.tfvars${NC}"
        echo -e "${YELLOW}Please edit terraform.tfvars with your values before proceeding${NC}"
        echo "File location: ${SCENARIO_DIR}/terraform.tfvars"
        exit 0
    else
        echo -e "${RED}✗ terraform.tfvars.example not found${NC}"
        exit 1
    fi
fi

# Initialize Terraform
echo -e "\n${YELLOW}Initializing Terraform...${NC}"
if terraform init; then
    echo -e "${GREEN}✓ Terraform initialized${NC}"
else
    echo -e "${RED}✗ Terraform initialization failed${NC}"
    exit 1
fi

# Validate configuration
echo -e "\n${YELLOW}Validating Terraform configuration...${NC}"
if terraform validate; then
    echo -e "${GREEN}✓ Configuration is valid${NC}"
else
    echo -e "${RED}✗ Configuration validation failed${NC}"
    exit 1
fi

# Run terraform plan
echo -e "\n${YELLOW}Running terraform plan...${NC}"
if terraform plan -out=tfplan; then
    echo -e "${GREEN}✓ Plan created successfully${NC}"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Setup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "To apply the configuration:"
    echo "  cd ${SCENARIO_DIR}"
    echo "  terraform apply tfplan"
    echo ""
    echo "Estimated time to complete: 40-60 minutes"
else
    echo -e "${RED}✗ Plan failed${NC}"
    exit 1
fi