#!/bin/bash
set -e

# AKS to ARO Migration - Convert Manifests
# This script converts AKS Kubernetes manifests to ARO/OpenShift compatible format

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Load latest export directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATION_DIR="${MIGRATION_DIR:-$(dirname "$SCRIPT_DIR")}"

if [ -f "$MIGRATION_DIR/exports/latest-export.env" ]; then
    source "$MIGRATION_DIR/exports/latest-export.env"
    print_info "Using export directory: $AKS_EXPORT_DIR"
else
    print_error "No export found. Run 01-export-aks-resources.sh first"
    exit 1
fi

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    print_warn "yq not found. Installing yq is recommended for advanced YAML processing."
    print_info "Install: brew install yq (macOS) or snap install yq (Linux)"
    USE_YQ=false
else
    USE_YQ=true
    print_info "yq found: $(yq --version)"
fi

# Create conversion output directory
CONVERTED_DIR="$MIGRATION_DIR/manifests/converted/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$CONVERTED_DIR"
print_info "Conversion output directory: $CONVERTED_DIR"

# Function to clean Kubernetes metadata
clean_metadata() {
    local input_file=$1
    local output_file=$2

    if [ "$USE_YQ" = true ]; then
        yq eval 'del(.metadata.uid,
                     .metadata.resourceVersion,
                     .metadata.creationTimestamp,
                     .metadata.generation,
                     .metadata.selfLink,
                     .metadata.managedFields,
                     .status)' "$input_file" > "$output_file"
    else
        # Basic sed-based cleanup (less robust)
        grep -v "uid:\|resourceVersion:\|creationTimestamp:\|generation:\|selfLink:\|managedFields:\|^status:" "$input_file" > "$output_file"
    fi
}

# Convert deployments
print_step "Converting deployments..."
if [ -f "$AKS_EXPORT_DIR/deployments.yaml" ]; then
    clean_metadata "$AKS_EXPORT_DIR/deployments.yaml" "$CONVERTED_DIR/deployments-cleaned.yaml"

    # Add ARO-specific security contexts
    cat > "$CONVERTED_DIR/deployment-notes.txt" << 'EOF'
ARO Deployment Conversion Notes
================================

Required Changes:
1. Add securityContext at pod and container level:
   - runAsNonRoot: true
   - allowPrivilegeEscalation: false
   - capabilities.drop: [ALL]

2. Specify serviceAccountName for each deployment

3. Add imagePullSecrets if using private registry (ACR)

4. Update resource requests/limits if needed

5. Review and update probes (readiness/liveness)

Example securityContext:
  securityContext:
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    capabilities:
      drop:
      - ALL
EOF
    print_info "Deployments cleaned and conversion notes created"
else
    print_warn "No deployments.yaml found"
fi

# Convert services (usually compatible, just clean metadata)
print_step "Converting services..."
if [ -f "$AKS_EXPORT_DIR/services.yaml" ]; then
    clean_metadata "$AKS_EXPORT_DIR/services.yaml" "$CONVERTED_DIR/services-cleaned.yaml"
    print_info "Services cleaned"
else
    print_warn "No services.yaml found"
fi

# Convert Ingress to OpenShift Routes
print_step "Converting Ingress to OpenShift Routes..."
if [ -f "$AKS_EXPORT_DIR/ingresses.yaml" ]; then
    print_info "Creating Route conversion template..."

    cat > "$CONVERTED_DIR/ingress-to-route-conversion.sh" << 'EOF'
#!/bin/bash
# Helper script to convert Ingress to OpenShift Route
# Usage: ./ingress-to-route-conversion.sh <ingress-yaml> <output-route-yaml>

INGRESS_FILE=$1
ROUTE_FILE=$2

if [ ! -f "$INGRESS_FILE" ]; then
    echo "Ingress file not found: $INGRESS_FILE"
    exit 1
fi

