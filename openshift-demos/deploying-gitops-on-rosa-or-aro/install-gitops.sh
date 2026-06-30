#!/bin/bash

set -euo pipefail

# Script to install OpenShift GitOps on a ROSA/ARO cluster
# Usage: install-gitops.sh <admin_username> <admin_password> <api_url>

# Validate inputs
if [ $# -lt 3 ]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 <admin_username> <admin_password> <api_url>"
    exit 1
fi

admin_username=$1
admin_password=$2
api_url=$3

# Validate that inputs are not empty
if [ -z "$admin_username" ] || [ -z "$admin_password" ] || [ -z "$api_url" ]; then
    echo "Error: All arguments must be non-empty"
    exit 1
fi

# Configuration
MAX_LOGIN_ATTEMPTS=30
LOGIN_RETRY_INTERVAL=60
LOGIN_TIMEOUT=$((MAX_LOGIN_ATTEMPTS * LOGIN_RETRY_INTERVAL))

echo "Attempting to login to OpenShift cluster..."
echo "API URL: $api_url"
echo "Max attempts: $MAX_LOGIN_ATTEMPTS (timeout: ${LOGIN_TIMEOUT}s)"

# Retry login with timeout
attempt=0
while [ $attempt -lt $MAX_LOGIN_ATTEMPTS ]; do
    attempt=$((attempt + 1))
    echo "Login attempt $attempt of $MAX_LOGIN_ATTEMPTS..."
    
    if response=$(oc login "$api_url" --username "$admin_username" --password "$admin_password" 2>&1); then
        if echo "$response" | grep -q "Login successful"; then
            echo "✓ Login successful!"
            break
        fi
    fi
    
    if [ $attempt -eq $MAX_LOGIN_ATTEMPTS ]; then
        echo "Error: Failed to login after $MAX_LOGIN_ATTEMPTS attempts"
        exit 1
    fi
    
    echo "Login failed, retrying in ${LOGIN_RETRY_INTERVAL} seconds..."
    sleep $LOGIN_RETRY_INTERVAL
done

echo "Installing OpenShift GitOps..."
if ! oc apply -f https://raw.githubusercontent.com/andyrepton/managed-openshift-demos/main/openshift-gitops/gitops-install.yaml; then
    echo "Error: Failed to apply GitOps installation manifest"
    exit 1
fi

echo "Waiting for GitOps namespace to be created..."
if ! oc wait --for=condition=Ready namespace/openshift-gitops --timeout=300s 2>/dev/null; then
    echo "Warning: Namespace may not be ready yet, continuing..."
fi

echo "Configuring GitOps route with edge reencrypt..."
if ! oc -n openshift-gitops patch argocd/openshift-gitops --type=merge -p='{"spec":{"server":{"route":{"enabled":true,"tls":{"insecureEdgeTerminationPolicy":"Redirect","termination":"reencrypt"}}}}}'; then
    echo "Error: Failed to configure GitOps route"
    exit 1
fi

echo "Waiting for GitOps to be ready..."
if ! oc wait --for=condition=Available deployment/openshift-gitops-server -n openshift-gitops --timeout=600s; then
    echo "Warning: GitOps server may not be fully ready yet"
    echo "You can check status with: oc get pods -n openshift-gitops"
else
    echo "✓ GitOps installation completed successfully!"
fi

echo ""
echo "GitOps installation complete. You can access the UI using:"
echo "  oc get route -n openshift-gitops openshift-gitops-server -o jsonpath='{.spec.host}'"
