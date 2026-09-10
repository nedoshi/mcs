# Copy to env.sh, fill in values, then: source env.sh
# Do not commit env.sh — it may contain secrets.

export ARO_SUBSCRIPTION_ID="c5545383-1a94-45fe-b501-7ebdf43e5d7a"
export ARO_RESOURCE_GROUP="openenv-nd-aro-hcp"
export ARO_CLUSTER_NAME="nd-aro-hcp-lab"

# Red Hat Build of Keycloak
export RHBK_HOST="https://keycloak.example.com"
export EXTERNAL_AUTH_NAME="aro-hcp-auth"

# MOBB lab tagging (apply on cluster RG during provision)
# app-code=MOBB-001, cost-center=468, service-phase=lab

# After admin credential script runs:
# export KUBECONFIG="$(pwd)/aro-cluster.kubeconfig"

# API version — update when Microsoft publishes GA
export FRONTEND_API_VERSION="2024-06-10-preview"