# Extract ingress details (basic example for single-host ingress)
INGRESS_NAME=$(yq eval '.metadata.name' "$INGRESS_FILE")
NAMESPACE=$(yq eval '.metadata.namespace' "$INGRESS_FILE")
HOST=$(yq eval '.spec.rules[0].host' "$INGRESS_FILE")
SERVICE_NAME=$(yq eval '.spec.rules[0].http.paths[0].backend.service.name' "$INGRESS_FILE")
SERVICE_PORT=$(yq eval '.spec.rules[0].http.paths[0].backend.service.port.number // .spec.rules[0].http.paths[0].backend.service.port.name' "$INGRESS_FILE")
TLS_ENABLED=$(yq eval '.spec.tls | length' "$INGRESS_FILE")

# Create Route YAML
cat > "$ROUTE_FILE" << ROUTE_EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${INGRESS_NAME}
  namespace: ${NAMESPACE}
spec:
  host: ${HOST}
  to:
    kind: Service
    name: ${SERVICE_NAME}
    weight: 100
  port:
    targetPort: ${SERVICE_PORT}
$(if [ "$TLS_ENABLED" != "0" ] && [ "$TLS_ENABLED" != "null" ]; then
cat << TLS_EOF
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
TLS_EOF
fi)
  wildcardPolicy: None
ROUTE_EOF

echo "Route created: $ROUTE_FILE"
EOF

    chmod +x "$CONVERTED_DIR/ingress-to-route-conversion.sh"

    # Create manual conversion guide
    cat > "$CONVERTED_DIR/routes.yaml" << 'EOF'
# OpenShift Routes converted from AKS Ingress
# Review and customize for your specific needs

# Example Route (customize for your application):
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: sample-app
  namespace: production
spec:
  host: app.example.com
  to:
    kind: Service
    name: sample-app
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
---
# Add more routes as needed based on ingresses.yaml
EOF

    print_warn "Ingress to Route conversion requires manual review"
    print_info "Template created: $CONVERTED_DIR/routes.yaml"
    print_info "Helper script: $CONVERTED_DIR/ingress-to-route-conversion.sh"
fi

# Convert ConfigMaps
print_step "Converting ConfigMaps..."
if [ -f "$AKS_EXPORT_DIR/configmaps.yaml" ]; then
    clean_metadata "$AKS_EXPORT_DIR/configmaps.yaml" "$CONVERTED_DIR/configmaps-cleaned.yaml"
    print_info "ConfigMaps cleaned"
fi

# Handle Secrets
print_step "Handling Secrets..."
if [ -f "$AKS_EXPORT_DIR/secrets.yaml" ]; then
    clean_metadata "$AKS_EXPORT_DIR/secrets.yaml" "$CONVERTED_DIR/secrets-cleaned.yaml"

    cat > "$CONVERTED_DIR/secrets-migration-guide.txt" << 'EOF'
Secrets Migration Options
==========================

Option 1: Migrate secrets directly (for testing)
  oc apply -f secrets-cleaned.yaml

Option 2: Use Azure Key Vault CSI Driver (RECOMMENDED for production)
  - Install CSI driver on ARO
  - Create SecretProviderClass
  - Mount secrets as volumes in pods
  - See: ../docs/02-MIGRATION-RUNBOOK.md for details

Option 3: Create secrets from Azure Key Vault via CLI
  DB_USERNAME=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name db-username --query value -o tsv)
  DB_PASSWORD=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name db-password --query value -o tsv)
  oc create secret generic db-credentials \
    --from-literal=username=$DB_USERNAME \
    --from-literal=password=$DB_PASSWORD \
    --namespace=production
EOF

    print_warn "Secrets require careful handling. See: $CONVERTED_DIR/secrets-migration-guide.txt"
fi

# Create ARO-specific resources
print_step "Creating ARO-specific resource templates..."

# Create Service Account template
cat > "$CONVERTED_DIR/serviceaccount.yaml" << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sample-app-sa
  namespace: production
