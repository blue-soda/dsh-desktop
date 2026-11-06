<#
.SYNOPSIS
  Add the distribution touches to an installed stock DeepSeek Harness Desktop.

.DESCRIPTION
  Applies what this kit's installer normally ships baked in: the Windows/tray icons, the bundled
  remote plugin, the profile seed entry, and the Windows Security exclusions.

  The install directory is never hard-coded. It is taken from -InstallPath, else derived from this
  script's own location, else read from the uninstall registry, else picked from the conventional
  locations, and finally asked for interactively with validation.

.PARAMETER InstallPath
  Install directory of the application. Detected when omitted.

.PARAMETER PluginSpec
  Registry spec to install into the profile. Defaults to ^0.5.7.

.PARAMETER ServerUrl
  Relay/server URL written into the seeded profile entry.

.PARAMETER Profile
  Profile that receives the plugin and the seed entry. Defaults to desktop.

.PARAMETER SkipIcons
  Leave the packaged icons untouched.

.PARAMETER SkipPlugin
  Do not install the plugin or write the seed entry.

.PARAMETER SkipDefender
  Do not touch Windows Security exclusions.

.PARAMETER DryRun
  Report every planned action without changing anything.

.EXAMPLE
  .\dsh-customize.ps1 -DryRun

.EXAMPLE
  .\dsh-customize.ps1 -InstallPath 'C:\Program Files\DeepSeek Harness'
#>
[CmdletBinding()]
param(
  [string]$InstallPath,
  [switch]$All,
  [switch]$IncludeCustom,
  [string]$PluginSpec = '^0.5.7',
  [string]$ServerUrl = 'https://sakakibara.ink:8443',
  [string]$Profile = 'desktop',
  [switch]$SkipIcons,
  [switch]$SkipPlugin,
  [switch]$SkipDefender,
  [switch]$ExeIcon,
  [string]$RceditPath,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ExeName = 'DeepSeek Harness.exe'
$script:Changed = @()
$script:Problems = @()

function Say  { param([string]$Message) Write-Host "  $Message" }
function Ok   { param([string]$Message) Write-Host "  [ok] $Message" -ForegroundColor Green }
function Warn { param([string]$Message) Write-Host "  [!!] $Message" -ForegroundColor Yellow }
function Fail { param([string]$Message) Write-Host "  [xx] $Message" -ForegroundColor Red; $script:Problems += $Message }

function Test-InstallDir {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  return (Test-Path (Join-Path $Path $ExeName))
}

function New-Candidate {
  param([string]$Path, [string]$Version, [string]$Source)
  return [pscustomobject]@{
    Path     = $Path
    Version  = $Version
    Source   = $Source
    Custom   = (Test-Path (Join-Path $Path 'resources\defender-exclusions.ps1'))
    Running  = $false
    Artifact = ($Path -match '\.desktop-build|win-unpacked|\\build\\dsh\\')
  }
}

function Get-InstallCandidates {
  $byPath = @{}

  # 1. A copy this script sits inside is the strongest local hint.
  foreach ($dir in @($PSScriptRoot, (Split-Path $PSScriptRoot -Parent), (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))) {
    if ($dir -and (Test-InstallDir $dir)) {
      $resolved = (Resolve-Path $dir).Path
      if (-not $byPath.ContainsKey($resolved.ToLower())) { $byPath[$resolved.ToLower()] = New-Candidate $resolved '' 'script' }
    }
  }

  # 2. Every uninstall entry records the location and the human-readable version.
  foreach ($root in @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
    if (-not (Test-Path $root)) { continue }
    foreach ($key in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
      $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
      if (-not $props -or $props.DisplayName -notlike '*DeepSeek Harness*') { continue }
      $location = ([string]$props.InstallLocation).Trim('"', ' ')
      if (-not (Test-InstallDir $location)) { continue }
      $resolved = (Resolve-Path $location).Path
      $byPath[$resolved.ToLower()] = New-Candidate $resolved ([string]$props.DisplayVersion) 'registry'
    }
  }

  # 3. Running instances show the copy the person is actually using.
  $running = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -Unique | Where-Object { $_ })
  foreach ($path in $running) {
    $dir = Split-Path $path -Parent
    if (-not (Test-InstallDir $dir)) { continue }
    $resolved = (Resolve-Path $dir).Path
    if (-not $byPath.ContainsKey($resolved.ToLower())) { $byPath[$resolved.ToLower()] = New-Candidate $resolved '' 'running' }
    $byPath[$resolved.ToLower()].Running = $true
  }

  # 4. Conventional roots catch copies the registry does not know about.
  foreach ($root in @('C:\Programs', 'C:\Program Files', 'C:\Program Files (x86)', (Join-Path $env:LOCALAPPDATA 'Programs'))) {
    if (-not (Test-Path $root)) { continue }
    foreach ($file in (Get-ChildItem $root -Recurse -Depth 2 -File -Filter $ExeName -ErrorAction SilentlyContinue)) {
      $resolved = $file.DirectoryName
      if (-not $byPath.ContainsKey($resolved.ToLower())) { $byPath[$resolved.ToLower()] = New-Candidate $resolved '' 'scan' }
    }
  }

  return @($byPath.Values) | Sort-Object @{ Expression = { if ($_.Artifact) { 1 } else { 0 } } }, @{ Expression = { if ($_.Version) { $_.Version } else { '0' } }; Descending = $true }, Path
}

