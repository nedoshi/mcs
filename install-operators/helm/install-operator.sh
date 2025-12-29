#!/bin/bash
# Script to install individual operators using Helm charts
# Usage: ./install-operator.sh <operator-name> [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="${SCRIPT_DIR}/charts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Operator configurations
declare -A OPERATOR_NAMESPACES
declare -A OPERATOR_RELEASE_NAMES

OPERATOR_NAMESPACES[pipelines]="openshift-operators"
OPERATOR_NAMESPACES[rhtas]="openshift-operators"
OPERATOR_NAMESPACES[acs]="rhacs-operator"
OPERATOR_NAMESPACES[ai]="redhat-ods-operator"
OPERATOR_NAMESPACES[virtualization]="openshift-cnv"
OPERATOR_NAMESPACES[developer-hub]="rhdh-operator"
OPERATOR_NAMESPACES[gitops]="openshift-gitops-operator"

OPERATOR_RELEASE_NAMES[pipelines]="pipelines-operator"
OPERATOR_RELEASE_NAMES[rhtas]="rhtas-operator"
OPERATOR_RELEASE_NAMES[acs]="acs-operator"
OPERATOR_RELEASE_NAMES[ai]="ai-operator"
OPERATOR_RELEASE_NAMES[virtualization]="virtualization-operator"
OPERATOR_RELEASE_NAMES[developer-hub]="developer-hub-operator"
OPERATOR_RELEASE_NAMES[gitops]="gitops-operator"

usage() {
    cat <<EOF
Usage: $0 <operator-name> [options]

Install an individual operator using Helm charts.

Operators:
  pipelines          - OpenShift Pipelines Operator
  rhtas              - Red Hat Trusted Artifact Signer
  acs                - Advanced Cluster Security
  ai                 - OpenShift AI (Data Science)
  virtualization    - KubeVirt Virtualization
  developer-hub      - Developer Hub (Backstage)
  gitops             - OpenShift GitOps

Options:
  -h, --help         Show this help message
  -w, --wait         Wait for operator CSV to be Succeeded
  -c, --central      Enable Central for ACS (requires -w)
  -d, --dsc          Enable DataScienceCluster for AI (requires -w)
  -H, --hyperconverged  Enable HyperConverged for Virtualization (requires -w)
  -b, --backstage    Enable Backstage for Developer Hub (requires -w)
  -f, --values FILE  Use custom values file
  --dry-run          Show what would be installed without installing

Examples:
  # Install pipelines operator
  $0 pipelines

  # Install ACS operator and wait for it to be ready
  $0 acs -w

  # Install ACS operator, wait, then enable Central
  $0 acs -w -c

  # Install AI operator with DataScienceCluster
  $0 ai -w -d

  # Install with custom values file
  $0 pipelines -f my-values.yaml
EOF
}