---
# Link this service account to ACR pull secret:
# oc secrets link sample-app-sa acr-pull-secret --for=pull -n production
EOF

# Create Security Context Constraints template
cat > "$CONVERTED_DIR/scc-custom.yaml" << 'EOF'
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: custom-app-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: false
allowPrivilegedContainer: false
allowedCapabilities: []
defaultAddCapabilities: []
fsGroup:
  type: MustRunAs
  ranges:
  - min: 1000
    max: 65535
readOnlyRootFilesystem: false
requiredDropCapabilities:
- ALL
runAsUser:
  type: MustRunAsNonRoot
seLinuxContext:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
- csi
priority: 10
---
# To use this SCC:
# oc apply -f scc-custom.yaml
# oc adm policy add-scc-to-user custom-app-scc -z sample-app-sa -n production
EOF

# Create Azure Key Vault CSI SecretProviderClass template
cat > "$CONVERTED_DIR/secretproviderclass.yaml" << 'EOF'
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-keyvault-secrets
  namespace: production
spec:
  provider: azure
  secretObjects:
  - secretName: db-credentials
    type: Opaque
    data:
    - objectName: db-username
      key: username
    - objectName: db-password
      key: password
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "<ARO-SERVICE-PRINCIPAL-CLIENT-ID>"
    keyvaultName: "<KEY-VAULT-NAME>"
    tenantId: "<AZURE-TENANT-ID>"
    objects: |
      array:
        - |
          objectName: db-username
          objectType: secret
        - |
          objectName: db-password
          objectType: secret
---
# Update the following in your Deployment:
#   volumes:
#   - name: secrets-store
#     csi:
#       driver: secrets-store.csi.k8s.io
#       readOnly: true
#       volumeAttributes:
#         secretProviderClass: "azure-keyvault-secrets"
#
#   volumeMounts:
#   - name: secrets-store
#     mountPath: "/mnt/secrets"
#     readOnly: true
EOF

# Create conversion summary
print_step "Creating conversion summary..."
cat > "$CONVERTED_DIR/conversion-summary.txt" << EOF
AKS to ARO Manifest Conversion Summary
=======================================
Conversion Date: $(date)
Source Directory: $AKS_EXPORT_DIR
Output Directory: $CONVERTED_DIR

Files Created:
$(ls -lh "$CONVERTED_DIR" | tail -n +2)

Conversion Status:
  ✅ Deployments: Cleaned, requires security context updates
  ✅ Services: Cleaned, ready for ARO
  ⚠️  Ingress: Manual conversion to Routes required
  ✅ ConfigMaps: Cleaned, ready for ARO
  ⚠️  Secrets: Review migration options (direct or Key Vault CSI)
  ✅ ServiceAccount: Template created
  ✅ SCC: Custom template created
  ✅ SecretProviderClass: Template created for Azure Key Vault

Next Steps:
1. Review deployment-notes.txt for required security context changes
2. Convert Ingress to Routes using routes.yaml template
3. Decide on secrets migration strategy (secrets-migration-guide.txt)
4. Update service account references in deployments
5. Test manifests in ARO staging environment
6. Run deployment script: ./scripts/03-deploy-to-aro.sh

Manual Actions Required:
- Update securityContext in all Deployments
- Convert Ingress resources to Routes
- Configure ACR pull secrets
- Update environment-specific values (hostnames, database endpoints)
- Review and apply appropriate SCC
EOF

cat "$CONVERTED_DIR/conversion-summary.txt"

print_info "Conversion completed!"
print_info "Review conversion summary: $CONVERTED_DIR/conversion-summary.txt"
print_warn "Manual review and updates required before deployment"

# Set environment variable for next script
export ARO_MANIFEST_DIR="$CONVERTED_DIR"
echo "export ARO_MANIFEST_DIR=\"$CONVERTED_DIR\"" > "$MIGRATION_DIR/manifests/latest-conversion.env"
