@echo off
rem Build the customized DeepSeek Harness Desktop installer from a pinned upstream commit.
rem
rem   build-release.cmd [-Tag <name>] [-Upload] [-Verify] [-Clean] [-Source <url>] [-Base <commit>]
rem
rem The build is isolated: the upstream repository is cloned into build\dsh, reset to -Base, and
rem given dsh-desktop.patch. Artifacts land in dist\. All logic lives in tools\build-release.mjs;
rem run `build-release.cmd -Clean` to remove build\, dist\, and leftover dsh-* temp entries.

setlocal EnableExtensions
where node >nul 2>&1
if errorlevel 1 (
  echo build-release: Node.js is required on PATH.
  exit /b 1
)
node "%~dp0tools\build-release.mjs" %*
exit /b %ERRORLEVEL%
