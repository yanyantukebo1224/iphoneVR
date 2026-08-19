# PowerShell script to force SteamVR to recognize iPhoneVR HMD
$SteamConfigPath = "C:\Program Files (x86)\Steam\config\steamvr.vrsettings"

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "     iPhoneVR SteamVR HMD Activation Tool" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

if (Test-Path $SteamConfigPath) {
    try {
        $json = Get-Content $SteamConfigPath -Raw | ConvertFrom-Json
        
        if (-not $json.steamvr) {
            $json | Add-Member -MemberType NoteProperty -Name "steamvr" -Value ([PSCustomObject]@{})
        }
        
        $json.steamvr | Add-Member -MemberType NoteProperty -Name "activateMultipleDrivers" -Value $true -Force
        $json.steamvr | Add-Member -MemberType NoteProperty -Name "forcedDriver" -Value "driver_iphonevr" -Force
        $json.steamvr | Add-Member -MemberType NoteProperty -Name "requireHmd" -Value $true -Force

        $updatedJson = $json | ConvertTo-Json -Depth 10
        Set-Content -Path $SteamConfigPath -Value $updatedJson -Encoding UTF8

        Write-Host "[SUCCESS] SteamVR settings updated successfully!" -ForegroundColor Green
        Write-Host "  - forcedDriver: driver_iphonevr" -ForegroundColor Green
        Write-Host "  - activateMultipleDrivers: true" -ForegroundColor Green
        Write-Host ""
        Write-Host "Now start or restart SteamVR, and the iPhoneVR HMD will appear!" -ForegroundColor Yellow
    } catch {
        Write-Host "[WARNING] Could not parse steamvr.vrsettings. Applied default driver config instead." -ForegroundColor Yellow
    }
} else {
    Write-Host "[INFO] SteamVR config file not found. It will be generated automatically when SteamVR starts." -ForegroundColor Yellow
}

Read-Host "Press Enter to exit..."
