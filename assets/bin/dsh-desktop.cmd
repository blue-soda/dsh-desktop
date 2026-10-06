@echo off
rem DeepSeek Harness Desktop - fast development launch.
rem Starts Electron directly against the already-prepared development project,
rem skipping the ~70s primary-runtime verification and project re-link that
rem "pnpm run start:desktop" performs on every launch.
rem After changing dependencies or the runtime lock, run dsh-desktop-full.cmd once.
setlocal
set "REPO=C:\Workspace\deepseek-harness"
set "DEV=%REPO%\apps\desktop\.desktop-build\development"
set "RUNTIME=%REPO%\apps\desktop\.desktop-build\targets\win-x64\runtime\primary-runtime"
set "DSH_HOME=%USERPROFILE%\.dsh"

set "ELECTRON_DIR=%REPO%\apps\desktop\node_modules\electron"
if not exist "%ELECTRON_DIR%\path.txt" goto :nofull
set /p ELECTRON_REL=<"%ELECTRON_DIR%\path.txt"
if not exist "%ELECTRON_DIR%\dist\%ELECTRON_REL%" goto :nofull
if not exist "%DEV%\project\desktop-runtime.json" goto :nofull
if not exist "%RUNTIME%\runtime.json" goto :nofull

set "DSH_DESKTOP_PRIMARY_RUNTIME_DIR=%RUNTIME%"
set "DSH_DESKTOP_HOST_INSPECT_PORT=9230"
set "DSH_DESKTOP_OPEN_DEVTOOLS=0"
set "ELECTRON_ENABLE_LOGGING=1"

"%ELECTRON_DIR%\dist\%ELECTRON_REL%" --inspect=127.0.0.1:9229 --remote-debugging-port=9222 --user-data-dir="%DEV%\electron-user-data" "%REPO%\apps\desktop"
exit /b %ERRORLEVEL%

:nofull
echo [!] Prepared development artifacts are missing or Electron is not installed.
echo     Run once:  pnpm run start:desktop
echo     (or double-click %~dp0dsh-desktop-full.cmd)
pause
exit /b 1