function Format-CandidateTable {
  param($Candidates)
  Say 'Detected installations:'
  Say '  #  version          custom  running  source    path'
  $index = 0
  foreach ($c in $Candidates) {
    $index++
    Say ("  {0}  {1,-15}  {2,-6}  {3,-7}  {4,-8}  {5}" -f $index, $(if ($c.Version) { $c.Version } else { '?' }), $c.Custom, $c.Running, $c.Source, $c.Path)
    if ($c.Artifact) { Say '       (build-tree artifact, not an installed copy)' }
  }
}

function Select-Target {
  param($Candidates)

  if ($Candidates.Count -eq 0) { return @() }

  $usable = @($Candidates | Where-Object { -not $_.Artifact })
  if (-not $IncludeCustom) {
    $stock = @($usable | Where-Object { -not $_.Custom })
    if ($stock.Count -gt 0) { $usable = $stock }
  }
  if ($usable.Count -eq 0) { $usable = @($Candidates) }

  if ($All) { return $usable }
  if ($usable.Count -eq 1) {
    Ok "using the only candidate: $($usable[0].Path)"
    return @($usable[0])
  }

  Format-CandidateTable $Candidates
  Say ''
  Say 'Which installation should receive the customization?'
  Say '  Enter a number, A for all usable candidates, or press Enter to cancel.'
  while ($true) {
    $answer = Read-Host '  choice'
    if ([string]::IsNullOrWhiteSpace($answer)) { return @() }
    if ($answer -match '^(?i)a$') { return $usable }
    $number = 0
    if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Candidates.Count) {
      return @($Candidates[$number - 1])
    }
    Warn 'not a valid choice.'
  }
}

function Confirm-AppClosed {
  param($Targets)
  foreach ($target in $Targets) {
    $running = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and ((Split-Path $_.Path -Parent) -eq $target.Path) })
    if ($running.Count -eq 0) { continue }
    Warn "$($target.Path) is running ($($running.Count) process(es)); its files cannot be replaced while it runs."
    Say 'Close that window, then press Enter to re-check, or type S to stop.'
    while ($true) {
      $answer = Read-Host '  [Enter] re-check / S stop'
      if ($answer -match '^(?i)s') { return $false }
      $still = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and ((Split-Path $_.Path -Parent) -eq $target.Path) })
      if ($still.Count -eq 0) { Ok "$($target.Path) is closed."; break }
      Warn 'Still running.'
    }
  }
  return $true
}

