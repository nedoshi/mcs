#!/bin/bash
set -e

# AKS to ARO Migration - Validate Deployment
# This script validates the ARO deployment health and functionality

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_fail() { echo -e "${RED}[✗]${NC} $1"; }

# Check required environment variables
if [ -z "$ARO_NAMESPACE" ]; then
    print_error "ARO_NAMESPACE not set"
    echo "export ARO_NAMESPACE=\"your-namespace\""
    exit 1
fi

# Validation results
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Function to run check
run_check() {
    local check_name=$1
    local check_command=$2

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo -n "Checking $check_name... "

    if eval "$check_command" > /dev/null 2>&1; then
        print_success "$check_name"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        print_fail "$check_name"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

echo "======================================="
echo "   ARO Deployment Validation Report"
echo "======================================="
echo "Namespace: $ARO_NAMESPACE"
echo "Date: $(date)"
echo ""

# 1. Cluster Connectivity
echo "1. Cluster Connectivity"
echo "-----------------------"
run_check "OpenShift CLI connectivity" "oc whoami"
run_check "Cluster version accessible" "oc get clusterversion"
echo ""

# 2. Namespace Validation
echo "2. Namespace Validation"
echo "-----------------------"
run_check "Namespace exists" "oc get project $ARO_NAMESPACE"
run_check "Namespace is active" "[ \"\$(oc project -q)\" == \"$ARO_NAMESPACE\" ]"
echo ""

# 3. Pod Health
echo "3. Pod Health"
echo "-------------"
TOTAL_PODS=$(oc get pods -n "$ARO_NAMESPACE" --no-headers 2>/dev/null | wc -l)
RUNNING_PODS=$(oc get pods -n "$ARO_NAMESPACE" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
PENDING_PODS=$(oc get pods -n "$ARO_NAMESPACE" --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
FAILED_PODS=$(oc get pods -n "$ARO_NAMESPACE" --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)

echo "Total Pods: $TOTAL_PODS"
echo "Running: $RUNNING_PODS"
echo "Pending: $PENDING_PODS"
echo "Failed: $FAILED_PODS"

if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
    print_success "All pods are running"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
elif [ "$TOTAL_PODS" -eq 0 ]; then
    print_fail "No pods found"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
else
    print_warn "Not all pods are running"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

# Show pod details if any are not running
if [ "$RUNNING_PODS" -ne "$TOTAL_PODS" ]; then
    echo ""
    echo "Pod Status Details:"
    oc get pods -n "$ARO_NAMESPACE" -o wide
fi
echo ""

# 4. Deployment Health
echo "4. Deployment Health"
echo "--------------------"
DEPLOYMENTS=$(oc get deployments -n "$ARO_NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$DEPLOYMENTS" -eq 0 ]; then
    print_warn "No deployments found"
else
    echo "Found $DEPLOYMENTS deployment(s)"

    while IFS= read -r line; do
        DEPLOY_NAME=$(echo "$line" | awk '{print $1}')
        DESIRED=$(echo "$line" | awk '{print $2}')
        READY=$(echo "$line" | awk '{print $4}')

        if [ "$DESIRED" == "$READY" ]; then
            print_success "Deployment $DEPLOY_NAME: $READY/$DESIRED ready"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
        else
            print_fail "Deployment $DEPLOY_NAME: $READY/$DESIRED ready"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    done < <(oc get deployments -n "$ARO_NAMESPACE" --no-headers 2>/dev/null)
fi
echo ""

# 5. Service Endpoints
echo "5. Service Endpoints"
echo "--------------------"
SERVICES=$(oc get svc -n "$ARO_NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$SERVICES" -eq 0 ]; then
    print_warn "No services found"
else
    echo "Found $SERVICES service(s)"

    while IFS= read -r svc_name; do
        ENDPOINTS=$(oc get endpoints "$svc_name" -n "$ARO_NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
        if [ -n "$ENDPOINTS" ]; then
            ENDPOINT_COUNT=$(echo "$ENDPOINTS" | wc -w)
            print_success "Service $svc_name has $ENDPOINT_COUNT endpoint(s)"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
        else
            print_fail "Service $svc_name has no endpoints"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    done < <(oc get svc -n "$ARO_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n')
fi
echo ""

# 6. Routes
echo "6. Routes"
echo "---------"
ROUTES=$(oc get routes -n "$ARO_NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$ROUTES" -eq 0 ]; then
    print_warn "No routes found"
else
    echo "Found $ROUTES route(s)"

    while IFS= read -r line; do
        ROUTE_NAME=$(echo "$line" | awk '{print $1}')
        ROUTE_HOST=$(echo "$line" | awk '{print $2}')

        echo "  Route: $ROUTE_NAME"
        echo "  Host: $ROUTE_HOST"

        # Test route accessibility (basic HTTP check)
        if curl -sSf -k "https://$ROUTE_HOST" -o /dev/null -w "%{http_code}" --max-time 10 2>/dev/null | grep -q "^[2-3]"; then
            print_success "Route $ROUTE_NAME is accessible"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
        else
            print_warn "Route $ROUTE_NAME may not be accessible (HTTP check failed)"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    done < <(oc get routes -n "$ARO_NAMESPACE" --no-headers 2>/dev/null)
fi
echo ""

# 7. Resource Usage
echo "7. Resource Usage"
echo "-----------------"
if oc adm top pods -n "$ARO_NAMESPACE" > /dev/null 2>&1; then
    print_success "Metrics available"
    oc adm top pods -n "$ARO_NAMESPACE"
else
    print_warn "Metrics not available (metrics server may not be running)"
fi
echo ""

# 8. ConfigMaps and Secrets
echo "8. ConfigMaps and Secrets"
echo "-------------------------"
CONFIGMAPS=$(oc get configmaps -n "$ARO_NAMESPACE" --no-headers 2>/dev/null | wc -l)
SECRETS=$(oc get secrets -n "$ARO_NAMESPACE" --no-headers 2>/dev/null | grep -v "kubernetes.io/service-account-token" | wc -l)

echo "ConfigMaps: $CONFIGMAPS"
echo "Secrets: $SECRETS"
echo ""

# 9. Recent Events
echo "9. Recent Events"
echo "----------------"
echo "Last 10 events (newest first):"
oc get events -n "$ARO_NAMESPACE" --sort-by='.lastTimestamp' | tail -10
echo ""

# 10. Application Health Checks
echo "10. Application Health Checks"
echo "------------------------------"
DEPLOYMENTS_LIST=$(oc get deployments -n "$ARO_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

for DEPLOY in $DEPLOYMENTS_LIST; do
    echo "Checking deployment: $DEPLOY"

    # Check if pods have readiness probe configured
    HAS_READINESS=$(oc get deployment "$DEPLOY" -n "$ARO_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null)
    if [ -n "$HAS_READINESS" ] && [ "$HAS_READINESS" != "null" ]; then
        print_success "Readiness probe configured for $DEPLOY"
    else
        print_warn "No readiness probe for $DEPLOY"
    fi

    # Check if pods have liveness probe configured
    HAS_LIVENESS=$(oc get deployment "$DEPLOY" -n "$ARO_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null)
    if [ -n "$HAS_LIVENESS" ] && [ "$HAS_LIVENESS" != "null" ]; then
        print_success "Liveness probe configured for $DEPLOY"
    else
        print_warn "No liveness probe for $DEPLOY"
    fi
done
echo ""

# 11. Database Connectivity (if DB_HOST is set)
if [ -n "$DB_HOST" ]; then
    echo "11. Database Connectivity"
    echo "-------------------------"

    # Create a temporary pod to test database connectivity
    print_info "Testing database connectivity to $DB_HOST..."

    if oc run db-test --image=postgres:15 --rm -i --restart=Never -n "$ARO_NAMESPACE" -- \
        bash -c "timeout 5 bash -c '</dev/tcp/$DB_HOST/5432' 2>/dev/null" > /dev/null 2>&1; then
        print_success "Database is reachable"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        print_fail "Database connectivity test failed"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo ""
fi

# Summary
echo "======================================="
echo "           Validation Summary"
echo "======================================="
echo "Total Checks: $TOTAL_CHECKS"
echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
echo ""

PASS_RATE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))

if [ "$FAILED_CHECKS" -eq 0 ]; then
    echo -e "${GREEN}✓ All validation checks passed!${NC}"
    echo ""
    echo "Deployment appears healthy and ready for production."
    exit 0
elif [ "$PASS_RATE" -ge 80 ]; then
    echo -e "${YELLOW}⚠ Some validation checks failed (${PASS_RATE}% pass rate)${NC}"
    echo ""
    echo "Review the failures above before proceeding to production."
    exit 1
else
    echo -e "${RED}✗ Multiple validation checks failed (${PASS_RATE}% pass rate)${NC}"
    echo ""
    echo "Critical issues detected. Do not proceed to production."
    exit 2
fi
