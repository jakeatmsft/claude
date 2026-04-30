# ---------------------------------------------------------------------------
# azd-injected variables (populated from `azd env` values via main.tfvars.json)
# ---------------------------------------------------------------------------
variable "environment_name" {
  description = "azd environment name. Used for resource group + tagging."
  type        = string
}

variable "location" {
  description = "Azure region. Claude in Foundry: eastus2 or swedencentral (or westus2 for opus-only)."
  type        = string
  validation {
    condition     = contains(["eastus2", "swedencentral", "westus2"], var.location)
    error_message = "location must be eastus2, swedencentral, or westus2 (opus only)."
  }
}

variable "subscription_id" {
  description = "Target Azure subscription id."
  type        = string
}

variable "principal_id" {
  description = "Object id of the deploying user/SP. Empty disables RBAC."
  type        = string
  default     = ""
}

variable "assign_rbac" {
  description = "Whether to assign Azure AI User / Project Manager to principal_id. Set to \"true\" to enable. Requires Microsoft.Authorization/roleAssignments/write on the deployer."
  type        = string
  default     = "false"
}

# ---------------------------------------------------------------------------
# Naming
# ---------------------------------------------------------------------------
variable "base_name" {
  description = "Short prefix for resource names."
  type        = string
  default     = "claude"
}

# ---------------------------------------------------------------------------
# Claude model
# ---------------------------------------------------------------------------
variable "model_name" {
  description = "Claude model id."
  type        = string
  default     = "claude-sonnet-4-6"
  validation {
    condition = contains([
      "claude-haiku-4-5",
      "claude-sonnet-4-5",
      "claude-sonnet-4-6",
      "claude-opus-4-1",
      "claude-opus-4-5",
      "claude-opus-4-6",
      "claude-opus-4-7",
    ], var.model_name)
    error_message = "Unsupported Claude model."
  }
}

variable "model_version" {
  description = "Model version string. Use \"1\" for newest preview models."
  type        = string
  default     = "1"
}

variable "model_capacity" {
  description = "Deployment capacity (TPM / 1000). Sent as string from azd, converted to number."
  type        = string
  default     = "50"
}

# ---------------------------------------------------------------------------
# modelProviderData (REQUIRED by Foundry for Claude deployments)
# ---------------------------------------------------------------------------
variable "claude_organization_name" {
  description = "Organization name surfaced via modelProviderData."
  type        = string
}

variable "claude_country_code" {
  description = "Two-letter ISO country code (e.g. US, GB, DE)."
  type        = string
  default     = "US"
  validation {
    condition     = length(var.claude_country_code) == 2
    error_message = "Must be a 2-letter country code."
  }
}

variable "claude_industry" {
  description = "Industry — MUST be lowercase to match Foundry portal dropdown."
  type        = string
  default     = "technology"
  validation {
    condition = contains([
      "technology", "finance", "healthcare", "education",
      "retail", "manufacturing", "government", "media", "other",
    ], var.claude_industry)
    error_message = "industry must be a lowercase value supported by the Foundry portal."
  }
}
