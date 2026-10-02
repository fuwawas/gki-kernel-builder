@echo off
title GKI Kernel Builder
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0build-gki.ps1"
echo.
echo Done. Press any key to close.
pause >nul
