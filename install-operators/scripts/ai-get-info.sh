#!/bin/bash
# Script to get OpenShift AI dashboard route and connection information

set -e

NAMESPACE="${AI_NAMESPACE:-redhat-ods-operator}"
DASHBOARD_NAMESPACE="${DASHBOARD_NAMESPACE:-redhat-ods-applications}"

echo "=========================================="
echo "Red Hat OpenShift AI"
echo "Dashboard Connection Information"
echo "=========================================="
echo ""

# Check if DataScienceCluster exists
if ! oc get datasciencecluster default-dsc -n "$NAMESPACE" &>/dev/null; then
    echo "❌ Error: DataScienceCluster not found in namespace '$NAMESPACE'"
    echo ""
    echo "Please ensure DataScienceCluster is deployed:"
    echo "  oc get datasciencecluster -n $NAMESPACE"
    echo ""
    echo "To install:"
    echo "  make install-ai-datasciencecluster"
    exit 1
fi

# Check DataScienceCluster status
DSC_STATUS=$(oc get datasciencecluster default-dsc -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

if [ "$DSC_STATUS" != "True" ]; then
    echo "⚠️  Warning: DataScienceCluster is not ready yet"
    echo "   Status: $DSC_STATUS"
    echo ""
    echo "Please wait for DataScienceCluster to be ready:"
    echo "  oc wait --for=condition=Ready datasciencecluster/default-dsc -n $NAMESPACE --timeout=15m"
    echo ""
fi

# Get dashboard route
ROUTE=$(oc get route rhods-dashboard -n "$DASHBOARD_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -z "$ROUTE" ]; then
    echo "⚠️  Warning: AI Dashboard route not found"
    echo "   Dashboard may still be deploying..."
    echo ""
    echo "Check dashboard pods:"
    echo "  oc get pods -n $DASHBOARD_NAMESPACE -l app=odh-dashboard"
    echo ""
else
    echo "✅ OpenShift AI Dashboard URL:"
    echo "   https://$ROUTE"
    echo ""
fi

# Check dashboard component status
echo "✅ DataScienceCluster Components Status:"
oc get datasciencecluster default-dsc -n "$NAMESPACE" -o jsonpath='{range .status.components[*]}{.name}: {.phase}{"\n"}{end}' 2>/dev/null || echo "   Status not available"
echo ""

# Get dashboard pods status
echo "✅ Dashboard Pods:"
oc get pods -n "$DASHBOARD_NAMESPACE" -l app=odh-dashboard -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready --no-headers 2>/dev/null || echo "   No dashboard pods found"
echo ""

# Get workbenches status
echo "✅ Workbenches Pods:"
oc get pods -n "$DASHBOARD_NAMESPACE" -l app=notebook-controller -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready --no-headers 2>/dev/null | head -3 || echo "   No workbenches pods found"
echo ""

# Check if operator is ready
OPERATOR_READY=$(oc get csv -n "$NAMESPACE" -l operators.coreos.com/rhods-operator.redhat-ods-operator= -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
echo "✅ Operator Status: $OPERATOR_READY"
echo ""

echo "=========================================="
echo "Access Instructions:"
echo "=========================================="
echo ""
if [ -n "$ROUTE" ]; then
    echo "1. Access the Dashboard:"
    echo "   https://$ROUTE"
    echo ""
    echo "2. Login with your OpenShift credentials"
    echo ""
    echo "3. Or access via OpenShift Console:"
    echo "   - Click the application launcher (grid icon) in top-right"
    echo "   - Select 'Red Hat OpenShift AI'"
    echo ""
else
    echo "1. Wait for dashboard route to be created"
    echo "2. Check dashboard deployment:"
    echo "   oc get pods -n $DASHBOARD_NAMESPACE"
    echo "3. Once route is available, access via:"
    echo "   https://\$(oc get route rhods-dashboard -n $DASHBOARD_NAMESPACE -o jsonpath='{.spec.host}')"
    echo ""
fi

echo "For detailed information, see:"
echo "  install-operators/docs/AI_DASHBOARD_GUIDE.md"
echo ""

