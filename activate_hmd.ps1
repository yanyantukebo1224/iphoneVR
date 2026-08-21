# PowerShell script to fully activate GlassVR x iphoneVR HMD & Auto Bridge
$SteamConfigPath = "C:\Program Files (x86)\Steam\config\steamvr.vrsettings"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "   GlassVR x iphoneVR Auto Activation System" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Update SteamVR Config for forced driver & multiple drivers
if (Test-Path $SteamConfigPath) {
    try {
        $json = Get-Content $SteamConfigPath -Raw | ConvertFrom-Json
        
        if (-not $json.steamvr) {
            $json | Add-Member -MemberType NoteProperty -Name "steamvr" -Value ([PSCustomObject]@{})
        }
        
        $json.steamvr | Add-Member -MemberType NoteProperty -Name "activateMultipleDrivers" -Value $true -Force
        $json.steamvr | Add-Member -MemberType NoteProperty -Name "requireHmd" -Value $true -Force
        $json.steamvr | Add-Member -MemberType NoteProperty -Name "forcedDriver" -Value "driver_iphonevr" -Force

        $updatedJson = $json | ConvertTo-Json -Depth 10
        Set-Content -Path $SteamConfigPath -Value $updatedJson -Encoding UTF8

        Write-Host "[1/2] SteamVR settings updated (forcedDriver: glassvr)." -ForegroundColor Green
    } catch {
        Write-Host "[WARNING] Could not update steamvr.vrsettings." -ForegroundColor Yellow
    }
}

# 2. Launch GlassVR Auto Server in background silently
$ServerScript = Join-Path $ScriptDir "GlassVr\code-glassvrserver\main.py"
if (Test-Path $ServerScript) {
    Write-Host "[2/2] Launching GlassVR Auto Bridge in background..." -ForegroundColor Green
    Start-Process -FilePath "python" -ArgumentList "`"$ServerScript`"" -WindowStyle Hidden
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host "[ALL READY] Start SteamVR & Moonlight on iPhone!" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
