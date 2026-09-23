@echo off
setlocal
set "SOURCE=%~dp0frontend"
set "TARGET=C:\temp\NEXUSCUP\frontend"

if not exist "%SOURCE%\app.js" (
  echo ERRO: frontend de origem nao encontrado em %SOURCE%
  pause
  exit /b 1
)

if not exist "C:\temp\NEXUSCUP" (
  echo ERRO: instalacao C:\temp\NEXUSCUP nao encontrada.
  echo Copie manualmente a pasta frontend para a instalacao que esta a correr.
  pause
  exit /b 1
)

if not exist "%TARGET%" mkdir "%TARGET%"
copy /Y "%SOURCE%\index.html" "%TARGET%\index.html" >nul
copy /Y "%SOURCE%\app.js" "%TARGET%\app.js" >nul
copy /Y "%SOURCE%\style.css" "%TARGET%\style.css" >nul

echo.
echo Frontend V13 aplicado em C:\temp\NEXUSCUP\frontend
echo Agora no browser carregue Ctrl+F5.
echo Nao e necessario reiniciar a BD.
echo.
pause
