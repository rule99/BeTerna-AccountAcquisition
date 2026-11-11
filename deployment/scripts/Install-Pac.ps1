# Installs the Windows pac CLI (includes 'pac data') from nuget.org and puts it on PATH.
# Used by the pipeline so agents need no marketplace extension; also works locally.
param(
    [string]$Version = 'latest',
    [string]$ToolsDirectory = $(if ($env:AGENT_TOOLSDIRECTORY) { $env:AGENT_TOOLSDIRECTORY } else { Join-Path $env:LOCALAPPDATA 'pac-cli' })
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$feed = 'https://api.nuget.org/v3-flatcontainer/microsoft.powerapps.cli'
if ($Version -eq 'latest') {
    $Version = (Invoke-RestMethod "$feed/index.json").versions | Where-Object { $_ -notmatch '-' } | Select-Object -Last 1
}
$dest = Join-Path $ToolsDirectory "pac\$Version"
$exe = Join-Path $dest 'tools\pac.exe'
if (-not (Test-Path $exe)) {
    Write-Host "Downloading pac $Version..."
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $pkg = Join-Path $dest 'package.zip'
    Invoke-WebRequest "$feed/$Version/microsoft.powerapps.cli.$Version.nupkg" -OutFile $pkg -UseBasicParsing
    Expand-Archive $pkg -DestinationPath $dest -Force
    Remove-Item $pkg
}
if (-not (Test-Path $exe)) { throw "pac.exe not found in microsoft.powerapps.cli $Version." }

$toolDir = Split-Path $exe
$env:PATH = "$toolDir;$env:PATH"
if ($env:TF_BUILD) { Write-Host "##vso[task.prependpath]$toolDir" }
Write-Host "pac $Version -> $exe"
