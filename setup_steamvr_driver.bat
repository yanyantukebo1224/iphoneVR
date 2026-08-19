@echo off
chcp 65001 > nul
title iPhoneVR SteamVR Driver Automatic Setup

echo ===================================================
echo     iPhoneVR SteamVR Driver Automatic Setup Tool
echo ===================================================
echo.

set DRIVER_PATH=%~dp0SteamVR_Driver\driver_iphonevr
set VRPATHREG="C:\Program Files (x86)\Steam\steamapps\common\SteamVR\bin\win64\vrpathreg.exe"

if not exist %VRPATHREG% (
    echo [ERROR] SteamVR executable vrpathreg.exe not found!
    echo Please make sure SteamVR is installed in standard path.
    pause
    exit /b 1
)

echo [1/2] Registering driver to SteamVR...
%VRPATHREG% adddriver "%DRIVER_PATH%"

echo.
echo [2/2] Checking current registered SteamVR drivers...
%VRPATHREG% show

echo.
echo ===================================================
echo [SUCCESS] SteamVR Driver Registration Completed!
echo Now you can launch SteamVR and use iPhoneVR HMD.
echo ===================================================
pause
