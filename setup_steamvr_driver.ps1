# Windows PowerShell SteamVR Driver Setup Script
$ErrorActionPreference = "Continue"

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "    iPhoneVR SteamVR Driver Automatic Setup Tool" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$DriverPath = Join-Path $ScriptDir "SteamVR_Driver\driver_iphonevr"

$vrpathreg = $null

# 1. Check Steam Registry
$steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
if ($steamPath) {
    $candidate1 = Join-Path $steamPath "steamapps\common\SteamVR\bin\win64\vrpathreg.exe"
    if (Test-Path $candidate1) {
        $vrpathreg = $candidate1
    }
}

# 2. Check Standard Candidate Paths
if (-not $vrpathreg) {
    $candidates = @(
        "C:\Program Files (x86)\Steam\steamapps\common\SteamVR\bin\win64\vrpathreg.exe",
        "D:\SteamLibrary\steamapps\common\SteamVR\bin\win64\vrpathreg.exe",
        "E:\SteamLibrary\steamapps\common\SteamVR\bin\win64\vrpathreg.exe",
        "F:\SteamLibrary\steamapps\common\SteamVR\bin\win64\vrpathreg.exe"
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) {
            $vrpathreg = $path
            break
        }
    }
}

# 3. Handle Result
if (-not $vrpathreg) {
    Write-Host "[ERROR] SteamVR executable (vrpathreg.exe) was not found on your system!" -ForegroundColor Red
    Write-Host ""
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
    Write-Host "  [Solution]" -ForegroundColor Yellow
    Write-Host "   1. Open Steam App on your PC." -ForegroundColor Yellow
    Write-Host "   2. Search for 'SteamVR' in Store and install it (Free)." -ForegroundColor Yellow
    Write-Host "   3. After installation completes, run this script again!" -ForegroundColor Yellow
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit..."
    exit 1
}

Write-Host "[Found SteamVR]: $vrpathreg" -ForegroundColor Green
Write-Host ""
Write-Host "[1/2] Registering driver to SteamVR..." -ForegroundColor White
& "$vrpathreg" adddriver "$DriverPath"

Write-Host ""
Write-Host "[2/2] Checking current registered SteamVR drivers..." -ForegroundColor White
& "$vrpathreg" show

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host "[SUCCESS] SteamVR Driver Registration Completed!" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Read-Host "Press Enter to exit..."
