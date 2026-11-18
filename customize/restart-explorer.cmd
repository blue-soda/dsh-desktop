@echo off
rem Restarts Explorer so the shell reloads shortcut and executable icons after a customization run.
rem The desktop and taskbar disappear for a moment and come back; running applications keep running.
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 800; if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }"
set "CODE=%ERRORLEVEL%"
echo.
pause
exit /b %CODE%
