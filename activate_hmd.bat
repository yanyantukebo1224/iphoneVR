@echo off
title GlassVR x iphoneVR Auto Activation Tool
chcp 65001 > nul

echo ===================================================
echo    GlassVR x iphoneVR Auto Activation System
echo ===================================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0activate_hmd.ps1"

echo ===================================================
echo [ALL READY] Start SteamVR and Moonlight on iPhone!
echo ===================================================
pause
