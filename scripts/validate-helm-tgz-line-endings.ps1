param(
    [string]$PackagePath,

    [string]$Directory = "docs",

    [string[]]$TextPatterns = @("*.yaml", "*.yml", "*.tpl", "*.md", "*.json", "*.conf", "CNAME", "Chart.lock", ".helmignore")
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Resolve-AbsolutePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path $Path).Path
    }

    return (Resolve-Path (Join-Path $repoRoot $Path)).Path
}

function Test-ContainsCarriageReturn {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    foreach ($b in $bytes) {
        if ($b -eq 13) {
            return $true
        }
    }

    return $false
}

$packages = @()

if ($PackagePath) {
    $packageAbs = Resolve-AbsolutePath -Path $PackagePath
    if (-not (Test-Path $packageAbs)) {
        throw "Package not found: $packageAbs"
    }

    $packages = @($packageAbs)
}
else {
    $directoryAbs = Resolve-AbsolutePath -Path $Directory
    $packages = @(Get-ChildItem -Path $directoryAbs -File -Filter "*.tgz" | Select-Object -ExpandProperty FullName)

    if ($packages.Count -eq 0) {
        throw "No .tgz packages found under: $directoryAbs"
    }
}

Write-Host "Validating line endings in $($packages.Count) package(s)..."

$hasFailure = $false

foreach ($pkg in $packages) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("helm-validate-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    try {
        tar -xzf $pkg -C $tempRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to extract package: $pkg"
        }

        $targetFiles = @()
        foreach ($pattern in $TextPatterns) {
            $targetFiles += Get-ChildItem -Path $tempRoot -Recurse -File -Filter $pattern
        }

        $targetFiles = $targetFiles | Select-Object -Unique

        if (-not $targetFiles -or $targetFiles.Count -eq 0) {
            Write-Warning "No target text files found in package: $pkg"
            continue
        }

        $badFiles = @()
        foreach ($file in $targetFiles) {
            if (Test-ContainsCarriageReturn -FilePath $file.FullName) {
                $badFiles += $file.FullName
            }
        }

        if ($badFiles.Count -gt 0) {
            $hasFailure = $true
            Write-Host "`n[FAIL] $pkg"
            foreach ($bad in $badFiles) {
                $relative = $bad.Substring($tempRoot.Length).TrimStart('\\', '/')
                Write-Host "  - contains CR (^M): $relative"
            }
        }
        else {
            Write-Host "[PASS] $pkg"
        }
    }
    finally {
        if (Test-Path $tempRoot) {
            Remove-Item -Path $tempRoot -Recurse -Force
        }
    }
}

if ($hasFailure) {
    Write-Error "Detected CR (^M) in one or more packaged text files."
    exit 1
}

Write-Host "All checked packages are LF-only in target text files."
exit 0
