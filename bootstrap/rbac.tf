# Every role the deploy identity holds, in one file (D7, T13). Nothing at
# subscription scope, nothing on the bootstrap resource group itself.

locals {
  # The only roles the deploy identity may grant (D4, D7). Committed here, not
  # in tfvars, so anyone reading the repo can see exactly what CI can grant.
  grantable_role_names = ["Cognitive Services OpenAI User"]

  # Exact permissions of each grantable role, read from Azure on 2026-11-04
  # (az role definition list). If Microsoft changes a role, plan fails and the
  # role is re-reviewed before CI can grant it (D4, D7).
  expected_role_permissions = {
    "Cognitive Services OpenAI User" = {
      actions = [
        "Microsoft.CognitiveServices/*/read",
        "Microsoft.Authorization/roleAssignments/read",
        "Microsoft.Authorization/roleDefinitions/read",
      ]
      not_actions = []
      data_actions = [
        "Microsoft.CognitiveServices/accounts/OpenAI/*/read",
        "Microsoft.CognitiveServices/accounts/OpenAI/engines/completions/action",
        "Microsoft.CognitiveServices/accounts/OpenAI/engines/search/action",
        "Microsoft.CognitiveServices/accounts/OpenAI/engines/generate/action",
        "Microsoft.CognitiveServices/accounts/OpenAI/deployments/audio/action",
        "Microsoft.CognitiveServices/accounts/OpenAI/deployments/search/action",
        "Microsoft.CognitiveServices/accounts/OpenAI/deployments/completions/action",
        "Microsoft.CognitiveServices/accounts/OpenAI/deployments/chat/completions/action",
        "Microsoft.CognitiveServices/accounts/OpenAI/deployments/realtime/action",
        "Microsoft.CognitiveServices/accounts/OpenAI/deployments/extensions/chat/completions/action",
        "Microsoft.CognitiveServices/accounts/OpenAI/deployments/embeddings/action",
        "Microsoft.CognitiveServices/accounts/OpenAI/images/generations/action",
        "Microsoft.CognitiveServices/accounts/OpenAI/video/generations/*/action",
        "Microsoft.CognitiveServices/accounts/OpenAI/video/generations/*/delete",
        "Microsoft.CognitiveServices/accounts/OpenAI/assistants/*",
        "Microsoft.CognitiveServices/accounts/OpenAI/responses/*",
      ]
      not_data_actions = [
        "Microsoft.CognitiveServices/accounts/OpenAI/stored-completions/read",
      ]
    }
  }
}

data "azurerm_role_definition" "grantable" {
  for_each = toset(local.grantable_role_names)

  # Subscription scope, known at plan time, so this lookup and its
  # postcondition run at plan even on the first run. A scope created by this
  # bootstrap would push both to apply. Built-in roles are identical at every
  # scope, and only the role's GUID is used.
  name  = each.value
  scope = "/subscriptions/${var.subscription_id}"

  lifecycle {
    postcondition {
      condition = alltrue([
        for k in ["actions", "not_actions", "data_actions", "not_data_actions"] :
        join("\n", sort(flatten([for p in self.permissions : p[k]]))) ==
        join("\n", sort(local.expected_role_permissions[each.value][k]))
      ])
      error_message = "The permissions of ${each.value} differ from the snapshot reviewed on 2026-11-04 (D4). Re-review the role before applying."
    }
  }
}

locals {
  deploy_principal_id  = azurerm_user_assigned_identity.deploy.principal_id
  grantable_role_guids = join(", ", [for r in data.azurerm_role_definition.grantable : r.role_definition_id])

  # The deploy identity may create or delete role assignments only for the
  # grantable roles, and may create them only for service principals (which
  # includes managed identities), never users or groups.
  rbac_admin_condition = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.grantable_role_guids}}
      AND
      @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.grantable_role_guids}}
     )
    )
  EOT
}

# 1. Deploy the main stack into rg-gatehouse.
resource "azurerm_role_assignment" "deploy_contributor_stack" {
  scope                = azurerm_resource_group.stack.id
  role_definition_name = "Contributor"
  principal_id         = local.deploy_principal_id
  principal_type       = "ServicePrincipal"
  description          = "Gatehouse CI: deploy the main stack (D7)."
}

# 2. Grant only the listed roles, only to service principals, only in rg-gatehouse.
resource "azurerm_role_assignment" "deploy_rbac_admin_stack" {
  scope                = azurerm_resource_group.stack.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = local.deploy_principal_id
  principal_type       = "ServicePrincipal"
  condition            = local.rbac_admin_condition
  condition_version    = "2.0"
  description          = "Gatehouse CI: constrained role grants (D7)."
}

# 3. Read and write the main stack's state, and nothing else in the state account.
resource "azurerm_role_assignment" "deploy_state_blob" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.deploy_principal_id
  principal_type       = "ServicePrincipal"
  description          = "Gatehouse CI: main stack state (D6)."
}

# 4. Attach each app identity to its container, one assignment per identity,
#    never on the resource group (D7).
resource "azurerm_role_assignment" "deploy_mi_operator_app" {
  for_each = azurerm_user_assigned_identity.app

  scope                = each.value.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = local.deploy_principal_id
  principal_type       = "ServicePrincipal"
  description          = "Gatehouse CI: attach app identity ${each.key} (D7)."
}
