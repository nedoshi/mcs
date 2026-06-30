#!/bin/bash
# Simple script to install operators directly using oc apply
# This avoids Kustomize and Helm chart complexity
# Usage: ./install-operator-simple.sh <operator-name>

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPERATORS_DIR="${SCRIPT_DIR}/operators"

# Operator configurations
declare -A OPERATOR_NAMESPACES
declare -A OPERATOR_SUBSCRIPTIONS
declare -A OPERATOR_CSV_LABELS

OPERATOR_NAMESPACES[pipelines]="openshift-operators"
OPERATOR_NAMESPACES[rhtas]="openshift-operators"
OPERATOR_NAMESPACES[acs]="rhacs-operator"
OPERATOR_NAMESPACES[ai]="redhat-ods-operator"
OPERATOR_NAMESPACES[virtualization]="openshift-cnv"
OPERATOR_NAMESPACES[developer-hub]="rhdh-operator"
OPERATOR_NAMESPACES[gitops]="openshift-gitops-operator"

OPERATOR_SUBSCRIPTIONS[pipelines]="openshift-pipelines-operator"
OPERATOR_SUBSCRIPTIONS[rhtas]="trusted-artifact-signer-operator"
OPERATOR_SUBSCRIPTIONS[acs]="rhacs-operator"
OPERATOR_SUBSCRIPTIONS[ai]="rhods-operator"
OPERATOR_SUBSCRIPTIONS[virtualization]="kubevirt-hyperconverged"
OPERATOR_SUBSCRIPTIONS[developer-hub]="rhdh"
OPERATOR_SUBSCRIPTIONS[gitops]="openshift-gitops-operator"

OPERATOR_CSV_LABELS[pipelines]="operators.coreos.com/openshift-pipelines-operator.openshift-operators="
OPERATOR_CSV_LABELS[rhtas]="operators.coreos.com/trusted-artifact-signer-operator.openshift-operators="
OPERATOR_CSV_LABELS[acs]="operators.coreos.com/rhacs-operator.rhacs-operator="
OPERATOR_CSV_LABELS[ai]="operators.coreos.com/rhods-operator.redhat-ods-operator="
OPERATOR_CSV_LABELS[virtualization]="operators.coreos.com/kubevirt-hyperconverged.openshift-cnv="
OPERATOR_CSV_LABELS[developer-hub]="operators.coreos.com/rhdh.rhdh-operator="
OPERATOR_CSV_LABELS[gitops]="operators.coreos.com/openshift-gitops-operator.openshift-gitops-operator="

usage() {
    cat <<EOF
Usage: $0 <operator-name> [options]

Simple operator installation using direct oc apply (no Kustomize, no Helm).

Operators:
  pipelines          - OpenShift Pipelines Operator
  rhtas              - Red Hat Trusted Artifact Signer
  acs                - Advanced Cluster Security
  ai                 - OpenShift AI (Data Science)
  virtualization    - KubeVirt Virtualization
  developer-hub      - Developer Hub (Backstage)
  gitops             - OpenShift GitOps (openshift-gitops-operator)

Options:
  -h, --help         Show this help message
  -w, --wait         Wait for operator CSV to be Succeeded (default: true)
  --no-wait          Don't wait for operator to be ready
  --timeout SECONDS  Timeout for waiting (default: 900 = 15 minutes)
  -c, --create-cr    Create Custom Resources after operator is ready
  --no-cr            Don't create Custom Resources (default)

Examples:
  # Install GitOps operator
  $0 gitops

  # Install GitOps operator without waiting
  $0 gitops --no-wait

  # Install with custom timeout
  $0 gitops --timeout 600

  # Install ACS operator and create Central CR
  $0 acs -c

  # Install AI operator and create DataScienceCluster CR
  $0 ai -c
EOF
}

