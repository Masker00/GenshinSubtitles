@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules;%PSModulePath%"
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0GenshinSubtitles\setup.ps1"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo.
  echo Setup did not complete. Read the error above, fix that item, and run setup.bat again.
  pause
)
if "%RESULT%"=="0" (
  echo.
  echo Setup complete. Start the game normally, then run GenshinSubtitles\launcher.bat.
  pause
)
exit /b %RESULT%
