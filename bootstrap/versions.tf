terraform {
  # Exact pins (CLAUDE.md rule 5). Rule (D6): a release is at least 7 days
  # old before it is installed or pinned. Release dates, so this can be
  # checked: Terraform 1.17.1 (2026-10-28), azurerm 5.11.0 (2026-10-23),
  # azuread 3.10.0 (2026-09-24).
  required_version = "= 1.17.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.11.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "= 3.10.0"
    }
  }

  # No backend block: state is local and gitignored (D6). Keep an encrypted
  # copy outside the Mac after each apply.
}
