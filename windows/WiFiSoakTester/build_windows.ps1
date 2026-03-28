$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputDir = Join-Path $rootDir "BuildWindows"
$bundleDir = Join-Path $outputDir "wifisoaktester-windows-x64"
$zipPath = Join-Path $outputDir "wifisoaktester-windows-x64.zip"

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

    Get-ChildItem -Path $releaseDir -File |
        Where-Object { $_.Extension -in @(".dll", ".pdb") } |
        ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $bundleDir $_.Name)
        }

    Copy-Item -Path (Join-Path $rootDir "endpoints.txt") -Destination (Join-Path $bundleDir "endpoints.txt")
    Copy-Item -Path (Join-Path $rootDir "README_WINDOWS.md") -Destination (Join-Path $bundleDir "README_WINDOWS.md")

    $launcher = @'
@echo off
setlocal
cd /d "%~dp0"
if not exist "exports" mkdir "exports"
".\WiFiSoakTester.exe" --endpoints-file "endpoints.txt" --csv-out "exports\stats_current.csv" --html-out "exports\report_current.html"
pause
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
