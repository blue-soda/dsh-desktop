@echo off
rem Add or remove Windows Defender exclusions for the DSH development setup.
rem
rem   defender-exclusions.cmd [path ...] [-Remove]
rem
rem With no path it excludes %USERPROFILE%\.dsh and, when they exist, %LOCALAPPDATA%\pnpm and the
rem checkout named by the DSH_REPO environment variable. Real-time protection itself stays on.
rem
rem Windows exposes NO supported non-PowerShell interface for Add-MpPreference, and editing the
rem exclusion registry values directly is unreliable under Tamper Protection. This script therefore
rem performs the write through one inline `powershell -NoProfile -Command` call. It is an inline
rem call, not a .ps1 file. Elevation uses the same inline PowerShell to re-launch this script with
rem `Start-Process -Verb RunAs`.
rem
rem The outcome is written as JSON to %TEMP%\dsh-defender-exclusions.json and printed.

setlocal EnableExtensions
set "MODE=add"
set "PLAN=%TEMP%\dsh-defender-exclusions.plan.txt"
set "RESULT=%TEMP%\dsh-defender-exclusions.json"

if /i "%~1"=="-Elevated" set "ELEVATED=1"
if not defined ELEVATED del "%PLAN%" >nul 2>&1

:parse
if "%~1"=="" goto parsed
if /i "%~1"=="-Elevated" ( shift & goto parse )
if /i "%~1"=="-Remove" ( set "MODE=remove" & shift & goto parse )
if /i "%~1"=="-Mode" ( set "MODE=%~2" & shift & shift & goto parse )
if /i "%~1"=="-Plan" ( set "PLAN=%~2" & shift & shift & goto parse )
if not defined ELEVATED (
  >>"%PLAN%" echo(%~1
  set "HAD_TARGET=1"
)
shift
goto parse

:parsed
if not defined ELEVATED if not defined HAD_TARGET (
  if exist "%USERPROFILE%\.dsh" >>"%PLAN%" echo(%USERPROFILE%\.dsh
  if exist "%LOCALAPPDATA%\pnpm" >>"%PLAN%" echo(%LOCALAPPDATA%\pnpm
  if defined DSH_REPO if exist "%DSH_REPO%" >>"%PLAN%" echo(%DSH_REPO%
)

if not defined ELEVATED (
  net session >nul 2>&1
  if errorlevel 1 (
    echo Requesting administrator authorization...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList '-Elevated','-Plan','%PLAN%','-Mode','%MODE%' -Wait"
    if errorlevel 1 (
      echo defender-exclusions: authorization was declined; nothing changed.
      exit /b 1
    )
    if exist "%RESULT%" type "%RESULT%"
    exit /b 0
  )
)

set "PS=Remove-MpPreference"
if /i "%MODE%"=="add" set "PS=Add-MpPreference"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Continue'; $targets = @(Get-Content -LiteralPath '%PLAN%' | Where-Object { $_.Trim() -ne '' } | ForEach-Object { [string]$_ }); $applied = @(); $failed = @(); $missing = @(); foreach ($target in $targets) { if (-not (Test-Path -LiteralPath $target)) { $missing += [string]$target; continue }; try { if ('%MODE%' -eq 'remove') { Remove-MpPreference -ExclusionPath $target -ErrorAction Stop } else { Add-MpPreference -ExclusionPath $target -ErrorAction Stop }; $applied += [string]$target } catch { $failed += @{ path = [string]$target; message = $_.Exception.Message } } }; $excluded = @(); try { $excluded = @((Get-MpPreference -ErrorAction Stop).ExclusionPath) } catch { $excluded = @('unavailable: ' + $_.Exception.Message) }; $realTime = $null; try { $realTime = (Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled } catch { $realTime = 'unavailable' }; $result = @{ elevated = $true; action = $(if ('%MODE%' -eq 'remove') { 'remove' } else { 'add' }); applied = $applied; missing = $missing; failed = $failed; excluded = $excluded; realTime = $realTime }; $json = $result | ConvertTo-Json -Depth 4; [IO.File]::WriteAllText('%RESULT%', $json, (New-Object Text.UTF8Encoding $false)); Write-Output $json"
if errorlevel 1 (
  echo defender-exclusions: the elevated call failed; see %RESULT%
  exit /b 1
)
exit /b 0
