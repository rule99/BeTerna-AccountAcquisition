using './main.bicep'

param baseName = 'beternaaccou'
param environmentName = 'test'
param dataverseUrl = 'https://YOURORG-test.crm4.dynamics.com'
param appServiceSku = 'F1'
param contactInfoColumns = 'emailaddress1,telephone1,mobilephone,fax,address1_line1,address1_city,address1_postalcode,address1_country'

// Set by Deploy-Azure.ps1 (Entra app registrations and the signed-in user); not stored in the repo.
param webAppEntraClientId = readEnvironmentVariable('LRW_WEBAPP_CLIENT_ID', '')
param accountsApiClientId = readEnvironmentVariable('LRW_ACCOUNTS_API_CLIENT_ID', '')
param apimPublisherEmail = readEnvironmentVariable('LRW_APIM_PUBLISHER_EMAIL', '')
