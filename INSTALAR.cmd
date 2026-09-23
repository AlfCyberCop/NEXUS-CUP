@echo off
setlocal
cd /d "%~dp0"
if /I "%~1"=="/texto" goto texto
start "" powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0installer\Wizard.ps1"
exit /b 0
:texto
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Install.ps1"
set "NEXUS_EXIT=%ERRORLEVEL%"
echo.
if not "%NEXUS_EXIT%"=="0" echo NEXUS-CUP: instalacao interrompida. Consulte o erro acima.
pause
exit /b %NEXUS_EXIT%
