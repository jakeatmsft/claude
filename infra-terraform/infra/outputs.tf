output "CLAUDE_BASE_URL" {
  description = "Claude SDK base URL. The SDK appends /v1/messages internally."
  value       = "https://${azapi_resource.foundry.name}.services.ai.azure.com/anthropic"
}

output "FOUNDRY_PROJECT_ENDPOINT" {
  description = "Foundry project endpoint (Agents SDK / Foundry Projects)."
  value       = "https://${azapi_resource.foundry.name}.services.ai.azure.com/api/projects/${azapi_resource.project.name}"
}

output "CLAUDE_DEPLOYMENT_NAME" {
  description = "Pass this as the `model` parameter in Messages API calls."
  value       = azapi_resource.claude.name
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
