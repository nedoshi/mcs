OpenShift Operators Installation Guide for Air-Gapped Azure Red Hat OpenShift
Prerequisites
Environment Requirements

Azure Red Hat OpenShift cluster running in air-gapped environment
Bastion host or jump server with internet connectivity
Internal container registry (Harbor, Nexus, or similar)
OpenShift CLI (oc) installed
Podman or Docker installed on bastion host
Sufficient storage for operator images

Required Access

Cluster administrator privileges
Access to Red Hat registry (registry.redhat.io)
Network connectivity between bastion and internal registry

Phase 1: Prepare Air-Gapped Environment
Step 1: Set Up Internal Container Registry
bash# Example using Harbor registry
# Configure your internal registry with proper authentication
export INTERNAL_REGISTRY="harbor.company.com"
export REGISTRY_USER="admin"
export REGISTRY_PASSWORD="your-password"
Step 2: Configure Registry Authentication
bash# On bastion host, create registry auth file
mkdir -p ~/.docker
cat > ~/.docker/config.json << EOF
{
  "auths": {
    "registry.redhat.io": {
      "auth": "$(echo -n 'username:password' | base64 -w 0)"
    },
    "${INTERNAL_REGISTRY}": {
      "auth": "$(echo -n '${REGISTRY_USER}:${REGISTRY_PASSWORD}' | base64 -w 0)"
    }
  }
}
EOF
Phase 2: Mirror Operator Images
Step 3: Download Operator Catalog
bash# Create working directory
mkdir -p ~/operator-mirror
cd ~/operator-mirror

# Download the operator catalog
oc adm catalog mirror registry.redhat.io/redhat/redhat-operator-index:v4.14 \
  ${INTERNAL_REGISTRY}/openshift4/redhat-operator-index \
  --registry-config=~/.docker/config.json \
  --to-manifests=./manifests
Step 4: Mirror Specific Operators
bash# Mirror specific operators (example: OpenShift Pipelines, Service Mesh)
export OPERATORS="openshift-pipelines-operator-rh,servicemeshoperator"

# Create operator list file
cat > operators.txt << EOF
openshift-pipelines-operator-rh
servicemeshoperator
cluster-logging
elasticsearch-operator
EOF

# Mirror operators to internal registry
for operator in $(cat operators.txt); do
  oc adm catalog mirror registry.redhat.io/redhat/redhat-operator-index:v4.14 \
    ${INTERNAL_REGISTRY}/openshift4 \
    --registry-config=~/.docker/config.json \
    --filter-by-os="linux/amd64" \
    --manifests-only \
    --include="${operator}"
done
Step 5: Mirror Operator Images
bash# Mirror the actual operator images
oc image mirror -f ./manifests/mapping.txt \
  --registry-config=~/.docker/config.json \
  --skip-multiple-scopes \
  --max-per-registry=10
Phase 3: Configure OpenShift Cluster
Step 6: Configure Image Content Source Policy
bash# Apply the generated ImageContentSourcePolicy
oc apply -f ./manifests/imageContentSourcePolicy.yaml

# Wait for nodes to restart (this may take 10-15 minutes)
oc get nodes
watch oc get mcp
Step 7: Configure Catalog Source
bash# Create custom catalog source
cat > custom-catalog-source.yaml << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: custom-redhat-operators
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: ${INTERNAL_REGISTRY}/openshift4/redhat-operator-index:v4.14
  displayName: Custom Red Hat Operators
  publisher: Red Hat
  updateStrategy:
    registryPoll:
      interval: 30m
EOF

oc apply -f custom-catalog-source.yaml
Step 8: Disable Default Catalog Sources
bash# Disable default catalog sources in air-gapped environment
oc patch OperatorHub cluster --type json \
  -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
Phase 4: Install Operators
Step 9: Verify Catalog Source
bash# Check catalog source status
oc get catalogsource -n openshift-marketplace
oc get packagemanifest | grep -E "(pipelines|servicemesh)"

# Check available operators
oc get packagemanifest -n openshift-marketplace
Step 10: Install Operators via OperatorHub
Method 1: Using Web Console

Navigate to Operators → OperatorHub
Search for desired operator
Click Install
Configure installation options
Click Install

