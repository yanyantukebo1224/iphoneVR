@echo off
chcp 65001 > nul
title iPhoneVR PC Driver Build Script

echo ===================================================
echo     Building SteamVR Driver DLL (driver_iphonevr)
echo ===================================================
echo.

cd %~dp0SteamVR_Driver
if not exist build mkdir build
cd build

cmake ..
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] CMake configuration failed!
    pause
    exit /b %ERRORLEVEL%
)

cmake --build . --config Release
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Build failed!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ===================================================
echo [SUCCESS] Driver compiled: driver_iphonevr/bin/win64/
echo ===================================================
pause
