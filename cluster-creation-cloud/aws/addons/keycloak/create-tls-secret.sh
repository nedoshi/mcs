#!/bin/bash

# Quick fix script to create the missing TLS secret for Keycloak
# This resolves the error: MountVolume.SetUp failed for volume "keycloak-tls-certificates" : secret "my-tls-secret" not found

set -e

NAMESPACE="keycloak"

echo "Creating TLS secret for Keycloak..."
echo ""

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo "Error: oc (OpenShift CLI) is not installed."
    exit 1
fi

# Check if logged in
if ! oc whoami &> /dev/null; then
    echo "Error: Not logged in to OpenShift cluster."
    exit 1
fi

# Check if secret already exists
if oc get secret my-tls-secret -n $NAMESPACE &> /dev/null; then
    echo "✅ TLS secret 'my-tls-secret' already exists in namespace '$NAMESPACE'"
    exit 0
fi

# Generate self-signed certificate
if command -v openssl &> /dev/null; then
    TEMP_DIR=$(mktemp -d)
    echo "Generating self-signed certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$TEMP_DIR/keycloak-tls.key" \
        -out "$TEMP_DIR/keycloak-tls.crt" \
        -subj "/CN=keycloak/O=keycloak" 2>/dev/null
    
    if [ -f "$TEMP_DIR/keycloak-tls.key" ] && [ -f "$TEMP_DIR/keycloak-tls.crt" ]; then
        oc create secret tls my-tls-secret \
            --cert="$TEMP_DIR/keycloak-tls.crt" \
            --key="$TEMP_DIR/keycloak-tls.key" \
            -n $NAMESPACE
        rm -rf "$TEMP_DIR"
        echo "✅ TLS secret 'my-tls-secret' created successfully in namespace '$NAMESPACE'"
        echo ""
        echo "Note: This is a self-signed certificate. For production, use proper certificates."
        echo "The Keycloak pods should now be able to start."
    else
        echo "❌ Failed to generate certificate files"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
else
    echo "❌ openssl is not available. Please install openssl or create the secret manually:"
    echo ""
    echo "To create manually:"
    echo "  1. Generate certificate:"
    echo "     openssl req -x509 -nodes -days 365 -newkey rsa:2048 \\"
    echo "       -keyout tls.key -out tls.crt -subj \"/CN=keycloak/O=keycloak\""
    echo ""
    echo "  2. Create secret:"
    echo "     oc create secret tls my-tls-secret --cert=tls.crt --key=tls.key -n $NAMESPACE"
    exit 1
fi




