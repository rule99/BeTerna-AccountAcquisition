# Fetches a Dataverse access token via Azure CLI and writes it to http/.env for REST Client.
# Tokens expire after ~1 hour; re-run when requests start returning 401.
# Usage: .\http\Get-DataverseToken.ps1   (requires 'az login' once)

$envFile = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $PSScriptRoot '.env.example') $envFile
}

$lines = Get-Content $envFile
$url = ($lines | Where-Object { $_ -match '^DATAVERSE_URL=' }) -replace '^DATAVERSE_URL=', ''
$url = "$url".Trim().TrimEnd('/')
if (-not $url -or $url -match 'YOURORG') {
    Write-Error "Set DATAVERSE_URL in $envFile first."; return
}

$token = az account get-access-token --resource $url --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or -not $token) {
    Write-Error "Could not get a token. Run 'az login' (with an account that has access to $url) and try again."; return
}

$found = $false
$lines = $lines | ForEach-Object {
    if ($_ -match '^DATAVERSE_TOKEN=') { $found = $true; "DATAVERSE_TOKEN=$token" } else { $_ }
}
if (-not $found) { $lines += "DATAVERSE_TOKEN=$token" }
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllLines($envFile, [string[]]$lines, $utf8NoBom)
Write-Host "Token written to $envFile (valid ~1 hour)." -ForegroundColor Green
