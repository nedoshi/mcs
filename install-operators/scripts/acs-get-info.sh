#!/bin/bash
# Script to get ACS Central route and connection information

set -e

NAMESPACE="${ACS_NAMESPACE:-rhacs-operator}"

echo "=========================================="
echo "Red Hat Advanced Cluster Security (ACS)"
echo "Connection Information"
echo "=========================================="
echo ""

# Check if Central exists
if ! oc get central stackrox-central-services -n "$NAMESPACE" &>/dev/null; then
    echo "❌ Error: ACS Central not found in namespace '$NAMESPACE'"
    echo ""
    echo "Please ensure Central is deployed:"
    echo "  oc get central -n $NAMESPACE"
    exit 1
fi

# Check Central status
CENTRAL_STATUS=$(oc get central stackrox-central-services -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Deployed")].status}' 2>/dev/null || echo "Unknown")

if [ "$CENTRAL_STATUS" != "True" ]; then
    echo "⚠️  Warning: ACS Central is not fully deployed yet"
    echo "   Status: $CENTRAL_STATUS"
    echo ""
    echo "Please wait for Central to be ready:"
    echo "  oc wait --for=condition=Deployed central/stackrox-central-services -n $NAMESPACE --timeout=15m"
    echo ""
fi

# Get Central route
ROUTE=$(oc get route central -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -z "$ROUTE" ]; then
    echo "⚠️  Warning: ACS Central route not found"
    echo "   Central may still be deploying..."
    echo ""
else
    echo "✅ ACS Central URL:"
    echo "   https://$ROUTE"
    echo ""
fi

# Get admin password
PASSWORD=$(oc get secret central-htpasswd -n "$NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -z "$PASSWORD" ]; then
    echo "⚠️  Warning: Admin password not available yet"
    echo "   Central may still be initializing..."
    echo ""
else
    echo "✅ Default Credentials:"
    echo "   Username: admin"
    echo "   Password: $PASSWORD"
    echo ""
fi

# Get Central endpoint for SecuredCluster
CENTRAL_ENDPOINT="central.${NAMESPACE}.svc:443"
echo "✅ Central Endpoint (for SecuredCluster):"
echo "   $CENTRAL_ENDPOINT"
echo ""

# Check if SecuredCluster exists
if oc get securedcluster -n "$NAMESPACE" &>/dev/null; then
    echo "✅ SecuredCluster Status:"
    oc get securedcluster -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[?(@.type==\"Deployed\")].status,CLUSTER:.spec.clusterName --no-headers 2>/dev/null || echo "   No SecuredCluster found"
    echo ""
fi

# Get Central service status
echo "✅ Central Pods:"
oc get pods -n "$NAMESPACE" -l app=central -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready --no-headers 2>/dev/null || echo "   No pods found"
echo ""

echo "✅ Scanner Pods:"
oc get pods -n "$NAMESPACE" -l app=scanner -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready --no-headers 2>/dev/null || echo "   No pods found"
echo ""

echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo ""
echo "1. Access ACS Central UI:"
echo "   https://$ROUTE"
echo ""
echo "2. Generate Init Bundle for connecting clusters:"
echo "   - Login to ACS Central UI"
echo "   - Navigate to: Platform Configuration > Integrations > Cluster Init Bundle"
echo "   - Click 'Generate bundle' and download the YAML file"
echo ""
echo "3. Connect additional clusters:"
echo "   - Apply the init bundle to the target cluster:"
echo "     oc create -f <init-bundle>.yaml -n stackrox"
echo "   - Create SecuredCluster CR on the target cluster"
echo ""
echo "4. Get API token for CI/CD:"
echo "   - Login to ACS Central UI"
echo "   - Navigate to: Platform Configuration > Integrations > Authentication Tokens"
echo "   - Generate a new token with appropriate permissions"
echo ""
echo "For detailed instructions, see:"
echo "  install-operators/docs/ACS_CLUSTER_CONNECTION.md"
echo ""

