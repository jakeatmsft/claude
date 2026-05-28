output "CLAUDE_BASE_URL" {
  description = "Claude SDK base URL. The SDK appends /v1/messages internally."
  value       = "https://${azapi_resource.foundry.name}.services.ai.azure.com/anthropic"
}

output "FOUNDRY_PROJECT_ENDPOINT" {
  description = "Foundry project endpoint (Agents SDK / Foundry Projects)."
  value       = "https://${azapi_resource.foundry.name}.services.ai.azure.com/api/projects/${azapi_resource.project.name}"
}

output "FOUNDRY_ACCOUNT_NAME" {
  value = azapi_resource.foundry.name
}

output "AZURE_RESOURCE_GROUP" {
  value = azurerm_resource_group.rg.name
}

output "AZURE_LOCATION" {
  value = var.location
}

# --- Per-family deployment names. Empty when that family wasn't deployed. ---
output "CLAUDE_HAIKU_DEPLOYMENT_NAME" {
  description = "Deployment name for the haiku family (empty if not deployed)."
  value       = length(azapi_resource.claude_haiku) > 0 ? azapi_resource.claude_haiku[0].name : ""
}

output "CLAUDE_SONNET_DEPLOYMENT_NAME" {
  description = "Deployment name for the sonnet family (empty if not deployed)."
  value       = length(azapi_resource.claude_sonnet) > 0 ? azapi_resource.claude_sonnet[0].name : ""
}

output "CLAUDE_OPUS_DEPLOYMENT_NAME" {
  description = "Deployment name for the opus family (empty if not deployed)."
  value       = length(azapi_resource.claude_opus) > 0 ? azapi_resource.claude_opus[0].name : ""
}

# --- Legacy single-deployment-name output for back-compat with older
# configure-claude-code scripts. Picks sonnet > opus > haiku as priority. ---
output "CLAUDE_DEPLOYMENT_NAME" {
  description = "Legacy single-deployment name. Set to the first non-empty family deployment."
  value = length(azapi_resource.claude_sonnet) > 0 ? azapi_resource.claude_sonnet[0].name : (
    length(azapi_resource.claude_opus) > 0 ? azapi_resource.claude_opus[0].name : (
      length(azapi_resource.claude_haiku) > 0 ? azapi_resource.claude_haiku[0].name : ""
    )
  )
}
