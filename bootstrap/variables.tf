# IDs come from the uncommitted terraform.tfvars, never from this repo (D2).

variable "subscription_id" {
  description = "Azure subscription the bootstrap deploys into."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lowercase GUID."
  }
}

variable "tenant_id" {
  description = "Entra tenant that owns the subscription."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "tenant_id must be a lowercase GUID."
  }
}

variable "location" {
  description = "Region for all bootstrap resources (D5). The DR drill reruns the bootstrap with the DR region."
  type        = string
  default     = "swedencentral"
}

variable "bootstrap_resource_group_name" {
  description = "Holds the state account, the deploy identity and the app identities. The deploy identity has no control rights here (D6)."
  type        = string
  default     = "rg-gatehouse-bootstrap"
}

variable "stack_resource_group_name" {
  description = "Where CI deploys the main stack (D6)."
  type        = string
  default     = "rg-gatehouse"
}

variable "state_storage_account_name" {
  description = "Globally unique name for the remote-state storage account."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.state_storage_account_name))
    error_message = "Storage account names are 3 to 24 lowercase letters and digits."
  }
}

variable "state_container_name" {
  description = "Blob container for the main stack's remote state."
  type        = string
  default     = "tfstate"
}

variable "github_owner" {
  description = "GitHub owner name, used in the OIDC subject (D7)."
  type        = string
  default     = "LeightonSec"
}

variable "github_repo" {
  description = "GitHub repository name, used in the OIDC subject (D7)."
  type        = string
  default     = "gatehouse"
}

variable "github_owner_id" {
  description = "Numeric GitHub owner ID. Required by the immutable subject format (D7)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be the numeric owner ID."
  }
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID. Required by the immutable subject format (D7)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repo_id))
    error_message = "github_repo_id must be the numeric repository ID."
  }
}

variable "github_environment" {
  description = "GitHub environment the deploy identity trusts (D7)."
  type        = string
  default     = "azure"
}

variable "app_names" {
  description = "One user-assigned identity per simulated app (D8)."
  type        = set(string)
  default     = ["hr", "support", "code"]

  validation {
    condition     = alltrue([for n in var.app_names : can(regex("^[a-z0-9-]{1,20}$", n))])
    error_message = "App names are 1 to 20 lowercase letters, digits or dashes."
  }
}

variable "tags" {
  description = "Tags applied to every Azure resource."
  type        = map(string)
  default = {
    project    = "gatehouse"
    managed_by = "terraform-bootstrap"
  }
}
