// Account list web app: Windows App Service (ASP.NET Core MVC, .NET 10) behind Entra sign-in (Easy Auth),
// calling Dataverse through an API Management (Consumption) facade. No secrets anywhere:
//   browser --Easy Auth--> web app --web app managed identity token (aud = accounts API)--> APIM
//   APIM --validates token, calls Dataverse with its own managed identity--> Dataverse Web API
// Deployed into the CLIENT's subscription, separately from the Dataverse pipeline (azure/scripts/Deploy-Azure.ps1).
// The two Entra app registrations (web sign-in, accounts API audience) are created by Deploy-Azure.ps1 and passed in.

@description('Short lowercase base name (letters/digits), e.g. acmecrm.')
@minLength(2)
@maxLength(12)
param baseName string

@allowed(['dev', 'test', 'prod'])
param environmentName string

param location string = resourceGroup().location

@description('Dataverse environment URL, without trailing slash, e.g. https://contoso.crm4.dynamics.com.')
param dataverseUrl string

@description('App Service plan SKU. F1/D1 are shared tiers: 32-bit worker, no Always On.')
@allowed(['F1', 'D1', 'B1', 'B2', 'S1', 'P0v3', 'P1v3'])
param appServiceSku string = 'F1'

@description('.NET version of the web app (Windows App Service stack).')
param dotnetVersion string = 'v10.0'

// The next three come from environment variables set by Deploy-Azure.ps1, which validates them.
@description('Client (application) ID of the Entra app registration used for Easy Auth sign-in.')
param webAppEntraClientId string

@description('Client (application) ID of the Entra app registration that represents the accounts API (token audience).')
param accountsApiClientId string

@description('APIM publisher email (required by API Management; receives service notifications).')
param apimPublisherEmail string

param apimPublisherName string = 'Account Acquisition'

@description('Comma-separated contact columns that count as contact information. A contact with all of them empty has no contact information.')
@minLength(1)
param contactInfoColumns string

var suffix = '${baseName}-${environmentName}'
var tags = {
  environment: environmentName
  workload: 'account-acquisition'
}
var sharedTier = contains(['F1', 'D1'], appServiceSku)
var accountsApiAudience = 'api://${accountsApiClientId}'
var apimApiPath = 'crm'

// ---------- Monitoring ----------

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${suffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

// ---------- API Management (Consumption) ----------

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: 'apim-${suffix}'
  location: location
  tags: tags
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  identity: { type: 'SystemAssigned' }
  properties: {
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
  }
}

// Named values referenced by the policy as {{name}}. Configuration, not secrets.
var namedValues = {
  'tenant-id': tenant().tenantId
  'dataverse-url': dataverseUrl
  'accounts-api-audience': accountsApiAudience
  'accounts-api-client-id': accountsApiClientId
  'contact-info-columns': contactInfoColumns
}

resource apimNamedValues 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = [for nv in items(namedValues): {
  parent: apim
  name: nv.key
  properties: {
    displayName: nv.key
    value: nv.value
    secret: false
  }
}]

// Separate from the loop: the web app's managed identity is only known at deployment time.
resource webAppPrincipalNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'webapp-principal-id'
  properties: {
    displayName: 'webapp-principal-id'
    value: webApp.identity.principalId
    secret: false
  }
}

// The logger's connection string lives in a named value WE own. Passing it to the logger directly makes APIM
// create a new auto-named 'Logger-Credentials--<id>' secret on every deployment.
resource appInsightsConnectionNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'appinsights-connection-string'
  properties: {
    displayName: 'appinsights-connection-string'
    value: appInsights.properties.ConnectionString
    secret: true
  }
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'appinsights'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: appInsights.id
    credentials: {
      connectionString: '{{appinsights-connection-string}}'
    }
  }
  dependsOn: [appInsightsConnectionNamedValue]
}

// Request telemetry without headers or bodies (the Authorization header must never be logged).
resource apimDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    verbosity: 'information'
  }
}

resource accountsApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'accounts'
  properties: {
    displayName: 'Accounts'
    path: apimApiPath
    protocols: ['https']
    // No serviceUrl: the policy sets the backend from the 'dataverse-url' named value, the same value the
    // managed identity token is requested for, so the destination and the token audience can't diverge.
    subscriptionRequired: false // callers authenticate with an Entra token, not a subscription key
  }
}

resource getAccounts 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: accountsApi
  name: 'get-accounts'
  properties: {
    displayName: 'Get active accounts with contacts'
    method: 'GET'
    urlTemplate: '/accounts'
  }
}

resource getAccountsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: getAccounts
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('policies/get-accounts.xml')
  }
  dependsOn: [apimNamedValues, webAppPrincipalNamedValue]
}

// ---------- Web app (Windows) ----------

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'asp-${suffix}'
  location: location
  tags: tags
  kind: 'app'
  sku: { name: appServiceSku }
}

resource webApp 'Microsoft.Web/sites@2024-04-01' = {
  name: 'app-${suffix}'
  location: location
  tags: tags
  kind: 'app'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: dotnetVersion
      metadata: [
        { name: 'CURRENT_STACK', value: 'dotnet' }
      ]
      use32BitWorkerProcess: sharedTier
      alwaysOn: !sharedTier
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      appSettings: [
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'ApplicationInsightsAgent_EXTENSION_VERSION', value: '~2' }
        { name: 'AccountsApi__BaseUrl', value: '${apim.properties.gatewayUrl}/${apimApiPath}' }
        { name: 'AccountsApi__Scope', value: '${accountsApiAudience}/.default' }
      ]
    }
  }
}

// Easy Auth: every request must be signed in with an account from this tenant.
// No client secret: sign-in only needs the ID token. Background (XHR) requests get 401 instead of a redirect.
resource webAppAuth 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: webApp
  name: 'authsettingsV2'
  properties: {
    platform: { enabled: true }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureactivedirectory'
    }
    httpSettings: { requireHttps: true }
    login: {
      tokenStore: { enabled: true }
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: webAppEntraClientId
          openIdIssuer: '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [
            webAppEntraClientId
            'api://${webAppEntraClientId}'
          ]
        }
      }
    }
  }
}

output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output webAppPrincipalId string = webApp.identity.principalId
output apimName string = apim.name
output accountsApiUrl string = '${apim.properties.gatewayUrl}/${apimApiPath}'
@description('Object ID of the APIM managed identity. Its Application ID is what you add as a Dataverse application user.')
output apimPrincipalId string = apim.identity.principalId