function Invoke-IconSwap {
  param([string]$Root)
  $assets = Join-Path $PSScriptRoot 'assets'
  $maps = @(
    @{ Source = (Join-Path $assets 'icon.png');  Target = (Join-Path $Root 'resources\icon.png');  Label = 'window icon' },
    @{ Source = (Join-Path $assets 'tray.ico');  Target = (Join-Path $Root 'resources\tray.ico');  Label = 'tray icon' }
  )
  foreach ($map in $maps) {
    if (-not (Test-Path $map.Source)) { Fail "missing asset $($map.Source)"; continue }
    if (-not (Test-Path $map.Target)) { Warn "the packaged $($map.Label) was not found at $($map.Target); skipped"; continue }
    $sourceHash = (Get-FileHash $map.Source -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash $map.Target -Algorithm SHA256).Hash
    if ($sourceHash -eq $targetHash) { Ok "$($map.Label) already matches."; continue }
    if ($DryRun) { Say "would replace $($map.Label): $($map.Target)"; continue }
    $backup = "$($map.Target).bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $map.Target -Destination $backup -Force
    Copy-Item -LiteralPath $map.Source -Destination $map.Target -Force
    Ok "$($map.Label) replaced (backup: $(Split-Path $backup -Leaf))."
    $script:Changed += $map.Label
  }
}

function Resolve-Rcedit {
  param([string]$Explicit)
  if ($Explicit) {
    if (Test-Path $Explicit) { return (Resolve-Path $Explicit).Path }
    Fail "rcedit not found at '$Explicit'."
    return $null
  }
  $cache = Join-Path $env:LOCALAPPDATA 'electron-builder\Cache\winCodeSign'
  if (Test-Path $cache) {
    $found = Get-ChildItem $cache -Recurse -File -Filter 'rcedit-x64.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
  }
  $onPath = Get-Command 'rcedit-x64.exe' -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }
  return $null
}

function Get-ExeIconStatePath {
  param([string]$Root)
  return (Join-Path $Root 'resources\dsh-customize.json')
}

function Test-ExeIconApplied {
  param([string]$Root)
  $exe = Join-Path $Root $ExeName
  $icon = Join-Path (Join-Path $PSScriptRoot 'assets') 'icon.ico'
  $statePath = Get-ExeIconStatePath $Root
  if (-not (Test-Path $exe) -or -not (Test-Path $icon) -or -not (Test-Path $statePath)) { return $false }
  try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { return $false }
  if (-not $state.exeSha256 -or -not $state.iconSha256) { return $false }
  return ($state.exeSha256 -eq (Get-FileHash $exe).Hash) -and ($state.iconSha256 -eq (Get-FileHash $icon).Hash)
}

function Invoke-ExeIcon {
  param([string]$Root)
  $exe = Join-Path $Root $ExeName
  $icon = Join-Path (Join-Path $PSScriptRoot 'assets') 'icon.ico'
  if (-not (Test-Path $exe)) { Fail "no executable at $exe"; return }
  if (-not (Test-Path $icon)) { Fail "missing asset $icon"; return }
  if (Test-ExeIconApplied $Root) { Ok 'the executable icon already matches.'; return }
  $live = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and ((Split-Path $_.Path -Parent) -eq $Root) })
  if ($live.Count -gt 0) { Fail "$Root is running; close it before changing the executable icon."; return }
  $rcedit = Resolve-Rcedit -Explicit $RceditPath
  if (-not $rcedit) { Fail 'rcedit-x64.exe was not found; pass -RceditPath.'; return }
  if ($DryRun) { Say "would embed $icon into $exe using $rcedit"; return }
  $backup = "$exe.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  Copy-Item -LiteralPath $exe -Destination $backup -Force
  & $rcedit $exe --set-icon $icon | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Fail "rcedit exited with $LASTEXITCODE; restoring the original executable."
    Copy-Item -LiteralPath $backup -Destination $exe -Force
    return
  }
  $statePath = Get-ExeIconStatePath $Root
  [ordered]@{
    exeSha256  = (Get-FileHash $exe).Hash
    iconSha256 = (Get-FileHash $icon).Hash
    appliedAt  = (Get-Date).ToString('o')
    backup     = (Split-Path $backup -Leaf)
  } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
  Ok "executable icon embedded (backup: $(Split-Path $backup -Leaf))."
  Say 'Explorer caches icons: run "ie4uinit.exe -show" or sign out to refresh shortcuts.'
  $script:Changed += "executable icon @ $Root"
}

function Get-ProfilePatchPath {
  return (Join-Path (Join-Path (Join-Path $env:USERPROFILE '.dsh') 'profiles') (Join-Path $Profile 'cordis.patch.yml'))
}

