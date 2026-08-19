@echo off
title iPhoneVR SteamVR HMD Activation Tool

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0activate_hmd.ps1"

if %ERRORLEVEL% NEQ 0 (
    pause
)
