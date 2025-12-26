#!/bin/bash
# Script to get Developer Hub (Backstage) route and connection information

set -e

NAMESPACE="${BACKSTAGE_NAMESPACE:-rhdh-operator}"
BACKSTAGE_NAME="${BACKSTAGE_NAME:-developer-hub}"

echo "=========================================="
echo "Red Hat Developer Hub (Backstage)"
echo "Connection Information"
echo "=========================================="
echo ""

# Check if Backstage exists
if ! oc get backstage "$BACKSTAGE_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "❌ Error: Backstage instance '$BACKSTAGE_NAME' not found in namespace '$NAMESPACE'"
    echo ""
    echo "Please ensure Backstage is deployed:"
    echo "  oc get backstage -n $NAMESPACE"
    echo ""
    echo "To install:"
    echo "  make install-backstage"
    exit 1
fi

# Check Backstage status
BACKSTAGE_STATUS=$(oc get backstage "$BACKSTAGE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Deployed")].status}' 2>/dev/null || echo "Unknown")

if [ "$BACKSTAGE_STATUS" != "True" ]; then
    echo "⚠️  Warning: Backstage is not fully deployed yet"
    echo "   Status: $BACKSTAGE_STATUS"
    echo ""
    echo "Please wait for Backstage to be ready:"
    echo "  oc wait --for=condition=Deployed backstage/$BACKSTAGE_NAME -n $NAMESPACE --timeout=15m"
    echo ""
fi

# Get Backstage routes
echo "✅ Backstage Routes:"
echo ""

# Try to find route by label
ROUTE_BY_LABEL=$(oc get route -n "$NAMESPACE" -l app.kubernetes.io/name=backstage -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")

# Try to find route by name pattern
ROUTE_BY_NAME=$(oc get route -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="backstage-developer-hub")].spec.host}' 2>/dev/null || echo "")

# Try to find any route in namespace
ROUTE_ANY=$(oc get route -n "$NAMESPACE" -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")

# Use the first available route
ROUTE=""
if [ -n "$ROUTE_BY_LABEL" ]; then
    ROUTE="$ROUTE_BY_LABEL"
    echo "   Route (by label): https://$ROUTE"
elif [ -n "$ROUTE_BY_NAME" ]; then
    ROUTE="$ROUTE_BY_NAME"
    echo "   Route (by name): https://$ROUTE"
elif [ -n "$ROUTE_ANY" ]; then
    ROUTE="$ROUTE_ANY"
    echo "   Route: https://$ROUTE"
else
    echo "   ⚠️  No route found - Backstage may still be deploying"
    echo ""
    echo "   Check route creation:"
    echo "     oc get route -n $NAMESPACE"
    echo ""
fi

# List all routes in namespace
ALL_ROUTES=$(oc get route -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,HOST:.spec.host --no-headers 2>/dev/null || echo "")
if [ -n "$ALL_ROUTES" ]; then
    echo ""
    echo "   All routes in namespace:"
    echo "$ALL_ROUTES" | sed 's/^/     /'
fi

echo ""

# Check Backstage pods
echo "✅ Backstage Pods:"
oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=backstage -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready --no-headers 2>/dev/null || echo "   No pods found"
echo ""

# Check database pods
echo "✅ Database Pods:"
oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=postgres -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready --no-headers 2>/dev/null || echo "   No database pods found"
echo ""

# Check operator status
OPERATOR_READY=$(oc get csv -n "$NAMESPACE" -l operators.coreos.com/rhdh.rhdh-operator= -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
echo "✅ Operator Status: $OPERATOR_READY"
echo ""

# Get Backstage conditions
echo "✅ Backstage Conditions:"
oc get backstage "$BACKSTAGE_NAME" -n "$NAMESPACE" -o jsonpath='{range .status.conditions[*]}{.type}: {.status}{"\n"}{end}' 2>/dev/null || echo "   Status not available"
echo ""

echo "=========================================="
echo "Access Instructions:"
echo "=========================================="
echo ""
if [ -n "$ROUTE" ]; then
    echo "1. Access Developer Hub (Backstage):"
    echo "   https://$ROUTE"
    echo ""
    echo "2. Login with your OpenShift credentials"
    echo ""
    echo "3. Or access via OpenShift Console:"
    echo "   - Click the application launcher (grid icon) in top-right"
    echo "   - Look for 'Developer Hub' or 'Backstage'"
    echo ""
else
    echo "1. Wait for Backstage route to be created"
    echo "2. Check Backstage deployment:"
    echo "   oc get backstage $BACKSTAGE_NAME -n $NAMESPACE"
    echo "3. Check route creation:"
    echo "   oc get route -n $NAMESPACE"
    echo "4. Once route is available, access via:"
    echo "   https://\$(oc get route -n $NAMESPACE -l app.kubernetes.io/name=backstage -o jsonpath='{.items[0].spec.host}')"
    echo ""
fi

echo "For detailed information, see:"
echo "  install-operators/docs/BACKSTAGE_GUIDE.md"
echo ""