function Invoke-PluginSetup {
  param([string]$Root)
  $patchPath = Get-ProfilePatchPath
  $hasRow = (Test-Path $patchPath) -and (@(Select-String -Path $patchPath -Pattern 'ds-harness-remote' -ErrorAction SilentlyContinue).Count -gt 0)

  if ($hasRow) {
    Ok "The profile already carries the remote entry: $patchPath"
  } else {
    $cli = Get-Command dsh -ErrorAction SilentlyContinue
    if (-not $cli) {
      Warn "The 'dsh' command is not on PATH, so the plugin cannot be installed from here."
      Say  "Install it once from the application (Manage dsh Command), or run: dsh plugin --profile $Profile add $PluginSpec"
    } elseif ($DryRun) {
      Say "would run: dsh plugin --profile $Profile add `"$PluginSpec`""
    } else {
      Say "installing $PluginSpec into profile '$Profile'..."
      & $cli.Source plugin --profile $Profile add $PluginSpec
      if ($LASTEXITCODE -ne 0) { Fail "plugin install exited with $LASTEXITCODE" } else { Ok 'plugin installed.'; $script:Changed += 'plugin' }
    }
  }

  if ((Test-Path $patchPath) -and (@(Select-String -Path $patchPath -Pattern 'ds-harness-remote' -ErrorAction SilentlyContinue).Count -gt 0)) { return }
  if (-not (Test-Path $patchPath)) { Warn "no profile patch at $patchPath; the profile is created by the first launch."; return }

  $entry = @(
    '',
    '- id: ds-harness-remote',
    '  config:',
    '    enabled: true',
    '    role: both',
    "    serverUrl: $ServerUrl",
    '    codex:',
    '      enabled: true',
    ''
  ) -join "`n"
  if ($DryRun) { Say "would append the remote seed entry to $patchPath"; return }
  Copy-Item -LiteralPath $patchPath -Destination "$patchPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')" -Force
  Add-Content -LiteralPath $patchPath -Value $entry -Encoding UTF8
  Ok "seed entry appended to $patchPath"
  $script:Changed += 'profile seed'
}

function Invoke-DefenderExclusions {
  param([string[]]$Roots)
  $targets = @(@($Roots) + @((Join-Path $env:USERPROFILE '.dsh')) | Select-Object -Unique)
  $inner = @'
$ErrorActionPreference = 'SilentlyContinue'
$paths = $env:DSH_CUSTOMIZE_TARGETS -split ';' | Where-Object { $_ }
$result = [ordered]@{ elevated = $true; applied = @(); failed = @(); excluded = @() }
foreach ($p in $paths) {
  Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue
  if ($?) { $result.applied += $p } else { $result.failed += $p }
}
$result.excluded = @((Get-MpPreference).ExclusionPath)
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $env:DSH_CUSTOMIZE_RESULT -Encoding UTF8
'@
  $nonce = [guid]::NewGuid().ToString('N')
  $script = Join-Path $env:TEMP "dsh-customize-defender-$nonce.ps1"
  $result = Join-Path $env:TEMP "dsh-customize-defender-$nonce.json"
  if ($DryRun) {
    foreach ($t in $targets) { Say "would exclude from Windows Security: $t" }
    return
  }
  Set-Content -LiteralPath $script -Value $inner -Encoding UTF8
  $env:DSH_CUSTOMIZE_TARGETS = ($targets -join ';')
  $env:DSH_CUSTOMIZE_RESULT = $result
  Say 'Windows will ask for administrator approval once.'
  try {
    # A process started through UAC does not inherit this process's environment, so the two values
    # are assigned inside the elevated command line instead of relying on the parent's variables.
    $command = "`$env:DSH_CUSTOMIZE_TARGETS = '$($targets -join ';' -replace "'", "''")'; " +
               "`$env:DSH_CUSTOMIZE_RESULT = '$($result -replace "'", "''")'; " +
               "& '$($script -replace "'", "''")'"
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -Wait -PassThru `
      -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command
  } catch {
    Fail 'administrator approval was declined; the exclusions were not added.'
    return
  }
  if (-not (Test-Path $result)) { Fail "no result from the elevated step (exit $($process.ExitCode))"; return }
  $report = Get-Content -LiteralPath $result -Raw | ConvertFrom-Json
  if ($report.failed.Count -gt 0) { Fail "could not exclude: $($report.failed -join ', ')" }
  foreach ($p in $report.applied) { Ok "excluded: $p"; $script:Changed += "exclusion $p" }
  $missing = @($targets | Where-Object { $report.excluded -notcontains $_ })
  if ($missing.Count -gt 0) { Warn "not present in the exclusion list afterwards: $($missing -join ', ')" }
  Remove-Item -LiteralPath $script, $result -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'DSH desktop customization' -ForegroundColor Cyan
Write-Host '=========================' -ForegroundColor Cyan
if ($DryRun) { Warn 'dry run: nothing will be changed.' }

$targets = @()
if ($InstallPath) {
  if (-not (Test-InstallDir $InstallPath)) { Fail "'$InstallPath' does not contain '$ExeName'."; exit 1 }
  $targets = @(New-Candidate (Resolve-Path $InstallPath).Path '' 'parameter')
} else {
  $candidates = @(Get-InstallCandidates)
  if ($candidates.Count -eq 0) {
    Warn 'no installation was detected.'
    Say "Enter the install directory (the folder containing '$ExeName'), or press Enter to cancel."
    while ($true) {
      $answer = Read-Host '  install directory'
      if ([string]::IsNullOrWhiteSpace($answer)) { break }
      $answer = $answer.Trim('"', ' ')
      if (Test-InstallDir $answer) { $targets = @(New-Candidate (Resolve-Path $answer).Path '' 'typed'); break }
      Fail "'$answer' does not contain '$ExeName'."
    }
  } else {
    $targets = @(Select-Target $candidates)
  }
}
if ($targets.Count -eq 0) { Fail 'cancelled: no installation selected.'; exit 1 }
foreach ($t in $targets) { Ok "target: $($t.Path)$(if ($t.Version) { " (version $($t.Version))" })" }

# Only require the application to be closed when something would actually be written.
$needsWrite = $false
if (-not $SkipIcons) {
  $assets = Join-Path $PSScriptRoot 'assets'
  foreach ($t in $targets) {
    foreach ($name in @('icon.png', 'tray.ico')) {
      $source = Join-Path $assets $name
      $destination = Join-Path $t.Path "resources\$name"
      if ((Test-Path $source) -and (Test-Path $destination) -and ((Get-FileHash $source).Hash -ne (Get-FileHash $destination).Hash)) { $needsWrite = $true }
    }
  }
}
if ($ExeIcon -and @($targets | Where-Object { -not (Test-ExeIconApplied $_.Path) }).Count -gt 0) { $needsWrite = $true }

if ((-not $DryRun) -and $needsWrite) {
  if (-not (Confirm-AppClosed -Targets $targets)) { Fail 'cancelled: a selected installation is still running.'; exit 1 }
}

Write-Host ''
Write-Host 'Icons' -ForegroundColor Cyan
if ($SkipIcons) { Say 'skipped (-SkipIcons).' } else { foreach ($t in $targets) { Invoke-IconSwap -Root $t.Path } }

Write-Host ''
Write-Host 'Executable icon (shortcut and Explorer)' -ForegroundColor Cyan
if ($ExeIcon) { foreach ($t in $targets) { Invoke-ExeIcon -Root $t.Path } } else { Say 'skipped (-ExeIcon): the shortcut keeps the stock executable icon.' }

Write-Host ''
Write-Host 'Profile and plugin' -ForegroundColor Cyan
if ($SkipPlugin) { Say 'skipped (-SkipPlugin).' } else { Invoke-PluginSetup }

Write-Host ''
Write-Host 'Windows Security exclusions' -ForegroundColor Cyan
if ($SkipDefender) { Say 'skipped (-SkipDefender).' } else { Invoke-DefenderExclusions -Roots @($targets | ForEach-Object { $_.Path }) }

Write-Host ''
Write-Host 'Summary' -ForegroundColor Cyan
if ($script:Changed.Count -eq 0) { Say 'already up to date: nothing changed.' } else { foreach ($c in $script:Changed) { Say "changed: $c" } }
Say 'Still manual: the first-launch authorization dialog and the taskbar identity (AUMID) stay stock.'
if ($script:Problems.Count -gt 0) { Write-Host ''; foreach ($p in $script:Problems) { Fail $p }; exit 1 }
Ok 'done.'
