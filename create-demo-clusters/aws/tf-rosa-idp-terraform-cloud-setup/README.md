# ROSA IDP Setup and Terraform Cloud Integration

This guide provides step-by-step instructions for:
1. Setting up Terraform Cloud as a remote backend to access ROSA cluster information
2. Creating an OpenID Connect (OIDC) Identity Provider (IDP) using Azure AD for ROSA clusters
3. Connecting to your ROSA cluster using information from Terraform Cloud outputs

## Overview

This configuration enables you to:
- Store Terraform state in Terraform Cloud for centralized state management
- Access cluster connection details from Terraform Cloud workspace outputs
- Configure Azure AD as an OIDC identity provider for cluster authentication
- Authenticate users via Azure AD to access your ROSA cluster

## Prerequisites

Before you begin, ensure you have:

1. **ROSA Cluster**: A ROSA cluster already created using the `tf-rosa` module
2. **Terraform Cloud Account**: Sign up at https://app.terraform.io if you don't have one
3. **Terraform Cloud Token**: Generate one at https://app.terraform.io/app/settings/tokens
4. **Azure AD Tenant**: Access to an Azure AD tenant with permissions to create App Registrations
5. **OCM Credentials**: Either:
   - OCM token from https://console.redhat.com/openshift/token/rosa/show, OR
   - Client ID and Client Secret for RHCS API
6. **Terraform**: Version >= 1.0 installed locally
7. **AWS CLI**: Configured with appropriate credentials
8. **OpenShift CLI (oc)**: Installed for cluster access

## Part 1: Setting up Terraform Cloud Backend

### Step 1: Create Terraform Cloud Workspace

