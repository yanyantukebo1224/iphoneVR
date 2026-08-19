@echo off
chcp 65001 > nul
title iPhoneVR SteamVR Driver Automatic Setup

echo ===================================================
echo     iPhoneVR SteamVR Driver Automatic Setup Tool
echo ===================================================
echo.

set DRIVER_PATH=%~dp0SteamVR_Driver\driver_iphonevr
set FOUND_VRPATHREG=""

:: 1. 標準パスの探索
if exist "C:\Program Files (x86)\Steam\steamapps\common\SteamVR\bin\win64\vrpathreg.exe" (
    set FOUND_VRPATHREG="C:\Program Files (x86)\Steam\steamapps\common\SteamVR\bin\win64\vrpathreg.exe"
)

:: 2. Dドライブ SteamLibrary の探索
if %FOUND_VRPATHREG%=="" (
    if exist "D:\SteamLibrary\steamapps\common\SteamVR\bin\win64\vrpathreg.exe" (
        set FOUND_VRPATHREG="D:\SteamLibrary\steamapps\common\SteamVR\bin\win64\vrpathreg.exe"
    )
)

:: 3. Eドライブ SteamLibrary の探索
if %FOUND_VRPATHREG%=="" (
    if exist "E:\SteamLibrary\steamapps\common\SteamVR\bin\win64\vrpathreg.exe" (
        set FOUND_VRPATHREG="E:\SteamLibrary\steamapps\common\SteamVR\bin\win64\vrpathreg.exe"
    )
)

:: 見つからなかった場合のエラー表示
if %FOUND_VRPATHREG%=="" (
    echo [ERROR] SteamVR executable (vrpathreg.exe) was not found on your system!
    echo.
    echo ---------------------------------------------------
    echo  【解決方法 / Solution】
    echo   1. Steam アプリを起動してください。
    echo   2. ストア/ライブラリで 「SteamVR」 を検索し、無料インストールしてください。
    echo   3. インストール完了後、この setup_steamvr_driver.bat を再度実行してください！
    echo ---------------------------------------------------
    echo.
    pause
    exit /b 1
)

echo [Found SteamVR]: %FOUND_VRPATHREG%
echo.
echo [1/2] Registering driver to SteamVR...
%FOUND_VRPATHREG% adddriver "%DRIVER_PATH%"

echo.
echo [2/2] Checking current registered SteamVR drivers...
%FOUND_VRPATHREG% show

echo.
echo ===================================================
echo [SUCCESS] SteamVR Driver Registration Completed!
echo Now you can launch SteamVR and use iPhoneVR HMD.
echo ===================================================
pause
