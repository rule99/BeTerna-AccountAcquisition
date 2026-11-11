# Imports a solution zip into an environment, then configuration data zips (pac data) if any.
# Auth: service principal from PP_TENANT_ID / PP_CLIENT_ID / PP_CLIENT_SECRET (pipeline secrets);
# without them, the active pac auth profile is used (local use).
# Usage:
#   .\deployment\scripts\Import-Solution.ps1 -ZipPath out\MySolution_managed.zip -EnvironmentUrl https://org-test.crm4.dynamics.com `
#       -SettingsFile deployment\settings\deploymentSettings.test.json -DataFolder deployment\data -ImportMode update -DryRun
param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [Parameter(Mandatory = $true)][string]$EnvironmentUrl,
    [string]$SettingsFile,
    [string]$DataFolder,

    # update: components in the target but not in the package are kept.
    # upgrade: they are DELETED (stage-and-upgrade). Use only with explicit approval.
    [ValidateSet('update', 'upgrade')]
    [string]$ImportMode = 'update',

    # Print the pac commands instead of running them.
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $ZipPath)) { throw "Solution zip not found: $ZipPath" }
$EnvironmentUrl = $EnvironmentUrl.TrimEnd('/')

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $ZipPath).Path)
try {
    $entry = $zip.Entries | Where-Object { $_.FullName -eq 'solution.xml' }
    $reader = New-Object IO.StreamReader($entry.Open())
    $solXml = $reader.ReadToEnd(); $reader.Close()
} finally { $zip.Dispose() }
$uniqueName = [regex]::Match($solXml, '<UniqueName>([^<]+)</UniqueName>').Groups[1].Value
$version = [regex]::Match($solXml, '<Version>([^<]+)</Version>').Groups[1].Value
$managed = [regex]::Match($solXml, '<Managed>(\d)</Managed>').Groups[1].Value -eq '1'
Write-Host ("Package: {0} {1} ({2}) -> {3}, mode: {4}" -f $uniqueName, $version, $(if ($managed) { 'managed' } else { 'unmanaged' }), $EnvironmentUrl, $ImportMode) -ForegroundColor Cyan

$commands = New-Object System.Collections.Generic.List[object]
if ($env:PP_CLIENT_ID) {
    $commands.Add(@('auth', 'create', '--name', 'deploy', '--environment', $EnvironmentUrl,
        '--applicationId', $env:PP_CLIENT_ID, '--clientSecret', $env:PP_CLIENT_SECRET, '--tenant', $env:PP_TENANT_ID))
}
$import = @('solution', 'import', '--path', $ZipPath, '--environment', $EnvironmentUrl,
    '--activate-plugins', '--async', '--max-async-wait-time', '120')
if ($SettingsFile) {
    if (-not (Test-Path $SettingsFile)) { throw "Settings file not found: $SettingsFile" }
    $import += @('--settings-file', $SettingsFile)
}
if ($ImportMode -eq 'upgrade') { $import += '--stage-and-upgrade' }
$commands.Add($import)

$dataZips = @()
if ($DataFolder -and (Test-Path $DataFolder)) { $dataZips = @(Get-ChildItem $DataFolder -Filter *.zip | Sort-Object Name) }
foreach ($d in $dataZips) { $commands.Add(@('data', 'import', '--data', $d.FullName, '--environment', $EnvironmentUrl)) }

if ($DryRun) {
    foreach ($c in $commands) { 'pac ' + (($c | ForEach-Object { if ($_ -eq $env:PP_CLIENT_SECRET -and $_) { '***' } else { $_ } }) -join ' ') }
    return
}

foreach ($c in $commands) {
    & pac @c
    if ($LASTEXITCODE -ne 0) { throw "pac $($c[0]) $($c[1]) failed." }
    # pac can print an error yet exit 0, so the solution import is verified below.
    if ($c[0] -eq 'solution') {
        $list = (pac solution list --environment $EnvironmentUrl 2>&1 | Out-String) -split "`r?`n"
        $row = $list | Where-Object { $_ -match "^\s*$([regex]::Escape($uniqueName))\s" }
        if (-not $row -or $row -notmatch [regex]::Escape($version)) {
            throw "Import not confirmed: $uniqueName $version is not listed in $EnvironmentUrl."
        }
        Write-Host "Confirmed: $uniqueName $version in $EnvironmentUrl" -ForegroundColor Green
    }
}
if ($dataZips.Count -gt 0) { Write-Host "Imported $($dataZips.Count) data package(s) - check the pac data output above." -ForegroundColor Green }
