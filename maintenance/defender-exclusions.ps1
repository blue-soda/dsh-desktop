<#
.SYNOPSIS
    Add or remove the Windows Defender path exclusions that keep DSH cold starts fast.

.DESCRIPTION
    A cold start of the development Desktop reads a large amount of JavaScript and
    runtime data (the checkout, the harness home and the pnpm store). Real-time
    scanning charges for every file. Excluding exactly those three directories
    removes that cost while leaving real-time protection enabled for the rest of
    the machine.

    The script self-elevates (a UAC prompt appears), then writes a JSON result to
    %TEMP%\defender-exclusions-result.json and prints it.

.EXAMPLE
    pwsh -File defender-exclusions.ps1
    Add the three exclusions.

.EXAMPLE
    pwsh -File defender-exclusions.ps1 -Remove
    Remove exactly those three exclusions, restoring the previous state.
#>
param(
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$candidates = @(
    'C:\Workspace\deepseek-harness',
    (Join-Path $env:USERPROFILE '.dsh'),
    (Join-Path $env:LOCALAPPDATA 'pnpm')
)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '需要管理员权限，正在请求提权（桌面上会出现 UAC 弹窗）...'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Remove) { $arguments += '-Remove' }
    try {
        $elevated = Start-Process pwsh -Verb RunAs -Wait -PassThru -ArgumentList $arguments
        exit $elevated.ExitCode
    } catch {
        Write-Host "提权被取消或失败：$($_.Exception.Message)"
        exit 1
    }
}

$present = @($candidates | Where-Object { Test-Path $_ })
$absent = @($candidates | Where-Object { -not (Test-Path $_) })
$errors = @()
foreach ($path in $present) {
    try {
        if ($Remove) { Remove-MpPreference -ExclusionPath $path -ErrorAction Stop }
        else { Add-MpPreference -ExclusionPath $path -ErrorAction Stop }
    } catch {
        $errors += "$path : $($_.Exception.Message)"
    }
}

$result = [ordered]@{
    ranAt     = (Get-Date).ToString('s')
    action    = if ($Remove) { 'remove' } else { 'add' }
    elevated  = $true
    applied   = $present
    missing   = $absent
    effective = @((Get-MpPreference).ExclusionPath)
    realTime  = (Get-MpComputerStatus).RealTimeProtectionEnabled
    errors    = $errors
}
$json = $result | ConvertTo-Json -Depth 5
$json | Set-Content -Path (Join-Path $env:TEMP 'defender-exclusions-result.json') -Encoding utf8
Write-Host $json
