@echo off
rem DeepSeek Harness TUI launcher.
rem Defaults to the dsh-tui profile from the default home (~/.dsh).
rem Pass an explicit --profile to run a different profile instead.
setlocal
set "REPO=C:\Workspace\deepseek-harness"
set "DSH_HOME=%USERPROFILE%\.dsh"
if not exist "%REPO%\apps\cli\lib\profile-boot.js" goto :nobuild
pushd "%REPO%" || exit /b 1
set "INJECT=--profile dsh-tui"
rem Wrap in brackets so the value is never empty (an empty set deletes the variable).
set "ALLARGS=[%*]"
if not "%ALLARGS%"=="%ALLARGS:--profile=%" set "INJECT="
call pnpm dsh %INJECT% %*
set "RC=%ERRORLEVEL%"
popd
endlocal & exit /b %RC%

:nobuild
echo [!] DSH build artifacts are missing: apps\cli\lib\profile-boot.js
echo     A repository build may be running, or the checkout has not been built.
echo     Wait for the build to finish, then retry. To rebuild: pnpm run dev:desktop
pause
exit /b 1
