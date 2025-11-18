#!/bin/bash
# Cleanup script for ROSA HCP clusters

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}========================================${NC}"
echo -e "${RED}ROSA HCP Cluster Cleanup${NC}"
echo -e "${RED}========================================${NC}"

# Warning
echo -e "\n${YELLOW}⚠️  WARNING ⚠️${NC}"
echo "This script will:"
echo "  - Delete the ROSA cluster"
echo "  - Delete all AWS resources (VPC, subnets, etc.)"
echo "  - Delete all data (backups not included)"
echo ""
echo -e "${RED}This action cannot be undone!${NC}"
echo ""

read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

# Select scenario
echo -e "\n${YELLOW}Which scenario to clean up?${NC}"
echo "  1. Private cluster with PrivateLink"
echo "  2. Private cluster with AI/Virtualization pools"
echo "  3. Public cluster with IDP and machine pools"
echo "  4. Zero egress configuration"

read -p "Select scenario (1-4): " SCENARIO

case $SCENARIO in
    1)
        SCENARIO_DIR="${PROJECT_ROOT}/scenarios/1-private-privatelink"
        ;;
    2)
        SCENARIO_DIR="${PROJECT_ROOT}/scenarios/2-private-ai-virt-pools"
        ;;
    3)
        SCENARIO_DIR="${PROJECT_ROOT}/scenarios/3-public-idp-pools"
        ;;
    4)
        SCENARIO_DIR="${PROJECT_ROOT}/scenarios/4-zero-egress"
        ;;
    *)
        echo -e "${RED}Invalid scenario${NC}"
        exit 1
        ;;
esac

if [ ! -d "$SCENARIO_DIR" ]; then
    echo -e "${RED}Scenario directory not found: ${SCENARIO_DIR}${NC}"
    exit 1
fi

cd "$SCENARIO_DIR"

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${YELLOW}No terraform state found. Nothing to clean up.${NC}"
    exit 0
fi

# Get cluster name from state
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")

if [ -n "$CLUSTER_NAME" ]; then
    echo -e "\n${YELLOW}Found cluster: ${CLUSTER_NAME}${NC}"
    
    # Final confirmation
    echo ""
    read -p "Type the cluster name to confirm deletion: " CONFIRM_NAME
    if [ "$CONFIRM_NAME" != "$CLUSTER_NAME" ]; then
        echo -e "${RED}Cluster name doesn't match. Cleanup cancelled.${NC}"
        exit 1
    fi
fi

# Run terraform destroy
echo -e "\n${YELLOW}Running terraform destroy...${NC}"
echo "This may take 20-30 minutes..."

if terraform destroy -auto-approve; then
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Cleanup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "All resources have been deleted."
    echo ""
    echo "Note: If you created account roles, you may want to delete them:"
    echo "  rosa delete account-roles --region=<region>"
else
    echo -e "\n${RED}========================================${NC}"
    echo -e "${RED}Cleanup Failed${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Some resources may not have been deleted."
    echo "Please check the AWS console and clean up manually if needed."
    exit 1
fi