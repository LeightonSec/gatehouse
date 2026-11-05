# The three IDs scripts/configure-github.sh stores as environment secrets (D7).

output "deploy_client_id" {
  description = "Client ID of the deploy identity (AZURE_CLIENT_ID)."
  value       = azurerm_user_assigned_identity.deploy.client_id
}

output "tenant_id" {
  description = "Entra tenant ID (AZURE_TENANT_ID)."
  value       = var.tenant_id
}

output "subscription_id" {
  description = "Subscription ID (AZURE_SUBSCRIPTION_ID)."
  value       = var.subscription_id
}

# Used by the two scripts' read-back checks.

output "federated_subject" {
  description = "The OIDC subject the bootstrap built from tfvars."
  value       = local.github_subject
}

output "federated_credential_name" {
  value = azurerm_federated_identity_credential.github.name
}

output "deploy_identity_name" {
  value = azurerm_user_assigned_identity.deploy.name
}

output "deploy_principal_id" {
  value = azurerm_user_assigned_identity.deploy.principal_id
}

output "bootstrap_resource_group_name" {
  value = azurerm_resource_group.bootstrap.name
}

output "stack_resource_group_id" {
  value = azurerm_resource_group.stack.id
}

output "state_container_id" {
  value = azurerm_storage_container.tfstate.id
}

# Inputs for the main stack.

output "state_backend" {
  description = "Values for the main stack's azurerm backend."
  value = {
    resource_group_name  = azurerm_resource_group.bootstrap.name
    storage_account_name = azurerm_storage_account.state.name
    container_name       = azurerm_storage_container.tfstate.name
  }
}

output "stack_resource_group_name" {
  value = azurerm_resource_group.stack.name
}

output "app_identities" {
  description = "Per app: resource ID (to attach), client ID (gateway allowlist), principal ID."
  value = {
    for name, id in azurerm_user_assigned_identity.app : name => {
      id           = id.id
      client_id    = id.client_id
      principal_id = id.principal_id
    }
  }
}

output "gateway_client_id" {
  description = "The gateway app registration's client ID: the token audience (D8)."
  value       = azuread_application.gateway.client_id
}

# Read-back values for scripts/verify-bootstrap.sh.

output "gateway_service_principal_object_id" {
  value = azuread_service_principal.gateway.object_id
}

output "gateway_invoke_role_id" {
  value = local.invoke_role_id
}

output "rbac_admin_condition" {
  description = "The exact condition on the deploy identity's RBAC Administrator assignment."
  value       = local.rbac_admin_condition
}