install_operator() {
    local operator=$1
    local namespace=${OPERATOR_NAMESPACES[$operator]}
    local release_name=${OPERATOR_RELEASE_NAMES[$operator]}
    local chart_dir="${CHARTS_DIR}/${operator}"
    local wait_for_csv=false
    local enable_central=false
    local enable_dsc=false
    local enable_hyperconverged=false
    local enable_backstage=false
    local values_file=""
    local dry_run=false

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
            -c|--central)
                enable_central=true
                shift
                ;;
            -d|--dsc)
                enable_dsc=true
                shift
                ;;
            -H|--hyperconverged)
                enable_hyperconverged=true
                shift
                ;;
            -b|--backstage)
                enable_backstage=true
                shift
                ;;
            -f|--values)
                values_file="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
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

    # Check if chart directory exists
    if [[ ! -d "$chart_dir" ]]; then
        echo -e "${RED}Error: Chart directory not found: $chart_dir${NC}"
        exit 1
    fi

    echo -e "${GREEN}Installing $operator operator...${NC}"
    echo "  Namespace: $namespace"
    echo "  Release: $release_name"
    echo "  Chart: $chart_dir"

    # Build helm install command
    local helm_cmd="helm install $release_name $chart_dir"
    helm_cmd+=" --namespace $namespace"
    helm_cmd+=" --create-namespace"
    helm_cmd+=" --set namespace=$namespace"

    # Add custom values file if provided
    if [[ -n "$values_file" ]]; then
        if [[ ! -f "$values_file" ]]; then
            echo -e "${RED}Error: Values file not found: $values_file${NC}"
            exit 1
        fi
        helm_cmd+=" -f $values_file"
    fi

    # Add operator-specific options
    case $operator in
        acs)
            if [[ "$enable_central" == true ]]; then
                helm_cmd+=" --set central.enabled=true"
                helm_cmd+=" --set central.namespace=stackrox"
            fi
            ;;
        ai)
            if [[ "$enable_dsc" == true ]]; then
                helm_cmd+=" --set datasciencecluster.enabled=true"
            fi
            ;;
        virtualization)
            if [[ "$enable_hyperconverged" == true ]]; then
                helm_cmd+=" --set hyperconverged.enabled=true"
            fi
            ;;
        developer-hub)
            if [[ "$enable_backstage" == true ]]; then
                helm_cmd+=" --set backstage.enabled=true"
            fi
            ;;
    esac

    # Add dry-run if requested
    if [[ "$dry_run" == true ]]; then
        helm_cmd+=" --dry-run --debug"
    fi

    echo ""
    echo -e "${YELLOW}Running: $helm_cmd${NC}"
    echo ""

    # Execute helm install
    if ! eval "$helm_cmd"; then
        echo -e "${RED}Error: Failed to install $operator operator${NC}"
        exit 1
    fi

    if [[ "$dry_run" == true ]]; then
        echo -e "${GREEN}Dry-run completed. No changes made.${NC}"
        exit 0
    fi

    echo -e "${GREEN}✅ $operator operator installed successfully${NC}"

    # Wait for CSV if requested
    if [[ "$wait_for_csv" == true ]]; then
        echo ""
        echo -e "${YELLOW}Waiting for operator CSV to be Succeeded...${NC}"
        
        local csv_label=""
        case $operator in
            pipelines)
                csv_label="operators.coreos.com/openshift-pipelines-operator.openshift-operators="
                ;;
            rhtas)
                csv_label="operators.coreos.com/trusted-artifact-signer-operator.openshift-operators="
                ;;
            acs)
                csv_label="operators.coreos.com/rhacs-operator.rhacs-operator="
                ;;
            ai)
                csv_label="operators.coreos.com/rhods-operator.redhat-ods-operator="
                ;;
            virtualization)
                csv_label="operators.coreos.com/kubevirt-hyperconverged.openshift-cnv="
                ;;
            developer-hub)
                csv_label="operators.coreos.com/rhdh.rhdh-operator="
                ;;
            gitops)
                csv_label="operators.coreos.com/openshift-gitops-operator.openshift-gitops-operator="
                ;;
        esac

        if oc wait --for=condition=Succeeded csv -n "$namespace" -l "$csv_label" --timeout=15m; then
            echo -e "${GREEN}✅ Operator CSV is Succeeded${NC}"
            
            # Enable Custom Resources if requested
            if [[ "$enable_central" == true ]] && [[ "$operator" == "acs" ]]; then
                echo ""
                echo -e "${YELLOW}Enabling Central...${NC}"
                helm upgrade "$release_name" "$chart_dir" \
                    --namespace "$namespace" \
                    --set central.enabled=true \
                    --set central.namespace=stackrox
                echo -e "${GREEN}✅ Central enabled${NC}"
            fi
            
            if [[ "$enable_dsc" == true ]] && [[ "$operator" == "ai" ]]; then
                echo ""
                echo -e "${YELLOW}Enabling DataScienceCluster...${NC}"
                helm upgrade "$release_name" "$chart_dir" \
                    --namespace "$namespace" \
                    --set datasciencecluster.enabled=true
                echo -e "${GREEN}✅ DataScienceCluster enabled${NC}"
            fi
            
            if [[ "$enable_hyperconverged" == true ]] && [[ "$operator" == "virtualization" ]]; then
                echo ""
                echo -e "${YELLOW}Enabling HyperConverged...${NC}"
                helm upgrade "$release_name" "$chart_dir" \
                    --namespace "$namespace" \
                    --set hyperconverged.enabled=true
                echo -e "${GREEN}✅ HyperConverged enabled${NC}"
            fi
            
            if [[ "$enable_backstage" == true ]] && [[ "$operator" == "developer-hub" ]]; then
                echo ""
                echo -e "${YELLOW}Enabling Backstage...${NC}"
                helm upgrade "$release_name" "$chart_dir" \
                    --namespace "$namespace" \
                    --set backstage.enabled=true
                echo -e "${GREEN}✅ Backstage enabled${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Warning: CSV may still be installing. Check with: oc get csv -n $namespace${NC}"
        fi
    fi

    echo ""
    echo -e "${GREEN}Installation complete!${NC}"
    echo ""
    echo "Verify installation:"
    echo "  oc get subscription -n $namespace"
    echo "  oc get csv -n $namespace"
    echo "  oc get pods -n $namespace"
}

# Main
if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

install_operator "$@"