1. Log in to [Terraform Cloud](https://app.terraform.io)
2. Create a new organization (if you don't have one)
3. Create a new workspace:
   - Choose "CLI-driven workflow"
   - Name it something like `rosa-cluster-idp-setup`
   - Select your organization

### Step 2: Configure Terraform Cloud Backend

The `terraform.tf` file in this directory is already configured for Terraform Cloud. You need to:

1. Set your Terraform Cloud token as an environment variable:
   ```bash
   export TF_TOKEN_app_terraform_io="your-terraform-cloud-token"
   ```

2. Update `terraform.tf` with your organization and workspace names:
   ```hcl
   backend "remote" {
     organization = "your-organization-name"
     workspaces {
       name = "rosa-cluster-idp-setup"
     }
   }
   ```

### Step 3: Access Cluster Information from tf-rosa Workspace

If your ROSA cluster was created in a separate Terraform Cloud workspace, you can access its outputs using a data source. See `data-source-example.tf` for examples.

**Option A: Using terraform_remote_state data source**

If both workspaces are in the same Terraform Cloud organization, you can use:

```hcl
data "terraform_remote_state" "rosa_cluster" {
  backend = "remote"
  config = {
    organization = "your-organization-name"
    workspaces {
      name = "your-rosa-cluster-workspace-name"
    }
  }
}
```

Then reference outputs:
```hcl
cluster_id = data.terraform_remote_state.rosa_cluster.outputs.cluster_id
```

**Option B: Using Terraform Cloud API**

Alternatively, you can fetch outputs using the Terraform Cloud API or manually copy them to your variables.

### Step 4: Initialize Terraform

```bash
terraform init
```

When prompted, confirm migrating state to Terraform Cloud.

## Part 2: Creating Azure AD OIDC IDP

### Step 1: Create Azure AD App Registration

1. Log in to [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Active Directory** > **App registrations**
3. Click **New registration**
4. Configure the app:
   - **Name**: `ROSA-Cluster-OIDC` (or your preferred name)
   - **Supported account types**: Choose based on your needs
   - **Redirect URI**: 
     - Type: **Web**
     - URI: `https://oauth-openshift.apps.<cluster-domain>/oauth2callback/<idp-name>`
     - Replace `<cluster-domain>` with your cluster's domain (e.g., `mycluster.abc123.p1.openshiftapps.com`)
     - Replace `<idp-name>` with your desired IDP name (e.g., `azure-ad`)
   - Click **Register**

### Step 2: Configure App Registration

1. **Note the Application (client) ID**: Copy this value - you'll need it for Terraform
2. **Create a Client Secret**:
   - Go to **Certificates & secrets**
   - Click **New client secret**
   - Add description and expiration
   - **Copy the secret value immediately** - it won't be shown again
3. **Configure API Permissions**:
   - Go to **API permissions**
   - Click **Add a permission** > **Microsoft Graph** > **Delegated permissions**
   - Add: `openid`, `profile`, `email`, `User.Read`
   - Click **Add permissions**
   - **Grant admin consent** if required

### Step 3: Configure Optional Claims (for Groups)

If you want to map Azure AD groups to OpenShift groups:

1. Go to **Token configuration**
2. Click **Add optional claim**
3. Select **ID** token
4. Check **groups**
5. Click **Add**

### Step 4: Get Azure AD Tenant Information

1. Go to **Overview** in your App Registration
2. Note your **Directory (tenant) ID**
3. The issuer URL format is: `https://login.microsoftonline.com/<tenant-id>/v2.0`

### Step 5: Configure Terraform

1. Copy `terraform.tfvars.example` to `terraform.tfvars`:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Update `terraform.tfvars` with your values:
   ```hcl
   # Cluster information (from Terraform Cloud outputs or manual entry)
   cluster_id = "your-cluster-id"
   
   # Azure AD OIDC Configuration
   azure_ad_tenant_id     = "your-azure-tenant-id"
   azure_ad_client_id     = "your-azure-client-id"
   azure_ad_client_secret = "your-azure-client-secret"
   idp_name               = "azure-ad"
   
   # RHCS Authentication
   client_id     = "your-rhcs-client-id"
   client_secret = "your-rhcs-client-secret"
   ```

3. Review `idp-azure-ad.tf` - it's already configured with the OIDC provider settings

### Step 6: Apply Terraform Configuration

```bash
terraform plan
terraform apply
```

This will create the OIDC identity provider in your ROSA cluster.

## Part 3: Connecting to Cluster

### Step 1: Get Cluster Connection Details from Terraform Cloud

You can retrieve cluster information from Terraform Cloud outputs:

**Using Terraform CLI:**
```bash
# Get cluster API URL
terraform output -raw cluster_api_url

# Get cluster console URL
terraform output -raw cluster_console_url

# Get cluster ID
terraform output -raw cluster_id
```

**Using Terraform Cloud Web UI:**
1. Navigate to your workspace in Terraform Cloud
2. Go to **Outputs** tab
3. View all available outputs

### Step 2: Configure OpenShift CLI

1. **Get the cluster API URL**:
   ```bash
   CLUSTER_API_URL=$(terraform output -raw cluster_api_url)
   ```

2. **Login using Azure AD**:
   ```bash
   oc login $CLUSTER_API_URL
   ```
   
   You'll be redirected to Azure AD for authentication. After successful authentication, you'll be logged in to the cluster.

### Step 3: Verify Authentication

```bash
# Check current user
oc whoami

# List available projects
oc get projects
```

### Step 4: Configure RBAC (Optional)

By default, Azure AD users may not have cluster permissions. You can grant access:

**Grant cluster-admin to a user:**
```bash
oc adm policy add-cluster-role-to-user cluster-admin <azure-ad-username>
```

**Grant access to a specific group:**
If you configured group claims, you can map Azure AD groups to OpenShift groups:
```bash
# Create an OpenShift group
oc adm groups new developers

# Add Azure AD users to the group (users will be added automatically via group claims)
# Or manually add users:
oc adm groups add-users developers <azure-ad-username>

# Grant permissions to the group
oc adm policy add-role-to-group edit developers
```

## Troubleshooting

### IDP Not Appearing in Console

- Verify the IDP was created successfully: `terraform show`
- Check the cluster console - it may take a few minutes to appear
- Verify redirect URI matches exactly (including trailing slashes)

### Authentication Fails

- Verify Azure AD client ID and secret are correct
- Check redirect URI in Azure AD matches the cluster's OAuth callback URL
- Ensure Azure AD app has required permissions and admin consent granted
- Check cluster logs: `oc logs -n openshift-authentication deployment/oauth-openshift`

### Cannot Access Terraform Cloud Outputs

- Verify Terraform Cloud token is set: `echo $TF_TOKEN_app_terraform_io`
- Check workspace name and organization are correct
- Ensure you have read access to the source workspace
- Try using `terraform refresh` to update state

### Azure AD Groups Not Mapping

- Verify optional claims are configured in Azure AD
- Check the claims configuration in `idp-azure-ad.tf` matches your Azure AD setup
- Ensure users are assigned to groups in Azure AD
- Review OpenShift authentication logs

## Variables Reference

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `cluster_id` | ROSA cluster ID | Yes | - |
| `azure_ad_tenant_id` | Azure AD tenant ID | Yes | - |
| `azure_ad_client_id` | Azure AD application (client) ID | Yes | - |
| `azure_ad_client_secret` | Azure AD client secret | Yes | - |
| `idp_name` | Name for the identity provider | No | `azure-ad` |
| `client_id` | RHCS API client ID | Yes* | - |
| `client_secret` | RHCS API client secret | Yes* | - |
| `token` | OCM token (alternative to client_id/secret) | Yes* | - |
| `region` | AWS region | No | `us-east-1` |

*Either `token` OR `client_id`/`client_secret` must be provided

## Outputs

After applying the configuration, Terraform will output:

- `idp_name`: Name of the created identity provider
- `cluster_id`: ROSA cluster ID
- `cluster_api_url`: Cluster API endpoint URL
- `cluster_console_url`: OpenShift web console URL

## Cleanup

To remove the IDP:

```bash
terraform destroy
```

**Note**: This only removes the IDP configuration. It does not delete the Azure AD App Registration or the ROSA cluster.

## Additional Resources

- [ROSA Identity Provider Documentation](https://docs.openshift.com/rosa/authentication/sd-configuring-identity-providers.html)
- [Azure AD App Registration Guide](https://docs.microsoft.com/azure/active-directory/develop/quickstart-register-app)
- [Terraform Cloud Backend Documentation](https://www.terraform.io/docs/cloud/workspaces/remote.html)
- [OpenShift OAuth Configuration](https://docs.openshift.com/container-platform/latest/authentication/understanding-authentication.html)

## Support

For issues or questions:
- Check the [ROSA Documentation](https://docs.openshift.com/rosa/)
- Review Terraform Cloud [documentation](https://www.terraform.io/docs/cloud/)
- Open an issue in the repository
- Contact Red Hat Support