Method 2: Using CLI
bash# Example: Install OpenShift Pipelines Operator
cat > pipelines-operator-subscription.yaml << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-pipelines-operator-rh
  source: custom-redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc apply -f pipelines-operator-subscription.yaml
Step 11: Install Service Mesh Operator
bash# Create Service Mesh subscription
cat > servicemesh-operator-subscription.yaml << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator
  namespace: openshift-operators
spec:
  channel: stable
  name: servicemeshoperator
  source: custom-redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc apply -f servicemesh-operator-subscription.yaml
Phase 5: Verification
Step 12: Verify Operator Installation
bash# Check operator subscriptions
oc get subscription -n openshift-operators

# Check operator installation status
oc get csv -n openshift-operators

# Check operator pods
oc get pods -n openshift-operators | grep -E "(pipelines|servicemesh)"

# Detailed status check
oc describe csv -n openshift-operators
Step 13: Verify Operator Functionality
bash# For OpenShift Pipelines
oc get tektonconfig
oc get pods -n openshift-pipelines

# For Service Mesh
oc get servicemeshcontrolplane -A
oc get pods -n istio-system
Step 14: Test Operator Features
bash# Create test namespace
oc new-project operator-test

# Test Pipelines (if installed)
cat > test-pipeline.yaml << EOF
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: test-pipeline
  namespace: operator-test
spec:
  tasks:
  - name: hello
    taskSpec:
      steps:
      - name: hello
        image: registry.redhat.io/ubi8/ubi:latest
        script: |
          echo "Hello from air-gapped operator!"
EOF

oc apply -f test-pipeline.yaml
Phase 6: Maintenance and Updates
Step 15: Update Operators
bash# Check for operator updates
oc get subscription -n openshift-operators -o yaml

# Update operator images when new versions are available
# Repeat mirroring process for new operator versions
Step 16: Monitor Operator Health
bash# Create monitoring script
cat > monitor-operators.sh << '#!/bin/bash
#!/bin/bash

echo "=== Operator Status Check ==="
echo "Subscriptions:"
oc get subscription -n openshift-operators

echo -e "\nCluster Service Versions:"
oc get csv -n openshift-operators

echo -e "\nOperator Pods:"
oc get pods -n openshift-operators

echo -e "\nCatalog Sources:"
oc get catalogsource -n openshift-marketplace
'

chmod +x monitor-operators.sh
./monitor-operators.sh
Troubleshooting
Common Issues and Solutions

Catalog Source Not Ready
bash# Check catalog source logs
oc logs -n openshift-marketplace deployment/custom-redhat-operators

Image Pull Errors
bash# Verify image content source policy
oc get imagecontentsourcepolicy

# Check node configuration
oc debug node/<node-name>
chroot /host
cat /etc/containers/registries.conf

Operator Installation Stuck
bash# Check operator group
oc get operatorgroup -n openshift-operators

# Check install plan
oc get installplan -n openshift-operators


Validation Commands
bash# Comprehensive validation script
cat > validate-airgapped-operators.sh << '#!/bin/bash
#!/bin/bash

echo "=== Air-Gapped Operator Validation ==="

# Check if default sources are disabled
echo "1. Checking OperatorHub configuration:"
oc get operatorhub cluster -o jsonpath='{.spec.disableAllDefaultSources}'

# Check custom catalog source
echo -e "\n2. Custom catalog source status:"
oc get catalogsource custom-redhat-operators -n openshift-marketplace

# Check image content source policy
echo -e "\n3. Image content source policies:"
oc get imagecontentsourcepolicy

# Check operator subscriptions
echo -e "\n4. Operator subscriptions:"
oc get subscription -A

# Check cluster service versions
echo -e "\n5. Cluster service versions:"
oc get csv -A

echo -e "\n=== Validation Complete ==="
'

chmod +x validate-airgapped-operators.sh
./validate-airgapped-operators.sh
Best Practices

Regular Updates: Schedule regular operator image mirroring
Resource Monitoring: Monitor registry storage and cluster resources
Backup Strategy: Maintain backups of operator configurations
Documentation: Keep detailed records of installed operators and versions
Testing: Test operator functionality after each update

Security Considerations

Ensure internal registry has proper SSL certificates
Implement RBAC for operator management
Regularly scan operator images for vulnerabilities
Monitor operator resource consumption
Maintain audit logs for operator installations and updates