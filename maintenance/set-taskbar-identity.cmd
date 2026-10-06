@echo off
rem Give the development Desktop one taskbar identity so "Pin to taskbar" resolves to the shortcut.
rem
rem   set-taskbar-identity.cmd [-Repo <checkout>] [-Aumid <id>] [-Name <shortcut name>]
rem
rem An unpackaged Electron launch declares no application identifier, so Windows groups its
rem taskbar button under electron.exe: right-clicking the running window reads "Electron" and the
rem pin relaunches a bare Electron window. The application sets the identifier itself for
rem unpackaged launches; this script writes the same identifier onto the desktop shortcut and a
rem Start Menu copy, which is where Windows looks for the shortcut a pinned button should launch.
rem
rem The write goes through Electron's own shell.writeShortcutLink in maintenance\shortcut-writer,
rem so it needs the checkout's Electron but no PowerShell property hacking and no administrator.
rem It does still use the system's node.exe to print the result.

setlocal EnableExtensions
set "REPO=C:\Workspace\deepseek-harness"
set "AUMID=com.deepseek.harness.dev"
set "NAME=DeepSeek Harness Desktop"

:parse
if "%~1"=="" goto parsed
if /i "%~1"=="-Repo" ( set "REPO=%~2" & shift & shift & goto parse )
if /i "%~1"=="-Aumid" ( set "AUMID=%~2" & shift & shift & goto parse )
if /i "%~1"=="-Name" ( set "NAME=%~2" & shift & shift & goto parse )
echo set-taskbar-identity: unknown option %~1
exit /b 2

:parsed
set "ELECTRON_DIR=%REPO%\apps\desktop\node_modules\electron"
if not exist "%ELECTRON_DIR%\path.txt" (
  echo set-taskbar-identity: the checkout's Electron package is missing at %ELECTRON_DIR%
  exit /b 1
)
set "ELECTRON_REL="
set /p ELECTRON_REL=<"%ELECTRON_DIR%\path.txt"
set "ELECTRON=%ELECTRON_DIR%\dist\%ELECTRON_REL%"
if not exist "%ELECTRON%" (
  echo set-taskbar-identity: missing %ELECTRON%
  exit /b 1
)

rem A DSH shell exports ELECTRON_RUN_AS_NODE=1 for its Host child; left set, Electron would run as
rem plain Node, where require('electron') cannot resolve.
set "ELECTRON_RUN_AS_NODE="
set "DSH_SHORTCUT_AUMID=%AUMID%"
set "DSH_SHORTCUT_NAME=%NAME%"
set "DSH_SHORTCUT_REPO=%REPO%"

echo Writing the shortcut identity with the checkout's Electron...
"%ELECTRON%" "%~dp0shortcut-writer"
set "WRITER_CODE=%ERRORLEVEL%"

set "RESULT=%~dp0shortcut-writer\result.json"
if exist "%RESULT%" (
  node "%~dp0..\tools\report-shortcut-result.mjs" "%RESULT%"
) else (
  echo set-taskbar-identity: the writer produced no result.json ^(Electron exit code %WRITER_CODE%^)
)
exit /b %WRITER_CODE%
