@echo off
title iPhoneVR SteamVR Driver Automatic Setup

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_steamvr_driver.ps1"

if %ERRORLEVEL% NEQ 0 (
    pause
)
