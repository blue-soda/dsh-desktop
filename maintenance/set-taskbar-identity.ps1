<#
.SYNOPSIS
    Give the development Desktop one taskbar identity so it pins correctly.

.DESCRIPTION
    An unpackaged Electron launch declares no application identifier, so Windows groups its
    taskbar button under electron.exe: right-clicking the running window reads "Electron" and
    the shortcut "Pin to taskbar" writes relaunches a bare Electron window.

    apps/desktop/src/main.ts now calls `app.setAppUserModelId('com.deepseek.harness.dev')` for
    unpackaged Windows launches. This script writes the same identifier onto the desktop
    shortcut and a Start Menu copy — the Start Menu is where Windows looks for the shortcut a
    pinned button should launch.

    The write goes through Electron's own shell.writeShortcutLink, so `maintenance/shortcut-writer/`
    is launched with the checkout's Electron. No administrator rights are required.

.EXAMPLE
    pwsh -File set-taskbar-identity.ps1
    Rewrite both shortcuts and print their outcome.
#>
param(
    [string]$Repo = 'C:\Workspace\deepseek-harness',
    [string]$AppUserModelId = 'com.deepseek.harness.dev',
    [string]$ShortcutName = 'DeepSeek Harness Desktop'
)

$ErrorActionPreference = 'Stop'

$writerDirectory = Join-Path $PSScriptRoot 'shortcut-writer'
$resultFile = Join-Path $writerDirectory 'result.json'

$electronDirectory = Join-Path $Repo 'apps\desktop\node_modules\electron'
$pathFile = Join-Path $electronDirectory 'path.txt'
if (-not (Test-Path $pathFile)) { throw "找不到 Electron 包：$electronDirectory" }
$electron = Join-Path $electronDirectory ('dist\' + (Get-Content $pathFile -Raw).Trim())
if (-not (Test-Path $electron)) { throw "找不到 Electron 可执行文件：$electron" }

Remove-Item $resultFile -Force -ErrorAction SilentlyContinue

# A DSH shell inherits ELECTRON_RUN_AS_NODE=1 (Desktop uses it for its Host child); leaving it
# set would run Electron as plain Node, where require('electron') does not resolve.
$savedRunAsNode = $env:ELECTRON_RUN_AS_NODE
$env:ELECTRON_RUN_AS_NODE = $null
$env:DSH_SHORTCUT_AUMID = $AppUserModelId
$env:DSH_SHORTCUT_NAME = $ShortcutName
$env:DSH_SHORTCUT_REPO = $Repo
try {
    & $electron $writerDirectory | Out-Null
    $exitCode = $LASTEXITCODE
} finally {
    $env:ELECTRON_RUN_AS_NODE = $savedRunAsNode
    Remove-Item Env:DSH_SHORTCUT_AUMID, Env:DSH_SHORTCUT_NAME, Env:DSH_SHORTCUT_REPO -ErrorAction SilentlyContinue
}

if (-not (Test-Path $resultFile)) { throw "写入器没有生成结果（Electron 退出码 $exitCode）" }
$result = Get-Content $resultFile -Raw | ConvertFrom-Json
foreach ($entry in $result.results) {
    $state = if ($entry.written) { 'OK  ' } else { 'FAIL' }
    Write-Host "$state $($entry.file)"
}
Write-Host ""
Write-Host "AppUserModelID = $($result.appUserModelId)"
Write-Host "下一步：取消旧的任务栏固定项 → 重启 Desktop → 重新固定（见 README「固定到任务栏」）。"
if ($exitCode -ne 0) { exit $exitCode }
