#!/bin/bash
# Script to uninstall individual operators installed via Helm
# Usage: ./uninstall-operator.sh <operator-name> [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Operator configurations
declare -A OPERATOR_NAMESPACES
declare -A OPERATOR_RELEASE_NAMES
declare -A OPERATOR_SUBSCRIPTIONS
declare -A OPERATOR_OPERATORGROUPS

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

OPERATOR_SUBSCRIPTIONS[pipelines]="openshift-pipelines-operator"
OPERATOR_SUBSCRIPTIONS[rhtas]="trusted-artifact-signer-operator"
OPERATOR_SUBSCRIPTIONS[acs]="rhacs-operator"
OPERATOR_SUBSCRIPTIONS[ai]="rhods-operator"
OPERATOR_SUBSCRIPTIONS[virtualization]="kubevirt-hyperconverged"
OPERATOR_SUBSCRIPTIONS[developer-hub]="rhdh"
OPERATOR_SUBSCRIPTIONS[gitops]="openshift-gitops-operator"

OPERATOR_OPERATORGROUPS[pipelines]="pipelines-og"
OPERATOR_OPERATORGROUPS[rhtas]="rhtas-og"
OPERATOR_OPERATORGROUPS[acs]="acs-og"
OPERATOR_OPERATORGROUPS[ai]="ai-og"
OPERATOR_OPERATORGROUPS[virtualization]="virtualization-og"
OPERATOR_OPERATORGROUPS[developer-hub]="developer-hub-og"
OPERATOR_OPERATORGROUPS[gitops]="openshift-gitops-operator"

usage() {
    cat <<EOF
Usage: $0 <operator-name> [options]

Uninstall an individual operator installed via Helm.

Operators:
  pipelines          - OpenShift Pipelines Operator
  rhtas              - Red Hat Trusted Artifact Signer
  acs                - Advanced Cluster Security
  ai                 - OpenShift AI (Data Science)
  virtualization    - KubeVirt Virtualization
  developer-hub      - Developer Hub (Backstage)
  gitops             - OpenShift GitOps

Options:
  -h, --help              Show this help message
  -c, --clean-resources   Also delete subscriptions and operatorgroups
  -C, --clean-all         Delete everything including CSVs and Custom Resources
  -y, --yes               Skip confirmation prompts
  --dry-run               Show what would be deleted without deleting

Examples:
  # Uninstall pipelines operator (Helm release only)
  $0 pipelines

  # Uninstall with resource cleanup
  $0 acs -c

  # Uninstall with complete cleanup (CSVs, Custom Resources)
  $0 acs -C

  # Uninstall without prompts
  $0 pipelines -c -y
EOF
}

