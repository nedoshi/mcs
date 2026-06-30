# Configuring Microsoft Entra ID as External Authentication Provider for ROSA HCP

This guide provides detailed, step-by-step instructions for configuring Microsoft Entra ID (formerly Azure Active Directory) as an external authentication provider for your ROSA HCP cluster.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Architecture Overview](#architecture-overview)
- [Step 1: Get Cluster Information](#step-1-get-cluster-information)
- [Step 2: Register Application in Microsoft Entra ID](#step-2-register-application-in-microsoft-entra-id)
- [Step 3: Configure Client Secret](#step-3-configure-client-secret)
- [Step 4: Configure Token Claims](#step-4-configure-token-claims)
- [Step 5: Configure API Permissions](#step-5-configure-api-permissions)
- [Step 6: Create Security Groups (Optional)](#step-6-create-security-groups-optional)
- [Step 7: Add External Auth Provider to ROSA](#step-7-add-external-auth-provider-to-rosa)
- [Step 8: Configure RBAC](#step-8-configure-rbac)
- [Step 9: Test Authentication](#step-9-test-authentication)
- [CLI Authentication with kubelogin](#cli-authentication-with-kubelogin)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before you begin, ensure you have:

- [ ] A ROSA HCP cluster with `External Authentication: Enabled`
- [ ] Access to Microsoft Azure Portal with permissions to create App registrations
- [ ] Azure CLI (`az`) installed (optional, for CLI-based setup)
- [ ] ROSA CLI (`rosa`) installed and logged in
- [ ] OpenShift CLI (`oc`) installed

Verify your cluster has external auth enabled:

```bash
rosa describe cluster -c <cluster_name> | grep "External Authentication"
# Expected output: External Authentication:    Enabled
```

---

## Architecture Overview

```
┌─────────────────┐      ┌─────────────────────┐      ┌─────────────────┐
│                 │      │                     │      │                 │
│  User / CLI     │─────▶│  Microsoft Entra ID │─────▶│  ROSA HCP       │
│                 │      │                     │      │  Cluster        │
│  - Browser      │      │  - Authentication   │      │                 │
│  - oc login     │      │  - Token Issuance   │      │  - API Server   │
│  - kubectl      │      │  - Group Claims     │      │  - Console      │
│                 │      │                     │      │                 │
└─────────────────┘      └─────────────────────┘      └─────────────────┘
                                   │
                                   ▼
                         ┌─────────────────────┐
                         │  Token Contents:    │
                         │  - email (username) │
                         │  - groups (roles)   │
                         │  - aud (audience)   │
                         └─────────────────────┘
```

---

## Step 1: Get Cluster Information

First, gather the necessary information from your ROSA cluster:

```bash
# Set your cluster name
export ROSA_CLUSTER_NAME="your-cluster-name"

# Get cluster details
rosa describe cluster -c ${ROSA_CLUSTER_NAME}

# Get the cluster domain for OAuth callback URL
export CLUSTER_DOMAIN=$(rosa describe cluster -c ${ROSA_CLUSTER_NAME} -o json | jq -r '.dns.base_domain')
export CLUSTER_DOMAIN_PREFIX=$(rosa describe cluster -c ${ROSA_CLUSTER_NAME} -o json | jq -r '.domain_prefix')

# Construct the OAuth callback URL
export OAUTH_CALLBACK_URL="https://oauth-openshift.apps.rosa.${CLUSTER_DOMAIN_PREFIX}.${CLUSTER_DOMAIN}/oauth2callback/entra-id"

echo "OAuth Callback URL: ${OAUTH_CALLBACK_URL}"
```

**Note the OAuth Callback URL** - you'll need this when configuring the Entra ID app registration.

Example callback URL format:
```
https://oauth-openshift.apps.rosa.<domain_prefix>.<base_domain>/oauth2callback/<provider_name>
```

---

## Step 2: Register Application in Microsoft Entra ID

### Option A: Using Azure Portal (Recommended for first-time setup)

1. Navigate to [Azure Portal](https://portal.azure.com)

2. Go to **Microsoft Entra ID** (or search for "App registrations")

3. Click **App registrations** → **New registration**

4. Configure the application:

   | Field | Value |
   |-------|-------|
   | **Name** | `rosa-hcp-<cluster_name>` (e.g., `rosa-hcp-nddemo-external-auth`) |
   | **Supported account types** | "Accounts in this organizational directory only (Single tenant)" |
   | **Redirect URI (optional)** | Select **Web** and enter your OAuth callback URL |

   Example Redirect URI:
   ```
   https://oauth-openshift.apps.rosa.p4s4o7l7q1l2h4c.4lpr.p3.openshiftapps.com/oauth2callback/entra-id
   ```

5. Click **Register**

6. **Note the following values** from the Overview page:
   - **Application (client) ID**: e.g., `12345678-1234-1234-1234-123456789012`
   - **Directory (tenant) ID**: e.g., `64dc69e4-d083-49fc-9569-ebece1dd1408`

### Option B: Using Azure CLI

```bash
# Login to Azure
az login

# Set variables
export APP_NAME="rosa-hcp-${ROSA_CLUSTER_NAME}"

# Create the app registration
az ad app create \
    --display-name "${APP_NAME}" \
    --web-redirect-uris "${OAUTH_CALLBACK_URL}" \
    --sign-in-audience AzureADMyOrg

# Get the Application (client) ID
export ENTRA_CLIENT_ID=$(az ad app list --display-name "${APP_NAME}" --query "[0].appId" -o tsv)
echo "Client ID: ${ENTRA_CLIENT_ID}"

# Get the Tenant ID
export ENTRA_TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Tenant ID: ${ENTRA_TENANT_ID}"
```

---

## Step 3: Configure Client Secret

### Using Azure Portal

1. In your app registration, go to **Certificates & secrets**

2. Click **New client secret**

3. Configure:
   - **Description**: `rosa-hcp-secret`
   - **Expires**: Choose appropriate expiration (e.g., 24 months)

4. Click **Add**

5. **IMMEDIATELY copy the Secret Value** (it's only shown once!)
   - Store it securely (e.g., in a password manager or Azure Key Vault)

### Using Azure CLI

```bash
# Create client secret (valid for 2 years)
export ENTRA_CLIENT_SECRET=$(az ad app credential reset \
    --id ${ENTRA_CLIENT_ID} \
    --append \
    --display-name "rosa-hcp-secret" \
    --years 2 \
    --query password -o tsv)

echo "Client Secret: ${ENTRA_CLIENT_SECRET}"
# SAVE THIS VALUE SECURELY!
```

---

## Step 4: Configure Token Claims

Configure the ID token to include the necessary claims for OpenShift authentication.

### Using Azure Portal

1. In your app registration, go to **Token configuration**

2. Click **Add optional claim**

3. Select **ID** token type

4. Add the following claims:
   - [x] `email` - User's email address (used as username)
   - [x] `preferred_username` - Alternative username claim
   - [x] `upn` - User Principal Name

5. Click **Add**

6. If prompted to add Microsoft Graph permissions, click **Add**

### Configure Groups Claim (Important for RBAC)

1. Still in **Token configuration**, click **Add groups claim**

2. Select the group types to include:
   - [x] **Security groups** (recommended)
   - [ ] All groups (may cause token size issues)

3. For each token type (ID, Access, SAML), select:
   - **Group ID** (returns Azure AD group Object IDs)

4. Click **Add**

**Important**: Groups are returned as Object IDs (GUIDs), not names. You'll use these IDs in your ClusterRoleBindings.

---

## Step 5: Configure API Permissions

### Using Azure Portal

1. In your app registration, go to **API permissions**

2. Verify these permissions exist (should be added automatically):
   - `Microsoft Graph` > `User.Read` (Delegated)
   - `Microsoft Graph` > `email` (Delegated)
   - `Microsoft Graph` > `openid` (Delegated)
   - `Microsoft Graph` > `profile` (Delegated)

3. If any are missing, click **Add a permission** → **Microsoft Graph** → **Delegated permissions**

4. Click **Grant admin consent for [Your Organization]** (requires admin privileges)

### Using Azure CLI

```bash
# Add required permissions
az ad app permission add \
    --id ${ENTRA_CLIENT_ID} \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope \
                      37f7f235-527c-4136-accd-4a02d197296e=Scope \
                      64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0=Scope \
                      14dad69e-099b-42c9-810b-d002981feec1=Scope

# Grant admin consent (requires admin role)
az ad app permission admin-consent --id ${ENTRA_CLIENT_ID}
```

---

## Step 6: Create Security Groups (Optional)

Create Azure AD security groups to manage cluster access.

### Using Azure Portal

1. Go to **Microsoft Entra ID** → **Groups**

2. Click **New group**

3. Create groups for different access levels:

   | Group Name | Description | Purpose |
   |------------|-------------|---------|
   | `rosa-cluster-admins` | ROSA Cluster Administrators | Full cluster-admin access |
   | `rosa-developers` | ROSA Developers | Developer access to namespaces |
   | `rosa-viewers` | ROSA Viewers | Read-only access |

4. Add users to appropriate groups

5. **Note the Object ID** of each group (you'll need these for RBAC)

### Using Azure CLI

```bash
# Create cluster-admins group
export ADMIN_GROUP_ID=$(az ad group create \
    --display-name "rosa-cluster-admins" \
    --mail-nickname "rosa-cluster-admins" \
    --query id -o tsv)
echo "Admin Group ID: ${ADMIN_GROUP_ID}"

# Create developers group
export DEV_GROUP_ID=$(az ad group create \
    --display-name "rosa-developers" \
    --mail-nickname "rosa-developers" \
    --query id -o tsv)
echo "Developer Group ID: ${DEV_GROUP_ID}"

# Add yourself to the admin group
export MY_USER_ID=$(az ad signed-in-user show --query id -o tsv)
az ad group member add --group ${ADMIN_GROUP_ID} --member-id ${MY_USER_ID}
```

---

## Step 7: Add External Auth Provider to ROSA

Now configure ROSA to use Microsoft Entra ID as the external authentication provider.

### Set Environment Variables

```bash
# Cluster name
export ROSA_CLUSTER_NAME="your-cluster-name"

# From Azure Portal / CLI
export ENTRA_TENANT_ID="64dc69e4-d083-49fc-9569-ebece1dd1408"  # Your tenant ID
export ENTRA_CLIENT_ID="12345678-1234-1234-1234-123456789012"  # Your client ID
export ENTRA_CLIENT_SECRET="your-client-secret-value"          # Your client secret

# Provider name (lowercase, alphanumeric with dashes)
export PROVIDER_NAME="entra-id"
```

### Create the External Auth Provider

```bash
rosa create external-auth-provider -c ${ROSA_CLUSTER_NAME} \
    --name=${PROVIDER_NAME} \
    --issuer-url=https://login.microsoftonline.com/${ENTRA_TENANT_ID}/v2.0 \
    --issuer-audiences=${ENTRA_CLIENT_ID} \
    --claim-mapping-username-claim=email \
    --claim-mapping-groups-claim=groups \
    --console-client-id=${ENTRA_CLIENT_ID} \
    --console-client-secret=${ENTRA_CLIENT_SECRET}
```

### Verify the Provider

```bash
# List providers
rosa list external-auth-provider -c ${ROSA_CLUSTER_NAME}

# Describe the provider
rosa describe external-auth-provider -c ${ROSA_CLUSTER_NAME} --name ${PROVIDER_NAME}
```

Expected output:
```
NAME       ISSUER URL
entra-id   https://login.microsoftonline.com/64dc69e4-d083-49fc-9569-ebece1dd1408/v2.0
```

---

## Step 8: Configure RBAC

Before users can access the cluster, you need to create RBAC bindings. This requires cluster-admin access via break glass credentials.

### Create Break Glass Credential

```bash
# Create break glass credential
rosa create break-glass-credential -c ${ROSA_CLUSTER_NAME} --username=admin

# List credentials to get the ID
rosa list break-glass-credential -c ${ROSA_CLUSTER_NAME}

# Get the credential ID
export BREAK_GLASS_ID=$(rosa list break-glass-credential -c ${ROSA_CLUSTER_NAME} -o json | jq -r '.[0].id')

# Save kubeconfig
mkdir -p ~/.kube
rosa describe break-glass-credential ${BREAK_GLASS_ID} -c ${ROSA_CLUSTER_NAME} --kubeconfig > ~/.kube/breakglass-${ROSA_CLUSTER_NAME}

# Use the break glass kubeconfig
export KUBECONFIG=~/.kube/breakglass-${ROSA_CLUSTER_NAME}

# Verify access
oc whoami
oc get nodes
```

### Create ClusterRoleBindings for Entra ID Groups

```bash
# Create cluster-admin binding for admins group
# Replace <ADMIN_GROUP_OBJECT_ID> with your Azure AD group's Object ID

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
  name: "${ADMIN_GROUP_ID}"  # Azure AD Group Object ID
EOF

# Create view binding for developers group
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: entra-id-developers-view
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: "${DEV_GROUP_ID}"  # Azure AD Group Object ID
EOF
```

### Create Namespace-Scoped RoleBindings

```bash
# Create a namespace for developers
oc new-project dev-team

# Grant edit access to developers in their namespace
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: entra-id-developers-edit
  namespace: dev-team
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: "${DEV_GROUP_ID}"
EOF
```

---

## Step 9: Test Authentication

### Test Web Console Login

1. Get the console URL:
   ```bash
   rosa describe cluster -c ${ROSA_CLUSTER_NAME} | grep "Console URL"
   ```

2. Open the URL in a browser

3. You should be redirected to Microsoft login

4. Sign in with an Azure AD user that's a member of your configured groups

5. After successful authentication, you should see the OpenShift console

### Test CLI Login with kubelogin

For CLI access, you'll need `kubelogin` (also known as `kubectl-oidc-login`).

#### Install kubelogin

```bash
# macOS
brew install int128/kubelogin/kubelogin

# Linux
curl -LO https://github.com/int128/kubelogin/releases/latest/download/kubelogin_linux_amd64.zip
unzip kubelogin_linux_amd64.zip
sudo mv kubelogin /usr/local/bin/kubectl-oidc_login
```

#### Configure kubeconfig for OIDC

```bash
# Get cluster API URL
export API_URL=$(rosa describe cluster -c ${ROSA_CLUSTER_NAME} -o json | jq -r '.api.url')

# Create kubeconfig with OIDC authentication
cat > ~/.kube/rosa-entra-id-config <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: ${API_URL}
  name: rosa-entra-id
contexts:
- context:
    cluster: rosa-entra-id
    user: entra-id-user
  name: rosa-entra-id
current-context: rosa-entra-id
users:
- name: entra-id-user
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: kubectl
      args:
      - oidc-login
      - get-token
      - --oidc-issuer-url=https://login.microsoftonline.com/${ENTRA_TENANT_ID}/v2.0
      - --oidc-client-id=${ENTRA_CLIENT_ID}
      - --oidc-client-secret=${ENTRA_CLIENT_SECRET}
      - --oidc-extra-scope=email
      - --oidc-extra-scope=profile
EOF

# Use the new kubeconfig
export KUBECONFIG=~/.kube/rosa-entra-id-config

# Test - this will open a browser for authentication
oc get nodes
```

---

## CLI Authentication with kubelogin

### Alternative: Using oc login with OIDC Token

```bash
# Get token interactively using kubelogin
TOKEN=$(kubectl oidc-login get-token \
    --oidc-issuer-url=https://login.microsoftonline.com/${ENTRA_TENANT_ID}/v2.0 \
    --oidc-client-id=${ENTRA_CLIENT_ID} \
    --oidc-client-secret=${ENTRA_CLIENT_SECRET} \
    --oidc-extra-scope=email \
    --oidc-extra-scope=profile \
    | jq -r '.status.token')

# Login with the token
oc login ${API_URL} --token=${TOKEN}
```

---

## Troubleshooting

### Issue: "Invalid issuer" error

**Cause**: The issuer URL doesn't match the token's issuer claim.

**Solution**: Ensure the issuer URL is exactly:
```
https://login.microsoftonline.com/<tenant-id>/v2.0
```

### Issue: "Invalid audience" error

**Cause**: The token's `aud` claim doesn't match the configured audience.

**Solution**: Verify `--issuer-audiences` matches your Application (client) ID exactly.

### Issue: Groups not appearing in token

**Cause**: Groups claim not configured or user not in any groups.

**Solutions**:
1. Verify groups claim is configured in Token Configuration
2. Ensure user is a member of at least one security group
3. Check if the groups claim is returning Object IDs (not names)

### Issue: Token too large (HTTP 431)

**Cause**: User is in too many groups, causing the token to exceed size limits.

**Solutions**:
1. In Token Configuration, limit groups to "Security groups" only
2. Use "Groups assigned to the application" instead of "All groups"
3. Filter groups using group filtering in Entra ID

### Issue: Console redirect loop

**Cause**: Redirect URI mismatch.

**Solution**: 
1. Verify the redirect URI in Azure matches exactly:
   ```
   https://oauth-openshift.apps.rosa.<prefix>.<domain>/oauth2callback/<provider-name>
   ```
2. Ensure there are no trailing slashes or typos

### Issue: "Forbidden" after successful login

**Cause**: User authenticated but has no RBAC permissions.

**Solution**: 
1. Verify the user's group memberships in Azure AD
2. Check that ClusterRoleBindings use the correct group Object IDs
3. Use break glass to verify/fix RBAC configuration

### Debug: View token claims

To see what claims are in your token:

```bash
# Get and decode token
TOKEN=$(kubectl oidc-login get-token \
    --oidc-issuer-url=https://login.microsoftonline.com/${ENTRA_TENANT_ID}/v2.0 \
    --oidc-client-id=${ENTRA_CLIENT_ID} \
    --oidc-client-secret=${ENTRA_CLIENT_SECRET} \
    | jq -r '.status.token')

# Decode the JWT (middle section)
echo ${TOKEN} | cut -d'.' -f2 | base64 -d 2>/dev/null | jq .
```

---

## Quick Reference

### Environment Variables Summary

```bash
# Cluster
export ROSA_CLUSTER_NAME="your-cluster-name"
export PROVIDER_NAME="entra-id"

# Azure/Entra ID
export ENTRA_TENANT_ID="your-tenant-id"
export ENTRA_CLIENT_ID="your-client-id"
export ENTRA_CLIENT_SECRET="your-client-secret"

# Groups (Object IDs)
export ADMIN_GROUP_ID="your-admin-group-object-id"
export DEV_GROUP_ID="your-dev-group-object-id"
```

### Key URLs

| URL | Purpose |
|-----|---------|
| `https://login.microsoftonline.com/<tenant>/v2.0` | Issuer URL |
| `https://login.microsoftonline.com/<tenant>/v2.0/.well-known/openid-configuration` | OIDC Discovery |
| `https://oauth-openshift.apps.rosa.<prefix>.<domain>/oauth2callback/<provider>` | OAuth Callback |

### Useful Commands

```bash
# List external auth providers
rosa list external-auth-provider -c ${ROSA_CLUSTER_NAME}

# Delete and recreate provider (if needed)
rosa delete external-auth-provider -c ${ROSA_CLUSTER_NAME} --name ${PROVIDER_NAME}

# List break glass credentials
rosa list break-glass-credential -c ${ROSA_CLUSTER_NAME}

# Check RBAC bindings
oc get clusterrolebindings | grep entra

# View user's groups (after login)
oc whoami
oc auth can-i --list
```

---

## References

- [Red Hat: Configuring Microsoft Entra ID as External Auth Provider](https://cloud.redhat.com/experts/rosa/entra-external-auth/)
- [Microsoft: Register an application with Microsoft identity platform](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)
- [Microsoft: Configure group claims for applications](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-fed-group-claims)
- [kubelogin GitHub Repository](https://github.com/int128/kubelogin)
- [ROSA HCP External Auth Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_rosa_with_hcp_clusters/rosa-hcp-sts-creating-a-cluster-ext-auth)
