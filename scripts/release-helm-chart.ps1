param(
    [Parameter(Mandatory = $true)]
    [string]$Project,

    [ValidateSet("patch", "minor", "major", "none")]
    [string]$Bump = "patch",

    [string]$Version,

    [string]$Destination = "docs",

    [ValidateSet("WorkingTree", "GitHead")]
    [string]$SourceMode = "WorkingTree",

    [switch]$NoUpdateIndex,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Get-BumpedVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Current,
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    if ($Current -notmatch '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$') {
        throw "Chart version '$Current' is not plain semver (x.y.z), cannot auto bump. Use -Version explicitly."
    }

    $major = [int]$Matches.major
    $minor = [int]$Matches.minor
    $patch = [int]$Matches.patch

    switch ($Mode) {
        "major" { return "$($major + 1).0.0" }
        "minor" { return "$major.$($minor + 1).0" }
        "patch" { return "$major.$minor.$($patch + 1)" }
        "none"  { return $Current }
        default  { throw "Unsupported bump mode: $Mode" }
    }
}

function Resolve-ChartPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$ProjectArg
    )

    $candidatePaths = @(
        (Join-Path $RepoRoot ($ProjectArg.TrimStart('.', '/', '\').Replace('/', '\'))),
        (Join-Path $RepoRoot (Join-Path "charts-src" $ProjectArg))
    )

    foreach ($candidate in $candidatePaths | Select-Object -Unique) {
        if ((Test-Path $candidate -PathType Container) -and (Test-Path (Join-Path $candidate "Chart.yaml") -PathType Leaf)) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Cannot resolve chart from -Project '$ProjectArg'. Use chart name (e.g. new-api) or relative path (e.g. charts-src/new-api)."
}

function Get-RelativePathCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $baseFull = (Resolve-Path $BasePath).Path
    $targetFull = (Resolve-Path $TargetPath).Path

    $baseNormalized = $baseFull.TrimEnd('\\')
    if ($targetFull.StartsWith($baseNormalized, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $targetFull.Substring($baseNormalized.Length).TrimStart('\\')
    }

    $baseUri = New-Object System.Uri(($baseNormalized + '\\'))
    $targetUri = New-Object System.Uri($targetFull)
    $relative = $baseUri.MakeRelativeUri($targetUri).ToString()
    return [System.Uri]::UnescapeDataString($relative).Replace('/', '\\')
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$chartPathAbs = Resolve-ChartPath -RepoRoot $repoRoot -ProjectArg $Project
$chartYaml = Join-Path $chartPathAbs "Chart.yaml"
$packageScript = Join-Path $PSScriptRoot "package-helm-chart.ps1"

if (-not (Test-Path $packageScript -PathType Leaf)) {
    throw "Required script not found: $packageScript"
}

$chartPathRel = Get-RelativePathCompat -BasePath $repoRoot -TargetPath $chartPathAbs

$chartContent = Get-Content -Path $chartYaml -Raw -Encoding UTF8
$currentVersionLine = [regex]::Match($chartContent, '(?m)^version:\s*(.+)$')
if (-not $currentVersionLine.Success) {
    throw "Cannot find 'version:' in $chartYaml"
}

$currentVersion = $currentVersionLine.Groups[1].Value.Trim().Trim('"')
$targetVersion = if ([string]::IsNullOrWhiteSpace($Version)) {
    Get-BumpedVersion -Current $currentVersion -Mode $Bump
}
else {
    $Version.Trim()
}

if ($targetVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "Target version '$targetVersion' is invalid. Use semver x.y.z"
}

Write-Host "Repo root     : $repoRoot"
Write-Host "Chart path    : $chartPathRel"
Write-Host "Current ver   : $currentVersion"
Write-Host "Target ver    : $targetVersion"
Write-Host "Update index  : $([bool](-not $NoUpdateIndex))"
Write-Host "Source mode   : $SourceMode"

if ($DryRun) {
    Write-Host "DryRun enabled, no files changed."
    exit 0
}

if ($targetVersion -ne $currentVersion) {
    $updated = [regex]::Replace($chartContent, '(?m)^version:\s*(.+)$', "version: $targetVersion", 1)
    Set-Content -Path $chartYaml -Value $updated -Encoding UTF8
    Write-Host "Chart version updated: $currentVersion -> $targetVersion"
}
else {
    Write-Host "Chart version unchanged."
}

Write-Host "Running helm lint..."
helm lint $chartPathAbs
if ($LASTEXITCODE -ne 0) {
    throw "helm lint failed"
}

$packageArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $packageScript,
    "-ChartPath", $chartPathRel,
    "-Destination", $Destination,
    "-SourceMode", $SourceMode
)

if (-not $NoUpdateIndex) {
    $packageArgs += "-UpdateIndex"
}

Write-Host "Packaging chart..."
powershell @packageArgs
if ($LASTEXITCODE -ne 0) {
    throw "package-helm-chart.ps1 failed"
}

Write-Host "Release completed for $chartPathRel@$targetVersion"
