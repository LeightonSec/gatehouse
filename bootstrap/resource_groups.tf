# Two resource groups (D6). The split stops the deploy identity from
# controlling the group that contains itself.

resource "azurerm_resource_group" "bootstrap" {
  name     = var.bootstrap_resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "stack" {
  name     = var.stack_resource_group_name
  location = var.location
  tags     = var.tags
}
