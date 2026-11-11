# Deploys azure/infra/main.bicep with main.<env>.bicepparam into a resource group, then optionally publishes
# the web project. Manual / separate from the Dataverse pipeline. Run 'az login' first.
# Deploy Azure BEFORE importing the solution that references it (env variable values, webhooks).
#
# Steps: register resource providers -> create the resource group if missing -> create/reuse the two Entra app
# registrations (web sign-in, accounts API audience; no secrets) -> deploy Bicep -> optionally publish the web app.
# Needs: Contributor + role-assignment rights on the resource group, and rights to create app registrations in Entra.
#
# Usage:
#   .\azure\scripts\Deploy-Azure.ps1 -Environment dev -ResourceGroup rg-acme-dev -Location switzerlandnorth -WhatIf
#   .\azure\scripts\Deploy-Azure.ps1 -Environment dev -ResourceGroup rg-acme-dev -Location switzerlandnorth
#   .\azure\scripts\Deploy-Azure.ps1 -Environment dev -ResourceGroup rg-acme-dev -WebProject azure\Acme.Web
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'test', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    # Region for the resource group; only needed when the resource group doesn't exist yet.
    [string]$Location,

    [string]$Subscription,

    # ASP.NET Core project folder to publish to the web app after the infrastructure (dotnet publish + zip deploy).
    [string]$WebProject,

    # APIM publisher email (required by API Management). Defaults to the signed-in Azure user.
    [string]$PublisherEmail,

    # Show what would change (az deployment group what-if) and stop. Still creates the resource group and the
    # app registrations if missing, because what-if needs them.
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$azureRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$params = Join-Path $azureRoot "infra\main.$Environment.bicepparam"
if (-not (Test-Path $params)) { throw "Parameters file not found: $params" }
$paramsText = Get-Content $params -Raw
if ($paramsText -match '__AZURE_BASENAME__|YOURORG') { throw "Fill in the placeholders in $params first." }
if ($WebProject -and -not (Get-ChildItem -Path $WebProject -Filter *.csproj -ErrorAction SilentlyContinue)) {
    throw "Not a .NET project folder (no .csproj): $WebProject"
}

# Windows PowerShell turns native stderr into a terminating error under 'Stop', so relax it for this probe.
$ErrorActionPreference = 'Continue'
az account show --only-show-errors -o none 2>$null
$loggedIn = $LASTEXITCODE -eq 0
$ErrorActionPreference = 'Stop'
if (-not $loggedIn) { throw "Not logged in to Azure. Run 'az login' (with access to the client's subscription)." }
if ($Subscription) {
    az account set --subscription $Subscription
    if ($LASTEXITCODE -ne 0) { throw "Cannot select subscription $Subscription." }
}
$sub = az account show --query "{name:name, id:id, user:user.name}" -o json | ConvertFrom-Json
Write-Host "Subscription: $($sub.name) ($($sub.id)), resource group: $ResourceGroup, env: $Environment" -ForegroundColor Cyan

# Names must match main.bicep ('app-${baseName}-${environmentName}').
$baseName = [regex]::Match($paramsText, "param\s+baseName\s*=\s*'([^']+)'").Groups[1].Value
if (-not $baseName) { throw "Could not read baseName from $params." }
$webAppName = "app-$baseName-$Environment"

# 1. Resource providers (one-time per subscription).
foreach ($ns in 'Microsoft.Web', 'Microsoft.ApiManagement', 'Microsoft.Insights', 'Microsoft.OperationalInsights') {
    $state = az provider show --namespace $ns --query registrationState -o tsv
    if ($state -ne 'Registered') {
        Write-Host "Registering resource provider $ns ..." -ForegroundColor Cyan
        az provider register --namespace $ns --wait --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw "Could not register $ns." }
    }
}

# 2. Resource group.
if ((az group exists --name $ResourceGroup) -ne 'true') {
    if (-not $Location) { throw "Resource group $ResourceGroup doesn't exist. Pass -Location to create it." }
    Write-Host "Creating resource group $ResourceGroup in $Location" -ForegroundColor Cyan
    az group create --name $ResourceGroup --location $Location -o none
    if ($LASTEXITCODE -ne 0) { throw "Could not create resource group $ResourceGroup." }
}

