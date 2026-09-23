@echo off
setlocal
set "SRC=%~dp0frontend"
set "DEST=C:\temp\NEXUSCUP\frontend"

echo.
echo NEXUS-CUP NX15.2 - atualizar frontend
if not exist "%SRC%\app.js" (
  echo ERRO: pasta frontend nao encontrada junto deste ficheiro.
  pause
  exit /b 1
)

if not exist "%DEST%" (
  echo A instalacao C:\temp\NEXUSCUP nao foi encontrada.
  echo Os ficheiros da working tree ja ficaram atualizados; se instalaste noutro destino, copia a pasta frontend para esse destino.
  pause
  exit /b 2
)

copy /Y "%SRC%\index.html" "%DEST%\index.html" >nul
copy /Y "%SRC%\app.js" "%DEST%\app.js" >nul
copy /Y "%SRC%\style.css" "%DEST%\style.css" >nul

echo OK - frontend NX15.2 copiado para C:\temp\NEXUSCUP\frontend
echo No Chrome usa Ctrl+F5.
pause
