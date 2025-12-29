#!/bin/bash
# Script to troubleshoot ACS operator installation failures

set -euo pipefail

NAMESPACE="rhacs-operator"
CSV_NAME="rhacs-operator.v4.9.2"

echo "=========================================="
echo "ACS Operator Troubleshooting Diagnostic"
echo "=========================================="
echo ""

echo "1. Checking CSV Status..."
echo "-------------------------"
oc get csv "$CSV_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "CSV not found"
echo ""
oc get csv "$CSV_NAME" -n "$NAMESPACE" -o jsonpath='{.status.message}' 2>/dev/null || echo "No message"
echo ""
echo ""

echo "2. Checking Deployment Status..."
echo "--------------------------------"
oc get deployment rhacs-operator-controller-manager -n "$NAMESPACE" 2>/dev/null || echo "Deployment not found"
echo ""
oc get deployment rhacs-operator-controller-manager -n "$NAMESPACE" -o jsonpath='{.status.conditions[*].type}{"\n"}{.status.conditions[*].status}{"\n"}' 2>/dev/null || echo "No conditions"
echo ""

echo "3. Checking Pods..."
echo "-------------------"
oc get pods -n "$NAMESPACE" -l app=rhacs-operator
echo ""

echo "4. Checking Pod Status (if exists)..."
echo "--------------------------------------"
POD=$(oc get pods -n "$NAMESPACE" -l app=rhacs-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POD" ]; then
    echo "Pod: $POD"
    oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}{"\n"}{.status.containerStatuses[*].state}{"\n"}' 2>/dev/null || echo "No status"
    echo ""
    echo "Pod Events:"
    oc get events -n "$NAMESPACE" --field-selector involvedObject.name="$POD" --sort-by='.lastTimestamp' | tail -5
else
    echo "No pods found"
fi
echo ""

echo "5. Checking Recent Events..."
echo "----------------------------"
oc get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
echo ""

echo "6. Checking Subscription..."
echo "----------------------------"
oc get subscription rhacs-operator -n "$NAMESPACE" -o yaml | grep -A 10 "status:" || echo "Subscription not found"
echo ""

echo "7. Checking InstallPlan..."
echo "--------------------------"
oc get installplan -n "$NAMESPACE" -o yaml | grep -A 5 "status:" || echo "No InstallPlan found"
echo ""

echo "8. Checking Resource Quotas..."
echo "--------------------------------"
oc get resourcequota -n "$NAMESPACE" || echo "No resource quotas"
echo ""

echo "9. Checking Node Resources..."
echo "------------------------------"
echo "Node CPU/Memory usage:"
oc top nodes 2>/dev/null || echo "Metrics not available"
echo ""

echo "10. Checking CRDs..."
echo "--------------------"
oc get crd | grep stackrox || echo "No StackRox CRDs found"
echo ""

echo "11. Checking Service Account..."
echo "--------------------------------"
oc get sa rhacs-operator-controller-manager -n "$NAMESPACE" -o yaml | grep -A 5 "imagePullSecrets" || echo "ServiceAccount not found"
echo ""

echo "12. Checking for Image Pull Issues..."
echo "--------------------------------------"
if [ -n "$POD" ]; then
    oc describe pod "$POD" -n "$NAMESPACE" | grep -i "pull\|image\|error" || echo "No image pull issues found"
fi
echo ""

echo "=========================================="
echo "Diagnostic Complete"
echo "=========================================="
echo ""
echo "Common fixes:"
echo "1. Delete failed CSV: oc delete csv $CSV_NAME -n $NAMESPACE"
echo "2. Delete subscription: oc delete subscription rhacs-operator -n $NAMESPACE"
echo "3. Reinstall: oc apply -f operators/acs/subscription.yaml"
echo "4. Check pod logs: oc logs -n $NAMESPACE -l app=rhacs-operator"
echo ""

