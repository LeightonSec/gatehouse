# Both providers authenticate with Leighton's `az login`. The subscription and
# tenant are pinned explicitly so the bootstrap can never run against whatever
# subscription the CLI happens to have selected.

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  # Shared-key access is disabled on the state account, so any storage
  # data-plane call must use Entra.
  storage_use_azuread = true

  # Never register resource providers as a side effect. azurerm 5.11.0 already
  # defaults to "none"; setting it means the behaviour doesn't depend on that.
  resource_provider_registrations = "none"
}

provider "azuread" {
  tenant_id = var.tenant_id
}
