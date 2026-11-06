@echo off
rem Applies the distribution touches to every detected stock install: window and tray icons, the
rem executable icon, the profile plugin and seed entry, and the Windows Security exclusions.
rem Idempotent: whatever already matches is reported and skipped, and the application only has to be
rem closed when something actually needs writing. Extra arguments are forwarded, for example
rem -DryRun, -SkipDefender, -IncludeCustom or -InstallPath "D:\apps\DeepSeek Harness".
setlocal
set "SCRIPT=%~dp0dsh-customize.ps1"
if not exist "%SCRIPT%" (
  echo Missing dsh-customize.ps1 next to this file.
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -ExeIcon %*
set "CODE=%ERRORLEVEL%"
echo.
pause
exit /b %CODE%