# 3. Entra app registrations (identifiers only: no secrets, no certificates, no roles).
function Get-OrCreateAppRegistration([string]$Name) {
    $appId = az ad app list --filter "displayName eq '$Name'" --query "[0].appId" -o tsv
    if (-not $appId) {
        Write-Host "Creating app registration $Name" -ForegroundColor Cyan
        $appId = az ad app create --display-name $Name --sign-in-audience AzureADMyOrg --query appId -o tsv
        if ($LASTEXITCODE -ne 0 -or -not $appId) { throw "Could not create app registration $Name." }
    }
    # The service principal (enterprise application) is what users sign in to and what tokens are issued for.
    $spId = az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv
    if (-not $spId) {
        az ad sp create --id $appId -o none --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw "Could not create the service principal for $Name." }
    }
    return $appId
}

# Web sign-in (Easy Auth): redirect URI of the web app, ID token only.
$webClientId = Get-OrCreateAppRegistration "$baseName-web-$Environment"
az ad app update --id $webClientId --web-redirect-uris "https://$webAppName.azurewebsites.net/.auth/login/aad/callback" `
    --enable-id-token-issuance true --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Could not configure the web app registration.' }

# Accounts API: only an identifier the web app's managed identity requests tokens for.
$apiClientId = Get-OrCreateAppRegistration "$baseName-accounts-api-$Environment"
az ad app update --id $apiClientId --identifier-uris "api://$apiClientId" --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Could not configure the accounts API app registration.' }

if (-not $PublisherEmail) { $PublisherEmail = $sub.user }
$guid = '^[0-9a-fA-F-]{36}$'
if ($webClientId -notmatch $guid -or $apiClientId -notmatch $guid) { throw 'App registration IDs are not valid GUIDs.' }
if ($PublisherEmail -notmatch '@') { throw 'Pass -PublisherEmail (APIM requires a publisher email).' }

# Read by main.<env>.bicepparam (readEnvironmentVariable).
$env:LRW_WEBAPP_CLIENT_ID = $webClientId
$env:LRW_ACCOUNTS_API_CLIENT_ID = $apiClientId
$env:LRW_APIM_PUBLISHER_EMAIL = $PublisherEmail
Write-Host "Web sign-in app ID: $webClientId, accounts API app ID: $apiClientId" -ForegroundColor Cyan

# 4. Infrastructure.
if ($WhatIf) {
    az deployment group what-if --resource-group $ResourceGroup --parameters $params
    if ($LASTEXITCODE -ne 0) { throw 'what-if failed.' }
    return
}

$deploymentName = "infra-$Environment-$(Get-Date -Format 'yyyyMMddHHmmss')"
Write-Host "Deploying infrastructure (API Management can take several minutes the first time) ..." -ForegroundColor Cyan
$outputs = az deployment group create --name $deploymentName --resource-group $ResourceGroup --parameters $params `
    --query properties.outputs -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $outputs) { throw 'Infrastructure deployment failed.' }
$appName = $outputs.webAppName.value
$apimAppId = az ad sp show --id $outputs.apimPrincipalId.value --query appId -o tsv
Write-Host "Web app:      $appName  $($outputs.webAppUrl.value)" -ForegroundColor Green
Write-Host "Accounts API: $($outputs.accountsApiUrl.value)/accounts" -ForegroundColor Green
Write-Host "APIM managed identity Application ID: $apimAppId" -ForegroundColor Yellow
Write-Host "  -> after importing the solution (it carries the role), create the Dataverse application user:" -ForegroundColor Yellow
Write-Host "     pac admin assign-user --environment <dataverse-url> --user $apimAppId --role 'Account Acquisition API Reader' --application-user" -ForegroundColor Yellow

# 5. Web app code.
if ($WebProject) {
    $tmp = Join-Path $env:TEMP ("publish-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        Write-Host "Publishing $WebProject -> $appName" -ForegroundColor Cyan
        dotnet publish $WebProject -c Release -o (Join-Path $tmp 'app')
        if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed.' }
        $zip = Join-Path $tmp 'app.zip'
        Compress-Archive -Path (Join-Path $tmp 'app\*') -DestinationPath $zip
        az webapp deploy --resource-group $ResourceGroup --name $appName --src-path $zip --type zip -o none
        if ($LASTEXITCODE -ne 0) { throw 'Web app deployment failed.' }
    } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host 'Done.' -ForegroundColor Green
