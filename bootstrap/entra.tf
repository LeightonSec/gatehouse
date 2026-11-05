# The gateway's app registration: the audience apps request tokens for (D8).
# It defines one app role, `invoke`, granted only to the three app identities.

data "azuread_client_config" "current" {}

locals {
  # App role IDs must be UUIDs. A name-based UUID keeps the ID stable across
  # runs without a random provider or a hard-coded GUID.
  invoke_role_id = uuidv5("url", "https://github.com/${var.github_owner}/${var.github_repo}/app-roles/invoke")
}

resource "azuread_application" "gateway" {
  display_name            = "gatehouse-gateway"
  sign_in_audience        = "AzureADMyOrg"
  owners                  = [data.azuread_client_config.current.object_id]
  prevent_duplicate_names = true

  api {
    # v2 tokens carry the gateway's client ID as the audience.
    requested_access_token_version = 2
  }

  app_role {
    allowed_member_types = ["Application"]
    description          = "Call the Gatehouse gateway."
    display_name         = "Invoke"
    enabled              = true
    id                   = local.invoke_role_id
    value                = "invoke"
  }
}

resource "azuread_service_principal" "gateway" {
  client_id = azuread_application.gateway.client_id
  owners    = [data.azuread_client_config.current.object_id]

  # Only identities granted `invoke` should get a token. Whether Entra enforces
  # this for app-only tokens is unverified (D8); the gateway checks `roles` anyway.
  app_role_assignment_required = true
}

resource "azuread_app_role_assignment" "app_invoke" {
  for_each = azurerm_user_assigned_identity.app

  app_role_id         = azuread_service_principal.gateway.app_role_ids["invoke"]
  principal_object_id = each.value.principal_id
  resource_object_id  = azuread_service_principal.gateway.object_id
}
