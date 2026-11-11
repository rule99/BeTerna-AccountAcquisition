# Runs Solution Checker on a packed solution and fails when findings reach -FailOn severity.
# Auth: PP_TENANT_ID / PP_CLIENT_ID / PP_CLIENT_SECRET (pipeline secrets), else the active pac auth profile.
# Usage:
#   .\deployment\scripts\Test-Solution.ps1 -Path out\MySolution_managed.zip -EnvironmentUrl https://org-test.crm4.dynamics.com
#   .\deployment\scripts\Test-Solution.ps1 -OutputDirectory out\checker -SkipCheck    # re-evaluate existing results
param(
    [string]$Path,
    [string]$EnvironmentUrl,
    [string]$OutputDirectory = 'out\checker',

    # Lowest severity that fails the run.
    [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Never')]
    [string]$FailOn = 'High',

    # Checker service region, e.g. Europe, UnitedStates (pac default when omitted).
    [string]$Geo,

    # Only evaluate results already in -OutputDirectory.
    [switch]$SkipCheck
)
$ErrorActionPreference = 'Stop'
$rank = @{ Critical = 4; High = 3; Medium = 2; Low = 1; Informational = 0 }

if (-not $SkipCheck) {
    if (-not $Path -or -not (Test-Path $Path)) { throw "Solution zip not found: $Path" }
    if (-not $EnvironmentUrl) { throw '-EnvironmentUrl is required (the checker runs in that tenant).' }
    $EnvironmentUrl = $EnvironmentUrl.TrimEnd('/')
    if (Test-Path $OutputDirectory) { Remove-Item $OutputDirectory -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    if ($env:PP_CLIENT_ID) {
        pac auth create --name checker --environment $EnvironmentUrl --applicationId $env:PP_CLIENT_ID --clientSecret $env:PP_CLIENT_SECRET --tenant $env:PP_TENANT_ID
        if ($LASTEXITCODE -ne 0) { throw 'pac auth create failed.' }
    }
    $checkArgs = @('solution', 'check', '--path', $Path, '--outputDirectory', $OutputDirectory, '--environment', $EnvironmentUrl)
    if ($Geo) { $checkArgs += @('--geo', $Geo) }
    pac @checkArgs
    if ($LASTEXITCODE -ne 0) { throw 'pac solution check failed.' }
}

# Results come as .sarif files, possibly inside zips.
Get-ChildItem $OutputDirectory -Recurse -Filter *.zip | ForEach-Object {
    Expand-Archive $_.FullName -DestinationPath (Join-Path $_.DirectoryName $_.BaseName) -Force
}
$sarifs = @(Get-ChildItem $OutputDirectory -Recurse -Filter *.sarif)
# pac can print an error yet exit 0, so missing results count as a failure.
if ($sarifs.Count -eq 0) { throw "No Solution Checker results (.sarif) found in $OutputDirectory." }

$findings = foreach ($f in $sarifs) {
    $doc = Get-Content $f.FullName -Raw | ConvertFrom-Json
    foreach ($run in $doc.runs) {
        foreach ($r in $run.results) {
            $sev = $r.properties.severity
            if (-not $sev) { $sev = switch ($r.level) { 'error' { 'High' } 'warning' { 'Medium' } 'note' { 'Low' } default { 'Informational' } } }
            $loc = $r.locations | Select-Object -First 1
            [pscustomobject]@{
                Severity = $sev
                Rule     = $r.ruleId
                Message  = $r.message.text
                Location = $loc.physicalLocation.artifactLocation.uri
            }
        }
    }
}
$findings = @($findings)

Write-Host "Solution Checker: $($findings.Count) finding(s)" -ForegroundColor Cyan
foreach ($s in 'Critical', 'High', 'Medium', 'Low', 'Informational') {
    Write-Host ("  {0,-13} {1}" -f $s, @($findings | Where-Object Severity -eq $s).Count)
}
if ($FailOn -ne 'Never') {
    $blocking = @($findings | Where-Object { $rank[$_.Severity] -ge $rank[$FailOn] })
    if ($blocking.Count -gt 0) {
        $blocking | Select-Object -First 20 | ForEach-Object { Write-Host "  [$($_.Severity)] $($_.Rule): $($_.Message) ($($_.Location))" -ForegroundColor Red }
        throw "$($blocking.Count) finding(s) at '$FailOn' or above."
    }
}
Write-Host "Passed (fail threshold: $FailOn)." -ForegroundColor Green
