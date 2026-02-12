param(
    [Parameter(Mandatory = $true)]
    [string]$ChartPath,

    [string]$Destination = "docs",

    [switch]$UpdateIndex,

    [string]$RepoUrl = "https://helm.flandre.io"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$chartPathNormalized = $ChartPath.TrimStart(".", "/", "\").Replace("/", "\")
$chartSourceInRepo = Join-Path $repoRoot $chartPathNormalized
$destinationAbs = (Resolve-Path (Join-Path $repoRoot $Destination)).Path

if (-not (Test-Path $chartSourceInRepo)) {
    throw "Chart path not found: $chartSourceInRepo"
}

if (-not (Test-Path (Join-Path $chartSourceInRepo "Chart.yaml"))) {
    throw "Chart.yaml not found under: $chartSourceInRepo"
}

$null = git -C $repoRoot rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Current directory is not a git repository: $repoRoot"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("helm-package-" + [System.Guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $tempRoot "chart.zip"

function Convert-ToLf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $patterns = @("*.yaml", "*.yml", "*.tpl", "*.md", "*.json", "*.conf")
    $files = @()
    foreach ($pattern in $patterns) {
        $files += Get-ChildItem -Path $RootPath -Recurse -File -Filter $pattern
    }
    $files += Get-ChildItem -Path $RootPath -Recurse -File -Filter "CNAME"

    foreach ($file in $files | Select-Object -Unique) {
        $content = [System.IO.File]::ReadAllText($file.FullName)
        $normalized = $content -replace "`r`n", "`n" -replace "`r", "`n"
        if ($normalized -ne $content) {
            [System.IO.File]::WriteAllText($file.FullName, $normalized, [System.Text.UTF8Encoding]::new($false))
        }
    }
}

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    Write-Host "[1/3] Exporting chart from git HEAD with normalized LF..."
    git -C $repoRoot archive --format=zip --output=$zipPath HEAD -- $chartPathNormalized
    if ($LASTEXITCODE -ne 0) {
        throw "git archive failed"
    }

    Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force

    $chartExportPath = Join-Path $tempRoot $chartPathNormalized
    if (-not (Test-Path (Join-Path $chartExportPath "Chart.yaml"))) {
        throw "Exported chart not found: $chartExportPath"
    }

    Convert-ToLf -RootPath $chartExportPath

    Write-Host "[2/3] Packaging chart with helm..."
    helm package $chartExportPath --destination $destinationAbs
    if ($LASTEXITCODE -ne 0) {
        throw "helm package failed"
    }

    if ($UpdateIndex) {
        Write-Host "[3/3] Updating repository index..."
        $indexPath = Join-Path $destinationAbs "index.yaml"
        if (Test-Path $indexPath) {
            helm repo index $destinationAbs --url $RepoUrl --merge $indexPath
        }
        else {
            helm repo index $destinationAbs --url $RepoUrl
        }

        if ($LASTEXITCODE -ne 0) {
            throw "helm repo index failed"
        }
    }
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force
    }
}

Write-Host "Done."
