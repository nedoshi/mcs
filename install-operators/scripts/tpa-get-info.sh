#!/bin/bash
# Script to get Trusted Profile Analyzer (TPA) route and connection information

set -e

NAMESPACE="${TPA_NAMESPACE:-trustification}"

echo "=========================================="
echo "Trusted Profile Analyzer (TPA)"
echo "Connection Information"
echo "=========================================="
echo ""

# Check if TPA deployment exists
if ! oc get deployment tpa-service -n "$NAMESPACE" &>/dev/null; then
    echo "❌ Error: TPA service not found in namespace '$NAMESPACE'"
    echo ""
    echo "Please ensure TPA is deployed:"
    echo "  oc get deployment tpa-service -n $NAMESPACE"
    echo ""
    echo "To install:"
    echo "  make install-tpa"
    exit 1
fi

# Check deployment status
DEPLOYMENT_READY=$(oc get deployment tpa-service -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")

if [ "$DEPLOYMENT_READY" != "True" ]; then
    echo "⚠️  Warning: TPA deployment is not ready yet"
    echo "   Status: $DEPLOYMENT_READY"
    echo ""
    echo "Please wait for TPA to be ready:"
    echo "  oc wait --for=condition=Available deployment/tpa-service -n $NAMESPACE --timeout=5m"
    echo ""
fi

# Get TPA route
ROUTE=$(oc get route tpa-service -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -z "$ROUTE" ]; then
    echo "⚠️  Warning: TPA route not found"
    echo "   Route may still be creating..."
    echo ""
    echo "Check route creation:"
    echo "  oc get route -n $NAMESPACE"
    echo ""
else
    echo "✅ TPA Dashboard URL:"
    echo "   https://$ROUTE"
    echo ""
fi

# Check TPA pods
echo "✅ TPA Pods:"
oc get pods -n "$NAMESPACE" -l app=tpa-service -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready --no-headers 2>/dev/null || echo "   No pods found"
echo ""

# Check PVCs
echo "✅ Storage (PVCs):"
oc get pvc -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,SIZE:.spec.resources.requests.storage --no-headers 2>/dev/null || echo "   No PVCs found"
echo ""

# Check service
echo "✅ Service:"
oc get svc tpa-service -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,CLUSTER-IP:.spec.clusterIP,PORT:.spec.ports[0].port --no-headers 2>/dev/null || echo "   Service not found"
echo ""

# Test API endpoint
if [ -n "$ROUTE" ]; then
    echo "✅ API Health Check:"
    if curl -k -s -o /dev/null -w "%{http_code}" "https://$ROUTE/health" 2>/dev/null | grep -q "200"; then
        echo "   Health endpoint: ✅ Healthy"
    else
        echo "   Health endpoint: ⚠️  Not responding (may still be starting)"
    fi
    echo ""
fi

echo "=========================================="
echo "Access Instructions:"
echo "=========================================="
echo ""
if [ -n "$ROUTE" ]; then
    echo "1. Access TPA Dashboard:"
    echo "   https://$ROUTE"
    echo ""
    echo "2. API Endpoints:"
    echo "   - Health: https://$ROUTE/health"
    echo "   - Ready: https://$ROUTE/ready"
    echo "   - API: https://$ROUTE/api/v1"
    echo ""
    echo "3. Example API Usage:"
    echo "   # Upload SBOM"
    echo "   curl -X POST https://$ROUTE/api/v1/sbom \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d @sbom.json"
    echo ""
    echo "   # Get vulnerabilities"
    echo "   curl https://$ROUTE/api/v1/sbom/{sbom-id}/vulnerabilities"
    echo ""
    echo "   # Get licenses"
    echo "   curl https://$ROUTE/api/v1/sbom/{sbom-id}/licenses"
    echo ""
else
    echo "1. Wait for TPA route to be created"
    echo "2. Check deployment status:"
    echo "   oc get deployment tpa-service -n $NAMESPACE"
    echo "3. Check route creation:"
    echo "   oc get route -n $NAMESPACE"
    echo "4. Once route is available, access via:"
    echo "   https://\$(oc get route tpa-service -n $NAMESPACE -o jsonpath='{.spec.host}')"
    echo ""
fi

echo "For detailed information, see:"
echo "  install-operators/docs/TPA_GUIDE.md"
echo ""

