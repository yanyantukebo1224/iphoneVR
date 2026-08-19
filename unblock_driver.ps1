# PowerShell script to unblock iPhoneVR driver in SteamVR
$SteamConfigPath = "C:\Program Files (x86)\Steam\config\steamvr.vrsettings"

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "   Unblocking iPhoneVR Driver in SteamVR" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

if (Test-Path $SteamConfigPath) {
    $rawContent = Get-Content $SteamConfigPath -Raw
    
    # blocked_by_safe_mode を全消去・解除
    $cleanedContent = $rawContent -replace '"blocked_by_safe_mode"\s*:\s*true', '"blocked_by_safe_mode" : false'
    $cleanedContent = $cleanedContent -replace '"enableSafeMode"\s*:\s*true', '"enableSafeMode" : false'
    
    Set-Content -Path $SteamConfigPath -Value $cleanedContent -Encoding UTF8

    Write-Host "[SUCCESS] Unblocked driver from SteamVR Safe Mode!" -ForegroundColor Green
} else {
    Write-Host "[ERROR] steamvr.vrsettings not found!" -ForegroundColor Red
}

Read-Host "Press Enter to exit..."
