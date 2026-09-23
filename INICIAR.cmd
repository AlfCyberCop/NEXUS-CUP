@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Start.ps1"
set "NEXUS_EXIT=%ERRORLEVEL%"
if not "%NEXUS_EXIT%"=="0" pause
exit /b %NEXUS_EXIT%
