# Exports <SolutionName> (unmanaged + managed) from the dev environment of the active pac auth profile,
# unpacks it with --packagetype Both into Solutions/<SolutionName>, then bumps the solution version in dev.
# Afterwards: review with 'git status' / 'git diff' and commit only the changes that belong in the release.
# Usage:
#   .\deployment\scripts\Export-Solution.ps1 -SolutionName MySolution
#   .\deployment\scripts\Export-Solution.ps1 -SolutionName MySolution -ZipFile C:\Downloads\MySolution_1_0_0_5.zip
param(
    [Parameter(Mandatory = $true)]
    [string]$SolutionName,

    # Use an already-exported unmanaged zip instead of exporting; the managed zip must sit next to it
    # with the same name plus "_managed". No environment access, no version bump.
    [string]$ZipFile,

    # Don't increment the solution version in dev after exporting.
    [switch]$NoVersionBump
)
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$solRoot = Join-Path $repo "Solutions\$SolutionName"
$folder = if (Test-Path (Join-Path $solRoot 'src\Other\Solution.xml')) { Join-Path $solRoot 'src' } else { $solRoot }

$tmp = Join-Path $env:TEMP ("export-{0}-{1}" -f $SolutionName, [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    if ($ZipFile) {
        $managedSrc = Join-Path (Split-Path $ZipFile) ([IO.Path]::GetFileNameWithoutExtension($ZipFile) + '_managed.zip')
        foreach ($f in $ZipFile, $managedSrc) { if (-not (Test-Path $f)) { throw "Not found: $f" } }
        Copy-Item $ZipFile (Join-Path $tmp "$SolutionName.zip")
        Copy-Item $managedSrc (Join-Path $tmp "${SolutionName}_managed.zip")
    } else {
        # pac can print an error yet exit 0, so every step is checked by its result.
        if ((pac auth list 2>&1 | Out-String) -match 'No profiles') { throw "No pac auth profile. Run 'pac auth create --environment <dev url>' first." }
        Write-Host "Exporting $SolutionName (unmanaged + managed)..." -ForegroundColor Cyan
        pac solution export --name $SolutionName --path (Join-Path $tmp "$SolutionName.zip") --overwrite
        pac solution export --name $SolutionName --path (Join-Path $tmp "${SolutionName}_managed.zip") --managed --overwrite
    }
    $unmanagedZip = Join-Path $tmp "$SolutionName.zip"
    foreach ($f in $unmanagedZip, (Join-Path $tmp "${SolutionName}_managed.zip")) {
        if (-not (Test-Path $f)) { throw "Export failed: $f was not created." }
    }

    Write-Host "Unpacking (Both) -> $folder" -ForegroundColor Cyan
    pac solution unpack --zipfile $unmanagedZip --folder $folder --packagetype Both --allowDelete true --allowWrite true --clobber true
    $solXml = Join-Path $folder 'Other\Solution.xml'
    if (-not (Test-Path $solXml) -or (Get-Content $solXml -Raw) -notmatch '<Managed>2</Managed>') {
        throw "Unpack failed or did not produce a 'Both' layout in $folder."
    }

    if (-not $ZipFile -and -not $NoVersionBump) {
        $version = [regex]::Match((Get-Content $solXml -Raw), '<Version>([^<]+)</Version>').Groups[1].Value
        $parts = $version.Split('.')
        $parts[-1] = [string]([int]$parts[-1] + 1)
        $next = $parts -join '.'
        Write-Host "Bumping $SolutionName in dev: $version -> $next" -ForegroundColor Cyan
        pac solution online-version --solution-name $SolutionName --solution-version $next
        $now = (pac solution online-version --solution-name $SolutionName 2>&1 | Out-String)
        if ($now -notmatch [regex]::Escape($next)) { Write-Warning "Could not confirm the new version in dev. Check it manually." }
    }
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Done. Review with 'git status' and commit only the changes that belong in this release." -ForegroundColor Green
