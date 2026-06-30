# Complete Guide: ROSA HCP with External Authentication and GitOps Operators

This guide provides step-by-step instructions for:

1. **Installing a ROSA HCP cluster with external authentication**
2. **Configuring Microsoft Entra ID** as the external auth provider
3. **Installing Pipelines, GitOps, and Logging operators** using Helm charts from [rh-mobb/helm-charts](https://github.com/rh-mobb/helm-charts)

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Part 1: Install ROSA HCP Cluster with External Auth](#part-1-install-rosa-hcp-cluster-with-external-auth)
- [Part 2: Configure External Authentication (Microsoft Entra ID)](#part-2-configure-external-authentication-microsoft-entra-id)
- [Part 3: Bootstrap GitOps and Install Operators](#part-3-bootstrap-gitops-and-install-operators)
- [Part 4: Verify Installation](#part-4-verify-installation)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before you begin, ensure you have:

| Tool | Purpose | Installation |
|------|---------|--------------|
| **Terraform** | Infrastructure as Code | `brew install terraform` or [terraform.io](https://terraform.io) |
| **AWS CLI** v2 | AWS authentication | `brew install awscli` |
| **ROSA CLI** | Cluster management | [ROSA CLI Install](https://docs.openshift.com/rosa/cli_reference/rosa_cli/rosa-cli-reference.html) |
| **OpenShift CLI (oc)** | Cluster access | Included with ROSA CLI or [oc download](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/) |
| **jq** | JSON processing | `brew install jq` |

### RHCS API Credentials

You need Red Hat Cloud Services (RHCS) credentials:

1. Go to [Red Hat Console - API Tokens](https://console.redhat.com/openshift/token/rosa/show)
2. Create a token or use a service account with `client_id` and `client_secret`

### AWS Configuration

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAXXXXXXXXXXXXXXXXX",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-user"
# }
```

---

## Part 1: Install ROSA HCP Cluster with External Auth

### Step 1.1: Navigate to Terraform Configuration

```bash
cd cluster-creation/aws/tf-rosa
# Use examples/external-auth.tfvars.example for external authentication
```

### Step 1.2: Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# Required
cluster_name  = "my-rosa-external-auth"
client_id     = "your-rhcs-client-id"
client_secret = "your-rhcs-client-secret"

# Cluster Configuration
region     = "us-east-1"
multi_az   = false
private    = false
replicas   = 2
compute_machine_type = "m5.xlarge"

# CRITICAL: External auth must be enabled at creation - cannot be changed later!
external_auth_providers_enabled = true
```

### Step 1.3: Initialize and Deploy

```bash
# Initialize Terraform
terraform init
```

**Expected output:**
```
Initializing the backend...
Initializing provider plugins...
- Finding terraform-redhat/rhcs versions matching ">= 1.7.1"...
- Finding hashicorp/aws versions matching ">= 4.20.0"...
- Installing terraform-redhat/rhcs v1.7.4...
- Installing hashicorp/aws v6.33.0...
Terraform has been successfully initialized!
```

```bash
# Review the plan
terraform plan -var-file=terraform.tfvars
```

```bash
# Apply (cluster creation takes 30-45 minutes)
terraform apply -var-file=terraform.tfvars
```

**Expected output (summary):**
```
Plan: XX to add, 0 to change, 0 to destroy.
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

rhcs_cluster_rosa_hcp.rosa: Creating...
...
Apply complete! Resources: XX added, 0 changed, 0 destroyed.

Outputs:
cluster_api_url = "https://api.my-rosa-external-auth.xxxxx.p1.openshiftapps.com"
cluster_console_url = "https://console-openshift-console.apps.my-rosa-external-auth.xxxxx.p1.openshiftapps.com"
cluster_name = "my-rosa-external-auth"
external_auth_enabled = true
oauth_callback_url = "https://oauth-openshift.apps.my-rosa-external-auth.xxxxx.p1.openshiftapps.com/oauth2callback/<provider_name>"
```

### Step 1.4: Verify External Auth is Enabled

```bash
export ROSA_CLUSTER_NAME="my-rosa-external-auth"  # Use your cluster name
rosa describe cluster -c ${ROSA_CLUSTER_NAME} | grep "External Authentication"
```

**Expected output:**
```
External Authentication:    Enabled
```

---

## Part 2: Configure External Authentication (Microsoft Entra ID)

> **Important:** Until you configure an external auth provider and RBAC, you cannot log in to the cluster. Use **break glass credentials** for initial setup.

### Step 2.1: Create Break Glass Credential

```bash
rosa create break-glass-credential -c ${ROSA_CLUSTER_NAME} --username=admin
```

**Expected output:**
```
? Expiration duration: 24h
? Would you like to continue? Yes
I: Creating break glass credential...
I: Break glass credential 'xxxxx' has been created.
W: Break glass credentials provide emergency access to your cluster. Use them only when necessary.
W: Credential expires in 24h. Save the kubeconfig now.
```

```bash
# Get credential ID and save kubeconfig
export BREAK_GLASS_ID=$(rosa list break-glass-credential -c ${ROSA_CLUSTER_NAME} -o json | jq -r '.[0].id')
rosa describe break-glass-credential ${BREAK_GLASS_ID} -c ${ROSA_CLUSTER_NAME} --kubeconfig > ~/.kube/breakglass-${ROSA_CLUSTER_NAME}

# Use break glass for cluster access
export KUBECONFIG=~/.kube/breakglass-${ROSA_CLUSTER_NAME}

# Verify access
oc whoami
oc get nodes
```

**Expected output:**
```
admin
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-0-xxx-xxx.us-east-1.compute.internal   Ready    worker   45m   v1.28.x
ip-10-0-xxx-xxx.us-east-1.compute.internal   Ready    worker   45m   v1.28.x
```

### Step 2.2: Get Cluster Information for Entra ID

```bash
export CLUSTER_DOMAIN=$(rosa describe cluster -c ${ROSA_CLUSTER_NAME} -o json | jq -r '.domain')
export OAUTH_CALLBACK_URL="https://oauth-openshift.apps.${CLUSTER_DOMAIN}/oauth2callback/entra-id"

echo "OAuth Callback URL: ${OAUTH_CALLBACK_URL}"
```

**Expected output:**
```
OAuth Callback URL: https://oauth-openshift.apps.my-rosa-external-auth.xxxxx.p1.openshiftapps.com/oauth2callback/entra-id
```

### Step 2.3: Register Application in Microsoft Entra ID

1. Go to [Azure Portal](https://portal.azure.com) → **Microsoft Entra ID** → **App registrations** → **New registration**
2. Configure:
   - **Name:** `rosa-hcp-${ROSA_CLUSTER_NAME}`
   - **Supported account types:** Single tenant
   - **Redirect URI:** Web → `${OAUTH_CALLBACK_URL}`
3. After registration, note:
   - **Application (client) ID**
   - **Directory (tenant) ID**
4. Go to **Certificates & secrets** → **New client secret** → Copy the **Secret Value**
5. Go to **Token configuration** → Add optional claims:
   - ID token: `email`, `preferred_username`
   - Add groups claim: **Security groups** → Group ID
6. Go to **API permissions** → Ensure: `User.Read`, `email`, `openid`, `profile` (Delegated)

> For detailed Entra ID setup, see [tf-rosa/docs/ENTRA-ID-SETUP.md](tf-rosa/docs/ENTRA-ID-SETUP.md)

### Step 2.4: Add External Auth Provider to ROSA

```bash
export ENTRA_TENANT_ID="your-tenant-id"
export ENTRA_CLIENT_ID="your-client-id"
export ENTRA_CLIENT_SECRET="your-client-secret"
export PROVIDER_NAME="entra-id"

rosa create external-auth-provider -c ${ROSA_CLUSTER_NAME} \
    --name=${PROVIDER_NAME} \
    --issuer-url=https://login.microsoftonline.com/${ENTRA_TENANT_ID}/v2.0 \
    --issuer-audiences=${ENTRA_CLIENT_ID} \
    --claim-mapping-username-claim=email \
    --claim-mapping-groups-claim=groups \
    --console-client-id=${ENTRA_CLIENT_ID} \
    --console-client-secret=${ENTRA_CLIENT_SECRET}
```

**Expected output:**
```
I: External authentication provider 'entra-id' has been created.
```

### Step 2.5: Configure RBAC for Entra ID Groups

Create an Azure AD security group (e.g., `rosa-cluster-admins`) and note its **Object ID**. Then:

```bash
# Ensure KUBECONFIG points to break glass
export KUBECONFIG=~/.kube/breakglass-${ROSA_CLUSTER_NAME}
export ADMIN_GROUP_ID="your-azure-ad-group-object-id"

cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: entra-id-cluster-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: "${ADMIN_GROUP_ID}"
EOF
```

**Expected output:**
```
clusterrolebinding.rbac.authorization.k8s.io/entra-id-cluster-admins created
```

### Step 2.6: Test Login

1. Open the console URL: `rosa describe cluster -c ${ROSA_CLUSTER_NAME} | grep "Console URL"`
2. Sign in with an Entra ID user that is a member of your admin group
3. For CLI: Install `kubelogin` and configure kubeconfig (see [ENTRA-ID-SETUP.md](tf-rosa/docs/ENTRA-ID-SETUP.md#cli-authentication-with-kubelogin))

---

## Part 3: Install Operators via Helm Charts

Operators are installed using [rh-mobb/helm-charts](https://github.com/rh-mobb/helm-charts). The **operatorhub** chart deploys GitOps, Pipelines, and Logging operators. The **rosa-loki** chart (optional) deploys the full LokiStack with S3 backend.

### Step 3.1: Add Helm Repository and Create Namespaces

```bash
# Ensure you're logged in with cluster-admin
export KUBECONFIG=~/.kube/breakglass-${ROSA_CLUSTER_NAME}  # or your Entra ID kubeconfig

# Add the MOBB Helm repository
helm repo add mobb https://rh-mobb.github.io/helm-charts/
helm repo update
```

**Expected output:**
```
"mobb" has been added to your repositories
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "mobb" chart repository
Update Complete.
```

```bash
# Create required namespaces
oc create namespace openshift-gitops-operator
oc create namespace openshift-logging
oc create namespace openshift-operators-redhat
```

**Expected output:**
```
namespace/openshift-gitops-operator created
namespace/openshift-logging created
namespace/openshift-operators-redhat created
```

### Step 3.2: Install All Operators (GitOps, Pipelines, Logging)

```bash
cd cluster-creation/aws/addons/operators/helm-values

helm upgrade --install operators mobb/operatorhub \
  -n openshift-operators \
  -f operatorhub-operators.yaml \
  --create-namespace
```

**Expected output:**
```
Release "operators" does not exist. Installing it now.
NAME: operators
LAST DEPLOYED: ...
NAMESPACE: openshift-operators
STATUS: deployed
```

### Step 3.3: Wait for Operators to Be Ready

```bash
# GitOps (5-10 minutes)
oc wait --for=condition=Ready namespace/openshift-gitops --timeout=600s 2>/dev/null || true
oc wait --for=condition=Available deployment/openshift-gitops-server -n openshift-gitops --timeout=600s

# Pipelines
oc wait --for=condition=Available deployment/tekton-pipelines-controller -n openshift-pipelines --timeout=600s 2>/dev/null || true

# Logging operators
oc wait --for=condition=Available deployment/cluster-logging-operator -n openshift-logging --timeout=600s 2>/dev/null || true
oc wait --for=condition=Available deployment/loki-operator-controller-manager -n openshift-operators-redhat --timeout=600s 2>/dev/null || true
```

**Expected output:**
```
deployment.apps/openshift-gitops-server condition met
```

```bash
# Configure GitOps route (optional - for external access)
oc -n openshift-gitops patch argocd/openshift-gitops --type=merge -p='{"spec":{"server":{"route":{"enabled":true,"tls":{"insecureEdgeTerminationPolicy":"Redirect","termination":"reencrypt"}}}}}'
```

### Step 3.4: (Optional) Deploy LokiStack with S3 Backend

For full log collection with LokiStack backed by AWS S3, use the **rosa-loki** chart. See [rosa-loki README](https://github.com/rh-mobb/helm-charts/tree/main/charts/rosa-loki) for S3 bucket and IAM setup.

```bash
export CLUSTER_NAME="${ROSA_CLUSTER_NAME}"
export AWS_REGION="us-east-1"
# Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from IAM user

helm upgrade --install cluster-logging mobb/rosa-loki \
  -n cluster-logging \
  --set "aws_access_key_id=${AWS_ACCESS_KEY_ID}" \
  --set "aws_access_key_secret=${AWS_SECRET_ACCESS_KEY}" \
  --set "aws_region=${AWS_REGION}" \
  --set "aws_s3_bucket_name=rosa-${CLUSTER_NAME}-loki" \
  --create-namespace
```

### Step 3.5: Argo CD Application (GitOps-First with Helm)

To manage operators via Argo CD using Helm charts:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: operators-helm
  namespace: openshift-gitops
spec:
  source:
    repoURL: https://rh-mobb.github.io/helm-charts/
    chart: operatorhub
    targetRevision: "0.1.2"
    helm:
      valueFiles:
        - https://raw.githubusercontent.com/your-org/your-repo/main/cluster-creation/aws/addons/operators/helm-values/operatorhub-operators.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-operators
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

> **Alternative:** Raw YAML manifests are available in `gitops-manifests/` for users who prefer `oc apply -k` over Helm. See [gitops-manifests/README.md](gitops-manifests/README.md).

---

## Part 4: Verify Installation

### Verify Operators

```bash
# Check all operator subscriptions
oc get subscription -A | grep -E "gitops|pipelines|logging|loki"

# Check ClusterServiceVersions (CSVs)
oc get csv -A | grep -E "gitops|pipelines|cluster-logging|loki"
```

**Expected output (example):**
```
NAMESPACE                      NAME                           DISPLAY                          VERSION   REPLACES   PHASE
openshift-gitops-operator      openshift-gitops-operator.v1.x.x   Red Hat OpenShift GitOps       1.x.x               Succeeded
openshift-operators            openshift-pipelines-operator-rhel8.v1.x.x   Red Hat OpenShift Pipelines   1.x.x               Succeeded
openshift-logging             cluster-logging-operator.v5.x.x   Red Hat OpenShift Logging       5.x.x               Succeeded
openshift-operators-redhat    loki-operator.v5.x.x   Loki Operator              5.x.x               Succeeded
```

### Verify GitOps (Argo CD)

```bash
oc get route -n openshift-gitops openshift-gitops-server -o jsonpath='{.spec.host}'
# Open the URL in a browser
```

### Verify Pipelines

```bash
oc get pods -n openshift-pipelines
# Should show tekton pipelines controller pods
```

### Verify Logging

```bash
oc get pods -n openshift-logging
oc get clusterlogging -n openshift-logging  # After ClusterLogging CR is applied
```

---

## Troubleshooting

### Cluster Creation Fails

- Verify RHCS credentials: `terraform console` then `var.client_id`
- Check AWS quota for EC2 instances in the region
- Ensure `external_auth_providers_enabled = true` is set

### Cannot Login After Cluster Creation

- External auth is enabled but no provider is configured yet
- Create break glass: `rosa create break-glass-credential -c <cluster>`
- Add external auth provider (Step 2.4)

### Operator Installation Stuck

```bash
# Check install plans
oc get installplan -A

# Check CSV status
oc get csv -A
oc describe csv <csv-name> -n <namespace>

# Approve pending install plan manually if needed
oc patch installplan <installplan-name> -n <namespace> --type merge -p '{"spec":{"approved":true}}'
```

### GitOps Route Not Accessible

```bash
# Patch the route
oc -n openshift-gitops patch argocd/openshift-gitops --type=merge \
  -p='{"spec":{"server":{"route":{"enabled":true}}}}'
```

---

## Quick Reference Commands

```bash
# Cluster info
rosa describe cluster -c ${ROSA_CLUSTER_NAME}

# List external auth providers
rosa list external-auth-provider -c ${ROSA_CLUSTER_NAME}

# Break glass
export KUBECONFIG=~/.kube/breakglass-${ROSA_CLUSTER_NAME}

# Operator status
oc get subscription -A
oc get csv -A
```

---

## References

- [ROSA HCP External Auth Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_rosa_with_hcp_clusters/rosa-hcp-sts-creating-a-cluster-ext-auth)
- [Entra ID Setup (Detailed)](tf-rosa/docs/ENTRA-ID-SETUP.md)
- [OpenShift GitOps Installation](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.17/html-single/installing_gitops/)
- [OpenShift Logging Documentation](https://docs.openshift.com/container-platform/4.15/observability/logging/)
