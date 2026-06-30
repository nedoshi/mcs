locals {
  rhcs_use_token = try(var.token != null && var.token != "", false)
  rhcs_use_client = (
    try(var.client_id != null && var.client_id != "", false) &&
    try(var.client_secret != null && var.client_secret != "", false)
  )
}

check "rhcs_auth_configured" {
  assert {
    condition     = local.rhcs_use_token || local.rhcs_use_client
    error_message = "Provide client_id and client_secret (recommended for CI), or token (optional). Use one method only."
  }
}

check "rhcs_auth_exclusive" {
  assert {
    condition     = !(local.rhcs_use_token && local.rhcs_use_client)
    error_message = "Use either token or client_id/client_secret, not both."
  }
}