uninstall_operator() {
    local operator=$1
    local clean_resources=false
    local clean_all=false
    local skip_confirm=false
    local dry_run=false

    shift || true

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -c|--clean-resources)
                clean_resources=true
                shift
                ;;
            -C|--clean-all)
                clean_all=true
                clean_resources=true
                shift
                ;;
            -y|--yes)
                skip_confirm=true
                shift
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

    local namespace=${OPERATOR_NAMESPACES[$operator]}
    local release_name=${OPERATOR_RELEASE_NAMES[$operator]}
    local subscription=${OPERATOR_SUBSCRIPTIONS[$operator]}
    local operatorgroup=${OPERATOR_OPERATORGROUPS[$operator]}

    echo -e "${YELLOW}Uninstalling $operator operator...${NC}"
    echo "  Release: $release_name"
    echo "  Namespace: $namespace"
    echo "  Subscription: $subscription"
    echo "  OperatorGroup: $operatorgroup"
    echo ""

    if [[ "$dry_run" == true ]]; then
        echo -e "${YELLOW}[DRY RUN] Would execute:${NC}"
    fi

    # Confirm if not skipping
    if [[ "$skip_confirm" == false ]] && [[ "$dry_run" == false ]]; then
        if [[ "$clean_all" == true ]]; then
            echo -e "${RED}⚠️  WARNING: This will delete:${NC}"
            echo "  - Helm release"
            echo "  - Subscription"
            echo "  - OperatorGroup"
            echo "  - CSV (ClusterServiceVersion)"
            case $operator in
                acs)
                    echo "  - Central (if exists)"
                    echo "  - SecuredCluster (if exists)"
                    ;;
                ai)
                    echo "  - DataScienceCluster (if exists)"
                    ;;
                virtualization)
                    echo "  - HyperConverged (if exists)"
                    ;;
                developer-hub)
                    echo "  - Backstage (if exists)"
                    ;;
            esac
        elif [[ "$clean_resources" == true ]]; then
            echo -e "${YELLOW}⚠️  This will delete:${NC}"
            echo "  - Helm release"
            echo "  - Subscription"
            echo "  - OperatorGroup"
        else
            echo -e "${YELLOW}This will uninstall the Helm release only.${NC}"
            echo "  Use -c to also delete subscriptions and operatorgroups"
            echo "  Use -C to delete everything including CSVs and Custom Resources"
        fi
        echo ""
        read -p "Continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
        echo ""
    fi

    # Step 1: Delete Custom Resources (if clean_all)
    if [[ "$clean_all" == true ]]; then
        echo -e "${YELLOW}Step 1: Deleting Custom Resources...${NC}"
        case $operator in
            acs)
                if [[ "$dry_run" == false ]]; then
                    oc delete central stackrox-central-services -n stackrox --ignore-not-found=true 2>/dev/null || true
                    oc delete securedcluster secured-cluster -n "$namespace" --ignore-not-found=true 2>/dev/null || true
                    echo "  ✅ Deleted Central and SecuredCluster (if existed)"
                else
                    echo "  [DRY RUN] Would delete Central and SecuredCluster"
                fi
                ;;
            ai)
                if [[ "$dry_run" == false ]]; then
                    oc delete datasciencecluster default-dsc -n "$namespace" --ignore-not-found=true 2>/dev/null || true
                    echo "  ✅ Deleted DataScienceCluster (if existed)"
                else
                    echo "  [DRY RUN] Would delete DataScienceCluster"
                fi
                ;;
            virtualization)
                if [[ "$dry_run" == false ]]; then
                    oc delete hyperconverged kubevirt-hyperconverged -n "$namespace" --ignore-not-found=true 2>/dev/null || true
                    echo "  ✅ Deleted HyperConverged (if existed)"
                else
                    echo "  [DRY RUN] Would delete HyperConverged"
                fi
                ;;
            developer-hub)
                if [[ "$dry_run" == false ]]; then
                    oc delete backstage developer-hub -n "$namespace" --ignore-not-found=true 2>/dev/null || true
                    echo "  ✅ Deleted Backstage (if existed)"
                else
                    echo "  [DRY RUN] Would delete Backstage"
                fi
                ;;
        esac
        echo ""
    fi

    # Step 2: Uninstall Helm release
    echo -e "${YELLOW}Step 2: Uninstalling Helm release...${NC}"
    if [[ "$dry_run" == false ]]; then
        if helm uninstall "$release_name" --namespace "$namespace" 2>/dev/null; then
            echo -e "  ${GREEN}✅ Helm release uninstalled${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Helm release not found or already uninstalled${NC}"
        fi
    else
        echo "  [DRY RUN] Would run: helm uninstall $release_name --namespace $namespace"
    fi
    echo ""

    # Step 3: Delete resources if requested
    if [[ "$clean_resources" == true ]]; then
        echo -e "${YELLOW}Step 3: Deleting operator resources...${NC}"
        
        # Delete subscription
        if [[ "$dry_run" == false ]]; then
            if oc delete subscription "$subscription" -n "$namespace" --ignore-not-found=true 2>/dev/null; then
                echo -e "  ${GREEN}✅ Subscription deleted${NC}"
            else
                echo -e "  ${YELLOW}⚠️  Subscription not found${NC}"
            fi
        else
            echo "  [DRY RUN] Would delete subscription: $subscription"
        fi
        
        # Delete operatorgroup
        if [[ "$dry_run" == false ]]; then
            if oc delete operatorgroup "$operatorgroup" -n "$namespace" --ignore-not-found=true 2>/dev/null; then
                echo -e "  ${GREEN}✅ OperatorGroup deleted${NC}"
            else
                echo -e "  ${YELLOW}⚠️  OperatorGroup not found${NC}"
            fi
        else
            echo "  [DRY RUN] Would delete operatorgroup: $operatorgroup"
        fi
        echo ""
    fi

    # Step 4: Delete CSV if clean_all
    if [[ "$clean_all" == true ]]; then
        echo -e "${YELLOW}Step 4: Deleting ClusterServiceVersion...${NC}"
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

        if [[ "$dry_run" == false ]]; then
            if oc delete csv -n "$namespace" -l "$csv_label" --ignore-not-found=true 2>/dev/null; then
                echo -e "  ${GREEN}✅ CSV deleted${NC}"
            else
                echo -e "  ${YELLOW}⚠️  CSV not found or already deleted${NC}"
            fi
        else
            echo "  [DRY RUN] Would delete CSV with label: $csv_label"
        fi
        echo ""
    fi

    if [[ "$dry_run" == true ]]; then
        echo -e "${GREEN}Dry-run completed. No changes made.${NC}"
        exit 0
    fi

    echo -e "${GREEN}✅ $operator operator uninstalled successfully${NC}"
    echo ""
    echo "Verification:"
    echo "  helm list -n $namespace | grep $release_name || echo 'Release not found (good)'"
    echo "  oc get subscription -n $namespace | grep $subscription || echo 'Subscription not found (good)'"
    echo "  oc get operatorgroup -n $namespace | grep $operatorgroup || echo 'OperatorGroup not found (good)'"
}

# Main
if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

uninstall_operator "$@"

