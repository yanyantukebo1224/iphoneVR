@echo off
title Push to GitHub and Trigger iOS Cloud Build
cd /d "%~dp0"

echo ===================================================
echo   iPhoneVR GitHub Sync & Cloud Build Trigger
echo ===================================================
echo.

git add .
git commit -m "Update Moonlight VR 6DoF, Precision Finger Splay/Curl Tracking, Switch Controller, and PIN Pairing"
git push origin master

echo.
echo ===================================================
echo [SUCCESS] Pushed to GitHub!
echo GitHub Actions is now building MoonlightHMD.ipa / .app in the cloud.
echo.
echo Check build progress and download .ipa here:
echo https://github.com/yanyantukebo1224/iphoneVR/actions
echo ===================================================
echo.
pause