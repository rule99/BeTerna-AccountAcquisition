# Deploys azure/infra/main.bicep with main.<env>.bicepparam into a resource group, then optionally publishes
# a function project. Manual / separate from the Dataverse pipeline. Run 'az login' first.
# Deploy Azure BEFORE importing the solution that references it (env variable values, webhooks).
# Usage:
#   .\azure\scripts\Deploy-Azure.ps1 -Environment test -ResourceGroup rg-acme-test -Subscription <id> -WhatIf
#   .\azure\scripts\Deploy-Azure.ps1 -Environment test -ResourceGroup rg-acme-test -FunctionProject azure\Acme.Functions
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('test', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [string]$Subscription,

    # Function project folder to publish after the infrastructure (func azure functionapp publish).
    [string]$FunctionProject,

    # Show what would change (az deployment group what-if) and stop.
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$azureRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$params = Join-Path $azureRoot "infra\main.$Environment.bicepparam"
if (-not (Test-Path $params)) { throw "Parameters file not found: $params" }
if ($FunctionProject -and -not (Test-Path (Join-Path $FunctionProject 'host.json'))) {
    throw "Not a function project (no host.json): $FunctionProject"
}
if ((Get-Content $params -Raw) -match '__AZURE_BASENAME__|YOURORG') {
    throw "Fill in the placeholders in $params first."
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
$sub = az account show --query "{name:name, id:id}" -o json | ConvertFrom-Json
Write-Host "Subscription: $($sub.name) ($($sub.id)), resource group: $ResourceGroup, env: $Environment" -ForegroundColor Cyan

if ($WhatIf) {
    az deployment group what-if --resource-group $ResourceGroup --parameters $params
    if ($LASTEXITCODE -ne 0) { throw 'what-if failed.' }
    return
}

$deploymentName = "infra-$Environment-$(Get-Date -Format 'yyyyMMddHHmmss')"
$outputs = az deployment group create --name $deploymentName --resource-group $ResourceGroup --parameters $params `
    --query properties.outputs -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $outputs) { throw 'Infrastructure deployment failed.' }
$appName = $outputs.functionAppName.value
Write-Host "Function App: $appName  $($outputs.functionAppUrl.value)" -ForegroundColor Green
Write-Host "Managed identity object ID: $($outputs.principalId.value) (add its Application ID as a Dataverse application user)"

if ($FunctionProject) {
    Write-Host "Publishing $FunctionProject -> $appName" -ForegroundColor Cyan
    Push-Location $FunctionProject
    try {
        func azure functionapp publish $appName
        if ($LASTEXITCODE -ne 0) { throw 'Function publish failed.' }
    } finally { Pop-Location }
}
Write-Host "Done. Put the function URL into the solution's environment variable values (deploymentSettings.$Environment.json)." -ForegroundColor Green
