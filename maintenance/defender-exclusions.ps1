<#
.SYNOPSIS
    Add or remove the Windows Defender path exclusions that keep DSH cold starts fast.

.DESCRIPTION
    A cold start of the development Desktop reads a large amount of JavaScript and runtime data
    (the checkout, the harness home and the pnpm store). Real-time scanning charges for every file.
    Excluding exactly those directories removes that cost while leaving real-time protection enabled
    for the rest of the machine.

    Without administrator rights the script relaunches itself elevated with a hidden window, so the
    only prompt is the UAC dialog — the same behaviour as the installed application's copy. The
    outcome is written as JSON to %TEMP%\dsh-defender-exclusions.json and printed.

.PARAMETER Remove
    Remove the exclusions instead of adding them.

.PARAMETER Path
    Explicit directories to exclude, replacing the default candidate list.

.PARAMETER Repo
    Checkout excluded alongside the defaults; defaults to %DSH_REPO%.

.EXAMPLE
    pwsh -File defender-exclusions.ps1
    Add the exclusions for the checkout, the harness home and the pnpm store.

.EXAMPLE
    pwsh -File defender-exclusions.ps1 -Remove
    Remove exactly those exclusions.
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [string[]]$Path = @(),
    [string]$Repo = $(if ($env:DSH_REPO) { $env:DSH_REPO } else { 'C:\Workspace\deepseek-harness' })
)

$ErrorActionPreference = 'Stop'

$resultPath = Join-Path $env:TEMP 'dsh-defender-exclusions.json'

function Write-Result {
    param([hashtable]$Value)
    $json = $Value | ConvertTo-Json -Depth 4
    # UTF-8 without a byte-order mark: JSON.parse over the file must not see one.
    [IO.File]::WriteAllText($resultPath, $json, (New-Object Text.UTF8Encoding $false))
    Write-Output $json
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdministrator = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    $forward = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Remove) { $forward += '-Remove' }
    if ($Path.Count -gt 0) { $forward += @('-Path') + @($Path | ForEach-Object { "`"$_`"" }) }
    if ($PSBoundParameters.ContainsKey('Repo')) { $forward += @('-Repo', "`"$Repo`"") }
    try {
        # Hidden window: the elevated run shows no second console, so only UAC appears.
        $elevated = Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -WindowStyle Hidden `
            -ArgumentList $forward -Wait -PassThru
        # The elevated process writes the result file; print it here because its own output is hidden.
        if (Test-Path -LiteralPath $resultPath) { Get-Content -LiteralPath $resultPath -Raw }
        exit $elevated.ExitCode
    } catch {
        Write-Result @{ elevated = $false; action = 'none'; reason = 'authorization-declined'
            message = $_.Exception.Message }
        exit 1
    }
}

$candidates = if ($Path.Count -gt 0) {
    @($Path)
} else {
    @($Repo, (Join-Path $env:USERPROFILE '.dsh'), (Join-Path $env:LOCALAPPDATA 'pnpm'))
}

$applied = @()
$missing = @()
$failed = @()
foreach ($target in $candidates) {
    if (-not (Test-Path -LiteralPath $target)) { $missing += [string]$target; continue }
    try {
        if ($Remove) { Remove-MpPreference -ExclusionPath $target -ErrorAction Stop }
        else { Add-MpPreference -ExclusionPath $target -ErrorAction Stop }
        $applied += [string]$target
    } catch {
        $failed += @{ path = [string]$target; message = $_.Exception.Message }
    }
}

# Guarded reads: without elevation these cmdlets throw, and an unguarded call renders the whole
# error record into the result instead of a readable report.
$excluded = @()
try { $excluded = @((Get-MpPreference -ErrorAction Stop).ExclusionPath) }
catch { $excluded = @('unavailable: ' + $_.Exception.Message) }
$realTime = 'unavailable'
try { $realTime = (Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled } catch { }

$result = @{
    elevated = $true
    action = $(if ($Remove) { 'remove' } else { 'add' })
    applied = $applied
    missing = $missing
    failed = $failed
    excluded = $excluded
    realTime = $realTime
}
Write-Result $result
exit $(if ($failed.Count -eq 0) { 0 } else { 1 })
