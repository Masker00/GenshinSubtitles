@echo off
setlocal
cd /d "%~dp0"
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
echo Checking subtitle overlay requirements...
set "GAME=%GENSHIN_GAME_EXE%"
if not defined GAME if exist "%~dp0game-path.txt" set /p "GAME="<"%~dp0game-path.txt"
if not "%~1"=="" set "GAME=%~1"
echo Checking local subtitle index...
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare-ocr-index.ps1" -CheckOnly
if errorlevel 1 (
  echo Building the local OCR subtitle index...
  "%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare-ocr-index.ps1"
  if errorlevel 1 (
    echo OCR index preparation failed.
    pause
    exit /b 2
  )
)
echo Checking Windows OCR and overlay...
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0overlay.ps1" -CheckOnly >"%~dp0overlay-startup.log" 2>&1
if errorlevel 1 (
  echo Subtitle overlay startup check failed:
  type "%~dp0overlay-startup.log"
  echo.
  echo If Windows OCR is unavailable, install Chinese or English OCR in Windows language settings.
  echo Details saved to: "%~dp0overlay-startup.log"
  pause
  exit /b 5
)
echo Looking for a running game...
"%POWERSHELL%" -NoProfile -Command "if (Get-Process -Name YuanShen,GenshinImpact -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if not errorlevel 1 goto game_ready
if not exist "%GAME%" (
  echo Game path not found. Start the game normally, then run this launcher again.
  echo Or drag YuanShen.exe / GenshinImpact.exe onto launcher.bat.
  echo You can also set GENSHIN_GAME_EXE to the game executable path.
  echo Or save the full executable path in game-path.txt beside this launcher.
  echo Current path: "%GAME%"
  pause
  exit /b 3
)
echo Starting game: "%GAME%"
start "Genshin Impact" "%GAME%"
echo Waiting for the game process...
set /a WAIT_SECONDS=0
:wait_for_game
"%POWERSHELL%" -NoProfile -Command "if (Get-Process -Name YuanShen,GenshinImpact -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if errorlevel 1 (
  set /a WAIT_SECONDS+=1
  if %WAIT_SECONDS% GEQ 180 (
    echo Game did not start within 180 seconds. Start it normally and retry.
    pause
    exit /b 4
  )
  timeout /t 1 /nobreak >nul
  goto wait_for_game
)
:game_ready
echo Starting subtitle overlay...
start "Genshin Subtitle Overlay" "%POWERSHELL%" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0overlay.ps1"
exit /b 0
