// Foundry account + project + Claude deployment + optional RBAC.
param location string
param tags object
param accountName string
param projectName string
param deploymentName string
param modelName string
param modelVersion string
param modelCapacity int
param claudeOrganizationName string
param claudeCountryCode string
param claudeIndustry string
param principalId string
param assignRbac string

var rbacEnabled = toLower(assignRbac) == 'true' && !empty(principalId)

// Built-in role definition IDs.
var azureAiUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
var azureAiProjectManagerRoleId = 'eadc314b-1a2d-4efa-be10-5d325db5065e'

resource account 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' = {
  name: accountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: accountName
    allowProjectManagement: true
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

resource claudeDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview' = {
  parent: account
  name: deploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      // `Anthropic` is the on-the-wire format literal in the Foundry catalog.
      format: 'Anthropic'
      name: modelName
      version: modelVersion
    }
    // REQUIRED for Claude. `industry` must be lowercase.
    modelProviderData: {
      organizationName: claudeOrganizationName
      countryCode: claudeCountryCode
      industry: claudeIndustry
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
  dependsOn: [
    project
  ]
}

resource aiUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (rbacEnabled) {
  name: guid(account.id, principalId, azureAiUserRoleId)
  scope: account
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAiUserRoleId)
    principalId: principalId
    principalType: 'User'
  }
}

resource aiProjectManagerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (rbacEnabled) {
  name: guid(account.id, principalId, azureAiProjectManagerRoleId)
  scope: account
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAiProjectManagerRoleId)
    principalId: principalId
    principalType: 'User'
  }
}

output claudeBaseUrl string = 'https://${account.name}.services.ai.azure.com/anthropic'
output foundryProjectEndpoint string = 'https://${account.name}.services.ai.azure.com/api/projects/${project.name}'
output claudeDeploymentName string = claudeDeployment.name
output foundryAccountName string = account.name
