// ============================================================================
// Microsoft Foundry + Claude — Bicep (azd-driven)
// ----------------------------------------------------------------------------
// `modelProviderData` is REQUIRED for Claude deployments. `industry`
// MUST be lowercase to match the Foundry portal dropdown.
// `allowProjectManagement = true` is required to create projects under the
// Foundry account.
// ============================================================================
targetScope = 'subscription'

@description('azd environment name. Used for resource group + tagging.')
param environmentName string

@description('Azure region. Claude in Foundry: eastus2 or swedencentral (or westus2 for opus).')
@allowed([
  'eastus2'
  'swedencentral'
  'westus2'
])
param location string

@description('Object id of the deploying user/SP. Empty disables RBAC.')
param principalId string = ''

@description('Whether to assign Azure AI User / Project Manager to principalId. Set to "true" to enable.')
param assignRbac string = 'false'

@description('Short prefix for resource names.')
param baseName string = 'claude'

@allowed([
  'claude-haiku-4-5'
  'claude-sonnet-4-5'
  'claude-sonnet-4-6'
  'claude-opus-4-1'
  'claude-opus-4-5'
  'claude-opus-4-6'
  'claude-opus-4-7'
])
param modelName string = 'claude-sonnet-4-6'
param modelVersion string = '1'
param modelCapacity int = 50

@description('Organization name surfaced via modelProviderData.')
param claudeOrganizationName string
@description('Two-letter ISO country code.')
@minLength(2)
@maxLength(2)
param claudeCountryCode string = 'US'
@description('Industry — MUST be lowercase to match Foundry portal dropdown.')
@allowed([
  'technology'
  'finance'
  'healthcare'
  'education'
  'retail'
  'manufacturing'
  'government'
  'media'
  'other'
])
param claudeIndustry string = 'technology'

var tags = {
  'azd-env-name': environmentName
}
var suffix = take(uniqueString(subscription().id, environmentName), 8)
var accountName = '${baseName}-foundry-${suffix}'
var projectName = '${baseName}-proj-${suffix}'
var deploymentName = '${modelName}-${take(suffix, 6)}'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module foundry 'foundry.bicep' = {
  name: 'foundry-deploy'
  scope: rg
  params: {
    location: location
    tags: tags
    accountName: accountName
    projectName: projectName
    deploymentName: deploymentName
    modelName: modelName
    modelVersion: modelVersion
    modelCapacity: modelCapacity
    claudeOrganizationName: claudeOrganizationName
    claudeCountryCode: claudeCountryCode
    claudeIndustry: claudeIndustry
    principalId: principalId
    assignRbac: assignRbac
  }
}

output CLAUDE_BASE_URL string = foundry.outputs.claudeBaseUrl
output FOUNDRY_PROJECT_ENDPOINT string = foundry.outputs.foundryProjectEndpoint
output CLAUDE_DEPLOYMENT_NAME string = foundry.outputs.claudeDeploymentName
output FOUNDRY_ACCOUNT_NAME string = foundry.outputs.foundryAccountName
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_LOCATION string = location