install_operator() {
    local operator=$1
    local wait_for_csv=true
    local timeout=900
    local create_cr=false

    shift || true

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -w|--wait)
                wait_for_csv=true
                shift
                ;;
            --no-wait)
                wait_for_csv=false
                shift
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            -c|--create-cr)
                create_cr=true
                shift
                ;;
            --no-cr)
                create_cr=false
                shift
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                exit 1
                ;;
        esac
    done

    # Validate operator name
    if [[ -z "${OPERATOR_NAMESPACES[$operator]:-}" ]]; then
        echo -e "${RED}Error: Unknown operator '$operator'${NC}"
        echo "Available operators: ${!OPERATOR_NAMESPACES[*]}"
        exit 1
    fi

    local namespace=${OPERATOR_NAMESPACES[$operator]}
    local subscription=${OPERATOR_SUBSCRIPTIONS[$operator]}
    local csv_label=${OPERATOR_CSV_LABELS[$operator]}
    local operator_dir="${OPERATORS_DIR}/${operator}"

    # Check if operator directory exists
    if [[ ! -d "$operator_dir" ]]; then
        echo -e "${RED}Error: Operator directory not found: $operator_dir${NC}"
        echo "Available operators: $(ls -1 $OPERATORS_DIR 2>/dev/null | tr '\n' ' ' || echo 'none')"
        exit 1
    fi

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Installing $operator operator${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "  Namespace: $namespace"
    echo "  Subscription: $subscription"
    echo "  Directory: $operator_dir"
    echo ""

    # Step 1: Apply namespace
    echo -e "${YELLOW}Step 1: Creating namespace...${NC}"
    if [[ -f "${operator_dir}/namespace.yaml" ]]; then
        if oc apply -f "${operator_dir}/namespace.yaml"; then
            echo -e "${GREEN}  ✅ Namespace created${NC}"
        else
            echo -e "${YELLOW}  ⚠️  Namespace may already exist (continuing...)${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠️  namespace.yaml not found, skipping${NC}"
    fi
    echo ""

    # Step 2: Apply OperatorGroup
    echo -e "${YELLOW}Step 2: Creating OperatorGroup...${NC}"
    if [[ -f "${operator_dir}/operatorgroup.yaml" ]]; then
        if oc apply -f "${operator_dir}/operatorgroup.yaml"; then
            echo -e "${GREEN}  ✅ OperatorGroup created${NC}"
        else
            echo -e "${YELLOW}  ⚠️  OperatorGroup may already exist (continuing...)${NC}"
        fi
    else
        echo -e "${RED}  ❌ operatorgroup.yaml not found${NC}"
        exit 1
    fi
    echo ""

    # Step 3: Apply Subscription
    echo -e "${YELLOW}Step 3: Creating Subscription...${NC}"
    if [[ -f "${operator_dir}/subscription.yaml" ]]; then
        if oc apply -f "${operator_dir}/subscription.yaml"; then
            echo -e "${GREEN}  ✅ Subscription created${NC}"
        else
            echo -e "${RED}  ❌ Failed to create Subscription${NC}"
            exit 1
        fi
    else
        echo -e "${RED}  ❌ subscription.yaml not found${NC}"
        exit 1
    fi
    echo ""

    # Step 4: Wait for operator to be ready
    local operator_ready=false
    if [[ "$wait_for_csv" == true ]]; then
        echo -e "${YELLOW}Step 4: Waiting for operator to be ready...${NC}"
        echo "  This may take several minutes (timeout: ${timeout}s)"
        echo ""
        
        if oc wait --for=condition=Succeeded csv -n "$namespace" -l "$csv_label" --timeout="${timeout}s" 2>/dev/null; then
            echo -e "${GREEN}  ✅ Operator CSV is Succeeded${NC}"
            operator_ready=true
        else
            echo -e "${YELLOW}  ⚠️  Operator may still be installing${NC}"
            echo "  Check status with: oc get csv -n $namespace"
            echo "  Check subscription with: oc get subscription $subscription -n $namespace"
        fi
        echo ""
    else
        echo -e "${YELLOW}Skipping wait - operator installation in progress${NC}"
        echo "  Check status with: oc get csv -n $namespace"
        echo ""
    fi

    # Step 5: Create Custom Resources (if requested and operator is ready)
    if [[ "$create_cr" == true ]] && [[ "$operator_ready" == true ]]; then
        echo -e "${YELLOW}Step 5: Creating Custom Resources...${NC}"
        
        # Find all YAML files that are not namespace, operatorgroup, or subscription
        local cr_files=()
        for file in "${operator_dir}"/*.yaml; do
            if [[ -f "$file" ]]; then
                local filename=$(basename "$file")
                if [[ "$filename" != "namespace.yaml" ]] && \
                   [[ "$filename" != "operatorgroup.yaml" ]] && \
                   [[ "$filename" != "subscription.yaml" ]] && \
                   [[ "$filename" != "kustomization.yaml" ]]; then
                    cr_files+=("$file")
                fi
            fi
        done

        if [[ ${#cr_files[@]} -eq 0 ]]; then
            echo -e "${YELLOW}  ⚠️  No Custom Resource files found${NC}"
        else
            for cr_file in "${cr_files[@]}"; do
                local cr_name=$(basename "$cr_file")
                echo "  Creating Custom Resource from $cr_name..."
                if oc apply -f "$cr_file" 2>/dev/null; then
                    echo -e "${GREEN}    ✅ $cr_name created${NC}"
                else
                    echo -e "${YELLOW}    ⚠️  $cr_name may already exist or failed to create${NC}"
                    echo "    Check with: oc get $(oc get -f $cr_file -o jsonpath='{.kind}' 2>/dev/null || echo 'resource') -n $namespace"
                fi
            done
        fi
        echo ""
    elif [[ "$create_cr" == true ]] && [[ "$operator_ready" == false ]]; then
        echo -e "${YELLOW}Step 5: Skipping Custom Resource creation (operator not ready)${NC}"
        echo "  Wait for operator to be ready, then create CRs manually or re-run with -w flag"
        echo ""
    fi

    # Final status
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}Installation initiated successfully!${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Verify installation:"
    echo "  oc get subscription $subscription -n $namespace"
    echo "  oc get csv -n $namespace"
    echo "  oc get pods -n $namespace"
    echo ""
    
    if [[ "$wait_for_csv" == false ]]; then
        echo "To check operator status:"
        echo "  oc wait --for=condition=Succeeded csv -n $namespace -l $csv_label --timeout=15m"
    fi
}

# Main
if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

install_operator "$@"

