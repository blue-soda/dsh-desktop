# Regenerate the desktop icons and make sure the main.ts change is present.
#
#   pwsh -File apply-icons.ps1
#
# Uses the DSH bundled Python (which ships Pillow). Override with -Python if you
# have another interpreter that has Pillow installed.
param(
  [string]$Repo = 'C:\Workspace\deepseek-harness',
  [string]$Python = "$env:USERPROFILE\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"
)

$ErrorActionPreference = 'Stop'
$kit = Split-Path -Parent $MyInvocation.MyCommand.Path
$mainTs = Join-Path $Repo 'apps\desktop\src\main.ts'

Write-Host "== 1) 准备图标资源 ==" -ForegroundColor Cyan
if (Test-Path $Python) {
  $env:DSH_REPO = $Repo
  & $Python (Join-Path $kit 'make-icons.py') (Join-Path $kit 'source.png')
} else {
  Write-Warning "找不到 Python: $Python"
  Write-Host "  改用本包内预生成的图标副本（generated\ 与 bin\dsh-desktop.ico）"
  Copy-Item "$kit\generated\*" (Join-Path $Repo 'apps\desktop\resources\') -Force
  $binDir = Join-Path $env:USERPROFILE 'bin'
  New-Item -ItemType Directory $binDir -Force | Out-Null
  Copy-Item (Join-Path $kit 'bin\dsh-desktop.ico') $binDir -Force
  Write-Host "  已复制 3 个仓库资源 + 快捷方式图标。"
}

Write-Host "`n== 2) 检查源码改动 ==" -ForegroundColor Cyan
if (Select-String -Path $mainTs -Pattern 'icon-windows\.ico' -Quiet) {
  Write-Host "  main.ts 已包含窗口图标改动，跳过。"
} else {
  Write-Host "  未包含，正在应用 patch..."
  git -C $Repo apply (Join-Path $kit 'main.ts.patch')
  if ($LASTEXITCODE -ne 0) { throw "git apply 失败；请手动参考 main.ts.patch" }
  Write-Host "  已应用。"
}

Write-Host "`n== 3) 重新构建 ==" -ForegroundColor Cyan
Write-Host "  现在执行（构建期间不要启动 Desktop）："
Write-Host "    cd $Repo; pnpm --filter @deepseek-ai/dsh-desktop run build" -ForegroundColor Yellow
Write-Host "  然后重启 Desktop 才会看到新图标。"
