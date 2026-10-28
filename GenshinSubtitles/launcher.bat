@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules;%PSModulePath%"
cd /d "%~dp0"
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
echo Checking local subtitle index...
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare-ocr-index.ps1" -CheckOnly
if errorlevel 1 (
  echo Subtitle data is missing or outdated. Run setup.bat once from the project folder.
  pause
  exit /b 2
)
echo Checking Windows OCR and overlay...
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0overlay.ps1" -CheckOnly >"%TEMP%\genshin-overlay-check.log" 2>&1
if errorlevel 1 (
  type "%TEMP%\genshin-overlay-check.log"
  echo Install a Windows OCR language, or run setup.bat to check the installation.
  pause
  exit /b 5
)
set "GAME=%GENSHIN_GAME_EXE%"
if not defined GAME if exist "%~dp0game-path.txt" set /p "GAME="<"%~dp0game-path.txt"
if not "%~1"=="" set "GAME=%~1"
"%POWERSHELL%" -NoProfile -Command "if (Get-Process -Name YuanShen,GenshinImpact -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if not errorlevel 1 goto game_ready
if not defined GAME (
  echo Start the game normally, set GENSHIN_GAME_EXE, save a path in game-path.txt, or drag the game EXE onto launcher.bat.
  pause
  exit /b 3
)
if not exist "%GAME%" (
  echo Game executable was not found: "%GAME%"
  pause
  exit /b 3
)
echo Starting game: "%GAME%"
start "Genshin Impact" "%GAME%"
echo Waiting for the game process, up to 180 seconds...
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
echo Starting the external subtitle overlay...
start "Genshin Subtitle Overlay" "%POWERSHELL%" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0overlay.ps1"
exit /b 0
