#!/bin/bash

# Complete deployment script for Keycloak on ROSA
# This script automates the entire deployment process

set -e

NAMESPACE="keycloak"
ROUTE_TYPE="${1:-public}"  # public or private

echo "=========================================="
echo "Keycloak Deployment Script for ROSA"
echo "=========================================="
echo ""

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo "Error: oc (OpenShift CLI) is not installed."
    echo "Please install it first: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html"
    exit 1
fi

# Check if logged in
if ! oc whoami &> /dev/null; then
    echo "Error: Not logged in to OpenShift cluster."
    echo "Please login first: oc login <your-cluster-api-url>"
    exit 1
fi

echo "✅ OpenShift CLI is installed and you are logged in"
echo "Logged in as: $(oc whoami)"
echo ""

# Step 1: Create namespace
echo "Step 1: Creating namespace..."
oc apply -f 01-namespace.yaml
echo "✅ Namespace created"
echo ""

# Step 2: Create secrets
echo "Step 2: Creating secrets..."
echo "⚠️  WARNING: Using default passwords. Please change them in production!"
oc apply -f 04-secrets.yaml
echo "✅ Secrets created"
echo ""

# Step 3: Deploy PostgreSQL
echo "Step 3: Deploying PostgreSQL..."
oc apply -f 02-postgresql.yaml
echo "Waiting for PostgreSQL to be ready..."
oc wait --for=condition=ready pod -l app=postgresql -n $NAMESPACE --timeout=300s || {
    echo "⚠️  PostgreSQL pod not ready yet. Continuing anyway..."
}
echo "✅ PostgreSQL deployed"
echo ""

# Step 4: Setup database
echo "Step 4: Setting up database..."
chmod +x setup-database.sh
./setup-database.sh
echo "✅ Database setup complete"
echo ""

# Step 5: Deploy Keycloak
echo "Step 5: Deploying Keycloak..."
oc apply -f 03-keycloak.yaml
echo "Waiting for Keycloak to be ready (this may take a few minutes)..."
oc wait --for=condition=ready pod -l app=keycloak -n $NAMESPACE --timeout=600s || {
    echo "⚠️  Keycloak pods not ready yet. They will continue starting in the background."
}
echo "✅ Keycloak deployed"
echo ""

# Step 6: Create route
echo "Step 6: Creating route ($ROUTE_TYPE)..."
if [ "$ROUTE_TYPE" == "private" ]; then
    oc apply -f 05-route-private.yaml
    echo "✅ Private route created"
else
    oc apply -f 05-route-public.yaml
    echo "✅ Public route created"
fi
echo ""

# Get route information
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo ""
echo "Namespace: $NAMESPACE"
echo ""
echo "Pods:"
oc get pods -n $NAMESPACE
echo ""
echo "Services:"
oc get svc -n $NAMESPACE
echo ""
echo "Routes:"
oc get route -n $NAMESPACE
echo ""
echo "Persistent Volume Claims:"
oc get pvc -n $NAMESPACE
echo ""

# Get Keycloak URL
KEYCLOAK_URL=$(oc get route keycloak -n $NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not available yet")
if [ "$KEYCLOAK_URL" != "Not available yet" ]; then
    echo "=========================================="
    echo "✅ Keycloak is available at:"
    echo "   https://$KEYCLOAK_URL"
    echo ""
    echo "Next steps:"
    echo "1. Access the URL above in your browser"
    echo "2. Create an admin user on first login"
    echo "3. Configure your realm and settings"
    echo ""
    echo "⚠️  IMPORTANT: Change default passwords!"
    echo "   - Update postgresql-secret"
    echo "   - Update keycloak-db-secret"
    echo "   - Restart deployments after updating secrets"
    echo "=========================================="
else
    echo "⚠️  Route not ready yet. Check status with: oc get route -n $NAMESPACE"
fi

