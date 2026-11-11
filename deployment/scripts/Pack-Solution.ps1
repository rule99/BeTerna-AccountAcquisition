# Builds plugins and packs Solutions/<SolutionName> into out/. Web resources and plugin DLLs in the
# solution are replaced with their repo sources automatically; deployment/map.xml holds exceptions only.
# Usage: .\deployment\scripts\Pack-Solution.ps1 -SolutionName MySolution [-PackageType Unmanaged|Managed|Both]
# Output: out\<SolutionName>.zip (unmanaged) and/or out\<SolutionName>_managed.zip.
param(
    [Parameter(Mandatory = $true)]
    [string]$SolutionName,

    # Managed/Both require a folder unpacked with --packagetype Both (Export-Solution.ps1 does that).
    [ValidateSet('Unmanaged', 'Managed', 'Both')]
    [string]$PackageType = 'Both',

    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$solRoot = Join-Path $repo "Solutions\$SolutionName"
$folder = if (Test-Path (Join-Path $solRoot 'src\Other\Solution.xml')) { Join-Path $solRoot 'src' } else { $solRoot }
if (-not (Test-Path (Join-Path $folder 'Other\Solution.xml'))) {
    throw "No unpacked solution found in $solRoot (expected Other\Solution.xml or src\Other\Solution.xml)."
}
# pac packs a "managed" zip even from an unmanaged-only folder without complaining, so guard it here.
if ($PackageType -ne 'Unmanaged' -and (Get-Content (Join-Path $folder 'Other\Solution.xml') -Raw) -notmatch '<Managed>2</Managed>') {
    throw "$folder was not unpacked with --packagetype Both, so a managed package can't be built from it. Re-export with Export-Solution.ps1 or use -PackageType Unmanaged."
}

$projects = Get-ChildItem (Join-Path $repo 'Plugins') -Recurse -Filter *.csproj -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' }
foreach ($proj in $projects) {
    Write-Host "Building $($proj.Name)..." -ForegroundColor Cyan
    dotnet build $proj.FullName -c Release --nologo -v q
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $($proj.Name)" }
}

$out = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $repo 'out' }
New-Item -ItemType Directory -Force -Path $out | Out-Null
$zip = Join-Path $out ("{0}{1}.zip" -f $SolutionName, $(if ($PackageType -eq 'Managed') { '_managed' } else { '' }))
$expected = switch ($PackageType) {
    'Unmanaged' { @($zip) }
    'Managed'   { @($zip) }
    'Both'      { @($zip, (Join-Path $out "${SolutionName}_managed.zip")) }
}

# Map "to" paths resolve against the solution folder, so walk back up to the repo root.
$depth = $folder.Substring($repo.Length).Trim('\').Split('\').Count
$up = '..\' * $depth

$manual = @()
$manualXml = Join-Path $repo 'deployment\map.xml'
if (Test-Path $manualXml) {
    [xml]$m = Get-Content $manualXml -Raw
    $manual = @($m.Mapping.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })
}
$manualMaps = @($manual | ForEach-Object { $_.GetAttribute('map') })

$entries = New-Object System.Collections.Generic.List[string]
$missing = New-Object System.Collections.Generic.List[string]

# WebResources\<prefix>_\<TableSchemaName>\<File> in the solution <- WebResources\<TableSchemaName>\<File> in the repo.
$wrRoot = Join-Path $folder 'WebResources'
if (Test-Path $wrRoot) {
    Get-ChildItem $wrRoot -Recurse -File | Where-Object { $_.Name -notlike '*.data.xml' } | ForEach-Object {
        $inSol = $_.FullName.Substring($folder.Length + 1)
        $parts = $inSol.Split('\')
        if ($parts.Count -lt 3 -or $manualMaps -contains $inSol) { return }
        $rel = $parts[2..($parts.Count - 1)] -join '\'
        if (Test-Path (Join-Path $repo "WebResources\$rel")) {
            $entries.Add("<FileToFile map=""$inSol"" to=""${up}WebResources\$rel"" />")
        } else { $missing.Add($inSol) }
    }
}

# PluginAssemblies\<Name>-<guid>\<Name>.dll in the solution <- newest Plugins\**\bin\Release\**\<Name>.dll.
$paRoot = Join-Path $folder 'PluginAssemblies'
if (Test-Path $paRoot) {
    Get-ChildItem $paRoot -Recurse -Filter *.dll | ForEach-Object {
        $inSol = $_.FullName.Substring($folder.Length + 1)
        if ($manualMaps -contains $inSol) { return }
        $built = Get-ChildItem (Join-Path $repo 'Plugins') -Recurse -Filter $_.Name -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\bin\\Release\\' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($built) {
            $entries.Add("<FileToFile map=""$inSol"" to=""$up$($built.FullName.Substring($repo.Length + 1))"" />")
        } else { $missing.Add($inSol) }
    }
}

$map = Join-Path $out 'map.generated.xml'
$xmlLines = @('<?xml version="1.0" encoding="utf-8"?>', '<Mapping>')
$xmlLines += $manual | ForEach-Object { '  ' + $_.OuterXml }
$xmlLines += $entries | ForEach-Object { "  $_" }
$xmlLines += '</Mapping>'
Set-Content -Path $map -Value $xmlLines -Encoding UTF8
Write-Host "Mapping: $($entries.Count) file(s) from repo sources, $($manual.Count) manual (see $map)." -ForegroundColor Cyan
foreach ($f in $missing) { Write-Warning "No repo source for $f - the copy inside the solution will be packed." }

Write-Host "Packing $folder -> $zip ($PackageType)" -ForegroundColor Cyan
$expected | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
pac solution pack --zipfile $zip --folder $folder --packagetype $PackageType --map $map
# pac can print an error yet exit 0, so also require every expected zip to exist.
$missingZips = @($expected | Where-Object { -not (Test-Path $_) })
if ($LASTEXITCODE -ne 0 -or $missingZips.Count -gt 0) { throw "pac solution pack failed (missing: $($missingZips -join ', '))." }
$expected | ForEach-Object { Write-Host "Done: $_" -ForegroundColor Green }
