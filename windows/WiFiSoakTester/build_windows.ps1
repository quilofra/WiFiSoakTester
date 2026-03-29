$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputDir = Join-Path $rootDir "BuildWindows"
$bundleDir = Join-Path $outputDir "wifisoaktester-windows-x64"
$zipPath = Join-Path $outputDir "wifisoaktester-windows-x64.zip"

function Copy-BundleFiles {
    param(
        [string]$SourceDirectory,
        [string[]]$Patterns
    )

    if ([string]::IsNullOrWhiteSpace($SourceDirectory) -or -not (Test-Path -LiteralPath $SourceDirectory)) {
        return
    }

    foreach ($pattern in $Patterns) {
        Get-ChildItem -LiteralPath $SourceDirectory -File -Filter $pattern -ErrorAction SilentlyContinue |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $bundleDir $_.Name) -Force
            }
    }
}

Push-Location $rootDir
try {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    Write-Host "[1/4] Building Windows CLI in Release mode..."
    swift build -c release --product WiFiSoakTester
    if ($LASTEXITCODE -ne 0) {
        throw "swift build failed."
    }

    Write-Host "[2/4] Locating release output..."
    $exe = Get-ChildItem -Path (Join-Path $rootDir ".build") -Recurse -File -Filter "WiFiSoakTester.exe" |
        Where-Object { $_.FullName -match '[\\/]+release[\\/]' } |
        Select-Object -First 1

    if (-not $exe) {
        throw "Release executable not found."
    }

    $releaseDir = $exe.Directory.FullName

    Write-Host "[3/4] Staging portable bundle..."
    Remove-Item -Path $bundleDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null

    Copy-Item -Path $exe.FullName -Destination (Join-Path $bundleDir "WiFiSoakTester.exe")

    Copy-BundleFiles -SourceDirectory $releaseDir -Patterns @("*.dll", "*.pdb")

    $swiftCommand = Get-Command swiftc -ErrorAction Stop
    $swiftBinDir = Split-Path -Parent $swiftCommand.Source
    $swiftRuntimeDirs = @($swiftBinDir)
    $swiftRuntimeDirs += $env:PATH -split ";" |
        ForEach-Object { $_.Trim() } |
        Where-Object {
            $_ -and
            (Test-Path -LiteralPath $_) -and
            $_ -match '[\\/]Programs[\\/]Swift[\\/](Toolchains|Runtimes)[\\/]'
        }

    $swiftRuntimeDirs |
        Select-Object -Unique |
        ForEach-Object {
            Copy-BundleFiles -SourceDirectory $_ -Patterns @("*.dll")
        }

    $vcRedistRoot = if ($env:VCToolsRedistDir) {
        Join-Path $env:VCToolsRedistDir "x64"
    }

    if ($vcRedistRoot -and (Test-Path -LiteralPath $vcRedistRoot)) {
        Get-ChildItem -LiteralPath $vcRedistRoot -Directory |
            Where-Object { $_.Name -like "Microsoft.VC*.CRT" -or $_.Name -like "Microsoft.VC*.OpenMP" } |
            ForEach-Object {
                Copy-BundleFiles -SourceDirectory $_.FullName -Patterns @("*.dll")
            }
    }

    Copy-Item -Path (Join-Path $rootDir "endpoints.txt") -Destination (Join-Path $bundleDir "endpoints.txt")
    Copy-Item -Path (Join-Path $rootDir "README_WINDOWS.md") -Destination (Join-Path $bundleDir "README_WINDOWS.md")

    $launcher = @'
@echo off
setlocal
cd /d "%~dp0"
if not exist "exports" mkdir "exports"
".\WiFiSoakTester.exe" --endpoints-file "endpoints.txt" --csv-out "exports\stats_current.csv" --html-out "exports\report_current.html"
if not defined WIFI_SOAK_NO_PAUSE pause
'@
    Set-Content -Path (Join-Path $bundleDir "run_default.bat") -Value $launcher -Encoding Ascii

    Write-Host "[4/4] Creating ZIP artifact..."
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $bundleDir "*") -DestinationPath $zipPath

    Write-Host "Bundle available at: $zipPath"
}
finally {
    Pop-Location
}
