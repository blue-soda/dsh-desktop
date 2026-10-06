@echo off
rem DeepSeek Harness Desktop - full development launch.
rem Runs the launcher's complete preparation (project re-link + primary-runtime
rem verification, about 70s on this machine) and then starts Electron.
rem Use this after changing dependencies, the runtime lock, or after a build.
setlocal
set "REPO=C:\Workspace\deepseek-harness"
set "DSH_HOME=%USERPROFILE%\.dsh"
if not exist "%REPO%\apps\cli\lib\profile-boot.js" goto :nobuild
if not exist "%REPO%\apps\desktop-host\lib\index.js" goto :nobuild
pushd "%REPO%" || exit /b 1
call pnpm run start:desktop %*
set "RC=%ERRORLEVEL%"
popd
endlocal & exit /b %RC%

:nobuild
echo [!] DSH desktop build artifacts are missing.
echo     A repository build may be running, or the checkout has not been built.
echo     Wait for the build to finish, then retry. To rebuild: pnpm run dev:desktop
pause
exit /b 1
