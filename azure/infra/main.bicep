// Example Azure Function App (Flex Consumption, .NET isolated) + storage + Application Insights.
// Deployed into the CLIENT's subscription, separately from the Dataverse pipeline (azure/scripts/Deploy-Azure.ps1).
// Storage uses the function's managed identity only (no account keys).

@description('Short lowercase base name (letters/digits), e.g. acmecrm.')
@minLength(2)
@maxLength(12)
param baseName string

@allowed(['test', 'prod'])
param environmentName string

param location string = resourceGroup().location

@description('Dataverse environment URL the function works with (app setting DataverseUrl).')
param dataverseUrl string

@description('.NET isolated worker version.')
param dotnetVersion string = '8.0'

var suffix = '${baseName}-${environmentName}'
var storageName = take('st${baseName}${environmentName}${uniqueString(resourceGroup().id)}', 24)
var deploymentContainer = 'app-package'

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${suffix}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${suffix}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource packageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: deploymentContainer
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'asp-${suffix}'
  location: location
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: 'func-${suffix}'
  location: location
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      appSettings: [
        { name: 'AzureWebJobsStorage__accountName', value: storage.name }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'DataverseUrl', value: dataverseUrl }
      ]
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentContainer}'
          authentication: { type: 'SystemAssignedIdentity' }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'dotnet-isolated'
        version: dotnetVersion
      }
    }
  }
  dependsOn: [packageContainer]
}

// Identity-based host storage: Blob Data Owner, Queue Data Contributor, Table Data Contributor.
var storageRoles = [
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
]

resource storageRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in storageRoles: {
  scope: storage
  name: guid(storage.id, functionApp.id, roleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}]

output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
@description('Object ID of the managed identity. Its Application ID (Entra > Enterprise applications) is what you add as a Dataverse application user.')
output principalId string = functionApp.identity.principalId
