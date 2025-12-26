# Azure AD OIDC Identity Provider for ROSA Cluster
#
# This configuration creates an OpenID Connect (OIDC) identity provider
# using Azure AD for authentication to your ROSA cluster.

resource "rhcs_identity_provider" "azure_ad" {
  cluster = var.cluster_id
  name    = var.idp_name

  openid = {
    # Azure AD OIDC issuer URL
    # Format: https://login.microsoftonline.com/<tenant-id>/v2.0
    issuer = "https://login.microsoftonline.com/${var.azure_ad_tenant_id}/v2.0"

    # Azure AD Application (Client) ID
    client_id = var.azure_ad_client_id

    # Azure AD Client Secret
    client_secret = var.azure_ad_client_secret

    # OAuth2 scopes to request
    # These scopes determine what user information is available in the token
    scopes = ["openid", "profile", "email"]

    # Claims configuration
    # Maps OIDC token claims to OpenShift user attributes
    claims = {
      # Username claim - maps to OpenShift username
      # Common options: "email", "preferred_username", "upn", "sub"
      username = ["email", "preferred_username"]

      # Display name claim - shown in OpenShift console
      name = ["name"]

      # Email claim
      email = ["email"]

      # Groups claim - used for group-based RBAC
      # Requires "groups" optional claim to be enabled in Azure AD
      # If not using groups, you can omit this or set to empty list
      groups = ["groups"]
    }

    # CA bundle (optional)
    # Only needed if using a custom CA for Azure AD
    # ca = null
  }
}

# Output the IDP name for reference
output "idp_name" {
  description = "Name of the created identity provider"
  value       = rhcs_identity_provider.azure_ad.name
}

output "cluster_id" {
  description = "ROSA cluster ID"
  value       = var.cluster_id
}

