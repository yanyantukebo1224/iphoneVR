@echo off
title GlassVR x iphoneVR Auto Activation Tool
chcp 65001 > nul

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0activate_hmd.ps1"

if %ERRORLEVEL% NEQ 0 (
    pause
)
