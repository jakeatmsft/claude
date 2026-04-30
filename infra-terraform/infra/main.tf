# ============================================================================
# Microsoft Foundry + Claude — Terraform (azd-driven)
# ----------------------------------------------------------------------------
# - Foundry account is created via `azapi_resource` so we can set
#   `allowProjectManagement = true` (required for child projects, not yet
#   exposed by `azurerm_cognitive_account`).
# - Claude deployment is also `azapi_resource` because `modelProviderData`
#   isn't yet exposed by `azurerm_cognitive_deployment` (issue #31140).
# ============================================================================

locals {
  tags = {
    "azd-env-name" = var.environment_name
  }
  account_name = "${var.base_name}-foundry-${random_string.suffix.result}"
  project_name = "${var.base_name}-proj-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.environment_name}"
  location = var.location
  tags     = local.tags
}

# --- Microsoft Foundry account (kind = AIServices) ------------------------
resource "azapi_resource" "foundry" {
  type      = "Microsoft.CognitiveServices/accounts@2025-10-01-preview"
  name      = local.account_name
  parent_id = azurerm_resource_group.rg.id
  location  = azurerm_resource_group.rg.location
  tags      = local.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      customSubDomainName    = local.account_name
      allowProjectManagement = true
      publicNetworkAccess    = "Enabled"
      disableLocalAuth       = false
    }
  }

  response_export_values = ["name", "identity.principalId"]
}

# --- Foundry project ------------------------------------------------------
resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview"
  name      = local.project_name
  parent_id = azapi_resource.foundry.id
  location  = azurerm_resource_group.rg.location
  tags      = local.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {}
  }

  response_export_values = ["name"]
}

# --- Claude deployment ----------------------------------------------------
resource "azapi_resource" "claude" {
  type                      = "Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview"
  name                      = "${var.model_name}-${substr(random_string.suffix.result, 0, 6)}"
  parent_id                 = azapi_resource.foundry.id
  schema_validation_enabled = false # required to allow modelProviderData

  body = {
    sku = {
      name     = "GlobalStandard"
      capacity = tonumber(var.model_capacity)
    }
    properties = {
      model = {
        # `Anthropic` is the on-the-wire format literal in the Foundry catalog.
        format  = "Anthropic"
        name    = var.model_name
        version = var.model_version
      }
      # REQUIRED for Claude. `industry` MUST be lowercase.
      modelProviderData = {
        organizationName = var.claude_organization_name
        countryCode      = var.claude_country_code
        industry         = var.claude_industry
      }
      versionUpgradeOption = "OnceNewDefaultVersionAvailable"
      raiPolicyName        = "Microsoft.DefaultV2"
    }
  }

  response_export_values = ["name"]

  depends_on = [azapi_resource.project]
}

# --- Optional RBAC --------------------------------------------------------
# Set `assign_rbac = true` (via azd: `azd env set ASSIGN_RBAC true`) to grant
# Azure AI User + Azure AI Project Manager to `principal_id`. Requires the
# deployer to have Microsoft.Authorization/roleAssignments/write.
resource "azurerm_role_assignment" "ai_user" {
  count                = lower(var.assign_rbac) == "true" && var.principal_id != "" ? 1 : 0
  scope                = azapi_resource.foundry.id
  role_definition_name = "Azure AI User"
  principal_id         = var.principal_id
}

resource "azurerm_role_assignment" "ai_project_manager" {
  count                = lower(var.assign_rbac) == "true" && var.principal_id != "" ? 1 : 0
  scope                = azapi_resource.foundry.id
  role_definition_name = "Azure AI Project Manager"
  principal_id         = var.principal_id
}
