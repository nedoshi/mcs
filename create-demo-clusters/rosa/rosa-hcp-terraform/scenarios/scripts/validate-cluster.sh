#!/bin/bash
# Validate ROSA HCP cluster deployment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ROSA HCP Cluster Validation${NC}"
echo -e "${GREEN}========================================${NC}"

# Get cluster info from terraform
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null)
CLUSTER_API=$(terraform output -raw cluster_api_url 2>/dev/null)
CLUSTER_CONSOLE=$(terraform output -raw cluster_console_url 2>/dev/null)

if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}✗ Cannot find cluster information${NC}"
    echo "Make sure you're in a scenario directory with deployed cluster"
    exit 1
fi

echo -e "\nCluster: ${CLUSTER_NAME}"
echo -e "API: ${CLUSTER_API}"
echo -e "Console: ${CLUSTER_CONSOLE}"

# Check cluster status
echo -e "\n${YELLOW}Checking cluster status...${NC}"
CLUSTER_STATE=$(rosa describe cluster --cluster="$CLUSTER_NAME" --output json | jq -r '.state')

if [ "$CLUSTER_STATE" == "ready" ]; then
    echo -e "${GREEN}✓ Cluster is ready${NC}"
else
    echo -e "${YELLOW}⚠ Cluster state: ${CLUSTER_STATE}${NC}"
fi

# Check if logged in to cluster
echo -e "\n${YELLOW}Checking cluster connectivity...${NC}"
if oc whoami &>/dev/null; then
    CURRENT_USER=$(oc whoami)
    echo -e "${GREEN}✓ Logged in as: ${CURRENT_USER}${NC}"
    
    # Check nodes
    echo -e "\n${YELLOW}Checking nodes...${NC}"
    NODE_COUNT=$(oc get nodes --no-headers | wc -l)
    READY_NODES=$(oc get nodes --no-headers | grep " Ready" | wc -l)
    echo -e "${GREEN}✓ Nodes: ${READY_NODES}/${NODE_COUNT} ready${NC}"
    
    # Check cluster operators
    echo -e "\n${YELLOW}Checking cluster operators...${NC}"
    DEGRADED_OPS=$(oc get co --no-headers | grep -v "True.*False.*False" | wc -l)
    if [ "$DEGRADED_OPS" -eq 0 ]; then
        echo -e "${GREEN}✓ All cluster operators healthy${NC}"
    else
        echo -e "${RED}✗ ${DEGRADED_OPS} cluster operators degraded${NC}"
        oc get co | grep -v "True.*False.*False"
    fi
    
    # Check machine pools
    echo -e "\n${YELLOW}Checking machine pools...${NC}"
    oc get machinepools -n openshift-machine-api 2>/dev/null || echo "No machine pools API available"
    
else
    echo -e "${YELLOW}⚠ Not logged in to cluster${NC}"
    echo "Login with: oc login ${CLUSTER_API}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Validation Complete${NC}"
echo -e "${GREEN}========================================${NC}"