# DSH Desktop 定制版构建工具（dsh-desktop）

从上游源码产出一份**定制版 DeepSeek Harness Desktop**（Windows x64）：一条命令构建，并发布到 [最新 Release](https://github.com/blue-soda/dsh-desktop/releases/latest)。本仓库同时保存这套定制的**全部真源**——单一补丁、图标资源、提权脚本与启动器，换台电脑也能重建。

定制共五块：

1. **图标外观** —— 窗口/任务栏图标、托盘图标、关于面板图标、桌面快捷方式图标
2. **启动方式** —— 无终端窗口的快捷方式、快速启动脚本、`dsh` 进 TUI 的命令
3. **冷启动性能** —— Windows Defender 排除项（消除实时扫描造成的冷启动开销）
4. **任务栏身份** —— 让固定到任务栏的项目显示为 DSH，而不是 Electron
5. **自带插件** —— 安装包内置 `ds-harness-remote` 并默认启用（见下方「自带的 remote 插件」）

本包是自包含的：换电脑或重新 clone 仓库后，可以用 `packaging/dsh-desktop.patch` + 一条命令重新产出安装包（见「一键构建」），也可以照下面各节手工复原。

## 仓库结构

```
dsh-desktop/
  README.md
  build-release.cmd      ← 唯一入口：.\build-release.cmd -Tag r5 -Verify
  packaging/             ← dsh-desktop.patch、.env.windows.template、release-notes.template.md
  assets/                ← 图标素材与生成脚本、启动器副本、main.ts.patch
  maintenance/           ← Defender 排除项、任务栏身份、快捷方式写入器
  tools/                 ← 构建与探针的 Node 实现
  docs/                  ← 历史发行说明
  build/  dist/          ← 构建目录与产物（gitignored）
```

| 文件 | 作用 |
|---|---|
| `build-release.cmd` + `tools/*.mjs` | **一键构建**：隔离 clone → 打补丁 → 写打包环境 → 装依赖 → 出 exe → 校验和与发行说明（可加 `-Verify` / `-Upload`） |
| `packaging/dsh-desktop.patch` | **完整**的 DSH 侧改动（图标资源与源码、提权对话框、内置插件机制）。构建时打到上游基线上，是"新电脑一键重建"的唯一真源 |
| `packaging/.env.windows.template` | 打包环境模板（appId、更新环境、策略源站），构建时写入隔离 checkout |
| `packaging/release-notes.template.md` | 发行说明模板，构建时自动填入 SHA256、体积与实际解析到的插件版本 |
| `assets/source.png` | 源美术图（透明背景 PNG，越大越好） |
| `assets/make-icons.py` | 图标生成：居中补方 → 按模式裁剪（默认 `--mode head` 头部特写，`--mode full` 整身）→ 收紧到内容边界 + 2% 余量 |
| `assets/apply-icons.ps1` | 一键：生成资源 + 检查/应用 patch + 提示构建（没有 Python 时退回预生成副本）。**本仓库保留的唯一 `.ps1`**，只用于重新生成图标，不参与构建 |
| `assets/main.ts.patch` | `apps/desktop/src/main.ts` 的**两处**源码改动：窗口图标 + 未打包启动的 AppUserModelID（完整改动已并入 `packaging/dsh-desktop.patch`） |
| `assets/generated/` | 三个仓库资源的**预生成副本**，仅在无法运行 `make-icons.py` 时使用（无 Python/Pillow） |
| `assets/bin/` | 机器级启动器副本（`dsh.cmd` 进 TUI、`dsh-desktop.cmd` 快速启动、`dsh-desktop-full.cmd` 完整准备、`dsh-desktop.vbs` 无窗口包装） |
| `assets/bin/dsh-desktop.ico` | **桌面快捷方式图标**。它不在仓库里，`make-icons.py` 也只在 `%USERPROFILE%\bin` 已存在时才写；放进包里可去掉"先拷脚本再生成"的顺序依赖 |
| `maintenance/defender-exclusions.ps1` | 添加/移除 Defender 排除项（checkout、`~/.dsh`、pnpm store；可用 `-Path` 指定、`-Remove` 撤销）。自助提权且**隐藏窗口**，用户只看到 UAC；与安装版自带的那份是同一形态 |
| `maintenance/set-taskbar-identity.cmd` | 把同一个 AUMID 写进桌面与开始菜单快捷方式，修复"固定到任务栏显示 Electron" |
| `maintenance/shortcut-writer/` | 上面脚本调用的极小 Electron 应用（用 `shell.writeShortcutLink` 写快捷方式并输出 `result.json`） |

> 图标都能由 `assets/source.png` + `assets/make-icons.py` 重新生成（输出确定），所以 `assets/generated/` 与 `assets/bin/dsh-desktop.ico`
> 属于**冗余保险**而非必需品。改动余量或裁剪方式后请重新生成，并同步覆盖这两处副本，避免与脚本输出不一致。

## 一键构建（build-release.cmd）

从零产出安装包。**构建完全隔离在本仓库的 `build\` 目录内**（clone 上游、装依赖、打包、产物都在那里），不会改动你其它的 checkout。

```powershell
# PowerShell 需要 .\ 前缀（默认不从当前目录加载命令）；在 cmd.exe 里可以直接写 build-release.cmd
.\build-release.cmd -Tag r5 -Verify           # 构建 + 探针
.\build-release.cmd -Tag r5 -Verify -Upload   # 再加发布到 Release
.\build-release.cmd -Clean                    # 只清理 build\、dist\ 与本工具自己的临时文件
```

流程：预检（git/node/pnpm/gh）→ 在 `build\dsh` clone 上游（`--filter=blob:none`）→ `checkout --force <Base>` + 按补丁路径重置 + `git apply packaging\dsh-desktop.patch`（**每次从干净基线开始，可重复运行**）→ 写 `apps\desktop\.env.windows` → `pnpm install` → `package:win:x64:unsigned` → 把 exe 与 `.blockmap` 复制到 `dist\`，生成 `SHA256SUMS.txt` 与发行说明。

| 选项 | 说明 |
|---|---|
| `-Tag <name>` | 发布标签，默认 `r` + 时间戳；也用于发行说明与 `-Upload` |
| `-Base <commit>` | 上游基线，默认 `5badb15009` |
| `-Source <url>` | 上游仓库，默认官方 GitHub 仓库。**网络不通时**可指向本地已有的 checkout（如 `-Source C:\Workspace\deepseek-harness`）：`git clone` 只读该目录，隔离性不变，而且 `origin` 会指向它，后续 fetch 也不再依赖网络 |
| `-Clean` | 只清理 `build\`、`dist\`，以及本工具自己的 `%TEMP%\dsh-verify-*`、`dsh-build-*`、`dsh-defender-exclusions.*` |
| `-Verify` | 构建后跑三项断言（见下） |
| `-Upload` | `gh release create`，**默认关闭** |

**首次耗时**：clone + `pnpm install` + 运行时准备，视网络约 30–60 分钟；之后复用 `build\dsh` 会明显更快（每次仍会重置到基线并重打补丁）。

**常见失败与排查**

| 现象 | 原因与处理 |
|---|---|
| `download:electron ... fetch failed` | 访问 GitHub 下载 CDN 失败。脚本已固定设置 `ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/`；仍然失败时多为网络抖动，稍后重跑即可 |
| `pnpm install` 卡住或失败 | registry 慢/被挡。在 `packaging\.env.windows.template` 里放开 `DSH_DESKTOP_NPM_REGISTRY=https://registry.npmmirror.com`，重跑 |
| 磁盘不足 | 运行时 + Electron + 产物需要数 GB；脚本在剩余空间 < 20 GB 时告警 |
| `git apply` 失败 | 补丁与基线不匹配，或上一轮产物残留。脚本会**从补丁本身推导路径**再重置：tracked 文件还原到基线，补丁新增的 untracked 文件用 `clean -fd` 删除（**不用** `-x`，所以 `node_modules` 不会被删、不必重装），正常无需手工干预 |
| `ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY` | pnpm 想清空 `node_modules` 但在无终端时会中止询问。脚本已设 `confirmModulesPurge=false`，若仍出现可显式加 `--config.confirmModulesPurge=false` |
| `EPERM: operation not permitted, unlink '…\win-unpacked\…dll'` | 有实例正从 `build\dsh\…\win-unpacked` 运行，锁住了 electron-builder 要重写的文件。**关掉那个应用窗口再重跑**；脚本现在会在打包前就检测并报出（不会替你杀进程），而不是跑十几分钟后才失败 |

**`-Verify` 的三项断言**：

1. 运行时里 `@deepseek-ai/dsh` 的清单声明了内置插件——profile 启动按安装清单的依赖图解析插件行的包名，缺声明就会解析失败：该行拿不到 fiber，插件页显示"已启用 / 未运行"。
2. 用打包树对一个临时 profile 跑 `loadProfileDirectory` + `createRuntimeResolution`，断言 `skippedBundles` 为空且插件为 `mapped: true`。
3. 运行时里的插件 `dist` 与 **npm 上同版本**的内容逐文件比对；拉不到 npm 时报告 `SKIP`，**不会伪装通过**。

### 哪里还会用到 `powershell.exe`

**构建本身不用它**：`build-release.cmd` 只调用 `node tools\*.mjs`，哈希、JSON、探针、发布都在 Node 里完成；快捷方式的 AUMID 走 Electron 的 `shell.writeShortcutLink`。

仓库里保留两个 `.ps1`，因为 Windows 上**添加 Defender 排除项没有非 PowerShell 的受支持接口**——只有 `Add-MpPreference`，而直接改写排除项的注册表值在篡改防护（Tamper Protection）下不可靠：

| 文件 | 作用 | 说明 |
|---|---|---|
| `maintenance/defender-exclusions.ps1` | 写入 / 撤销 Defender 排除项 | **与安装版 `resources\defender-exclusions.ps1` 同一形态**；提权用 `Start-Process … -Verb RunAs -WindowStyle Hidden`，被提权的进程不显示窗口，所以只弹 UAC |
| `assets/apply-icons.ps1` | 重新生成图标资源并应用 `main.ts` 补丁 | 仅在你改图标时运行；已生成的副本在 `assets/generated/` |

用 PowerShell 7（`pwsh`）或系统自带的 Windows PowerShell 运行均可。

## 自带的 remote 插件

发布的安装包内置 [`ds-harness-remote`](https://github.com/blue-soda/ds-harness-remote)（从其他设备远程接入本机 DSH），**随包安装、默认启用**，不需要用户自己 `dsh plugin add`。

- **位置与声明**：插件以 npm 包 [`@blue-soda/dsh-remote`](https://www.npmjs.com/package/@blue-soda/dsh-remote) 在**构建时**装进运行时（依赖 spec `^0.4.28`），并写进运行时里 `@deepseek-ai/dsh` 的依赖清单。最后这步不能省——profile 启动按**安装清单的依赖图**解析插件行的包名，缺声明就会解析失败：该行拿不到 fiber，插件页显示「已启用 / 未运行」，UI 也不出现。
- **更新插件**：改 `apps/desktop/src/bundled-extras.ts` 里的 `BUNDLED_EXTRA_SPEC` 一个字符串即可，不需要 vendor tarball。
- **默认配置**：新建 profile 时写入 `%USERPROFILE%\.dsh\profiles\desktop\cordis.patch.yml`，之后由用户自己维护：

  ```yaml
  - id: ds-harness-remote
    config:
      enabled: true
      role: both
      serverUrl: https://sakakibara.ink:8443
  ```

- **改配置 / 关闭**：编辑上面那段即可——`role` 可取 `host` / `client` / `both`，改成 `enabled: false` 或删掉整段即关闭；重启应用生效。
- **首次连接需授权一次**：设备凭证不随包分发（否则所有安装会共用同一个设备身份）。连接与设备密钥位于 `%USERPROFILE%\.dsh\remote\`。

## 图标定制由三部分组成

1. **仓库内的资源**（`apps/desktop/resources/`）
   - `tray-windows.ico` — 托盘/状态栏图标（dev 下读取；16/20/24/32/40/48/64）
   - `icon-windows.ico` — 窗口/任务栏图标（**新增文件**；16→256）
   - `icon-windows.png` — 关于面板图标（1024²）
2. **仓库内的源码改动**（`apps/desktop/src/main.ts`，共两处）
   - 未打包启动时 `BrowserWindow` 没有 `icon`，Windows 会显示 electron.exe 的图标；patch 补上这个 `icon`。
   - 未打包启动没有 AppUserModelID，任务栏把窗口归到 electron.exe 名下；patch 补上 `app.setAppUserModelId('com.deepseek.harness.dev')`，与快捷方式里的同一个 ID 配对。
3. **仓库外的机器级文件**（不在 git 里，换机需重建）
   - `%USERPROFILE%\bin\` 下的启动器与 `dsh-desktop.ico`
   - 桌面快捷方式（目标 `wscript.exe`，参数指向 `dsh-desktop.vbs`，图标用 `dsh-desktop.ico`）
   - 用户级环境变量 `DSH_HOME=%USERPROFILE%\.dsh`
   - 用户级 PATH 包含 `%USERPROFILE%\bin`（`dsh` 命令进 TUI）

## 在新电脑 / 新 checkout 上还原

```powershell
# 在仓库根目录执行；PowerShell 里脚本一律要 .\ 前缀

# 1) 只要安装包：直接看「一键构建」——.\build-release.cmd 会自己 clone 上游、重置到基线、打补丁并产出 exe。

# 2) 要在本机开发环境上应用同一套改动：
git clone https://github.com/deepseek-ai/deepseek-harness.git
git -C deepseek-harness apply --binary "$env:USERPROFILE\dsh-desktop\packaging\dsh-desktop.patch"

# 3) 重建机器级部件：把 assets\bin\ 里的脚本拷到 %USERPROFILE%\bin，
#    设置用户级 DSH_HOME 与 PATH，再重建桌面快捷方式（见下方脚本片段）

# 4) 冷启动优化（可选，会弹 UAC）
.\maintenance\defender-exclusions.ps1

# 5) 任务栏身份（把 AUMID 写进快捷方式，配合已构建的 main.ts）
.\maintenance\set-taskbar-identity.cmd
```

重建快捷方式：

```powershell
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\DeepSeek Harness Desktop.lnk")
$lnk.TargetPath = 'C:\Windows\System32\wscript.exe'
$lnk.Arguments = '"' + $env:USERPROFILE + '\bin\dsh-desktop.vbs"'
$lnk.WorkingDirectory = 'C:\Workspace\deepseek-harness'
$lnk.IconLocation = "$env:USERPROFILE\bin\dsh-desktop.ico,0"
$lnk.Save()
```

## 还原成官方图标

图标来自仓库内的 git 跟踪文件，所以直接回退即可（本机备份目录 `%USERPROFILE%\dsh-icon-backup-*` 只是保险）：

```powershell
cd C:\Workspace\deepseek-harness
git checkout -- apps/desktop/resources/icon-windows.png apps/desktop/resources/tray-windows.ico apps/desktop/src/main.ts
Remove-Item apps\desktop\resources\icon-windows.ico
pnpm --filter @deepseek-ai/dsh-desktop run build
```

## 调整外观

- **构图**：`--mode head`（当前默认：头部特写，16 px 下仍能看出脸）或 `--mode full`（整身）。
  ```powershell
  python assets\make-icons.py --mode full    # 换回整身；改完记得重启应用
  ```
- **更大/更小**：`--margin`（0 = 图形贴满整块画布；当前 0.02）。
- **头部窗口的位置与大小**：改 `make-icons.py` 顶部的 `HEAD_EDGE`（默认 0.58）与 `HEAD_CENTRE`（默认 0.50, 0.36）。
- **注意**：不要运行 `pnpm run render:tray-icon`，它会从仓库自带的 `icon-windows.svg` 重新生成**官方**托盘图标，覆盖你的定制。
- 改完任何参数后，记得把新的三个资源与 `assets\bin\dsh-desktop.ico` 重新拷进本包的 `assets\generated\` 和 `assets\bin\`，否则包内副本会与脚本输出不一致。

## 冷启动优化：Defender 排除项

开发版 Desktop 冷启动要读取大量文件（checkout、`~/.dsh`、pnpm store），而 Windows Defender 的**实时扫描会为每个文件收费**——这是冷启动里最贵的一项。脚本给这三个目录加排除项，**整机的实时保护不受影响**：

```powershell
# 添加（会弹出 UAC，自助提权；提权进程隐藏窗口，所以只看到 UAC 一个窗口）
.\maintenance\defender-exclusions.ps1

# 撤销（同样提权）
.\maintenance\defender-exclusions.ps1 -Remove

# 默认排除 %DSH_REPO%（默认 C:\Workspace\deepseek-harness）、%USERPROFILE%\.dsh、%LOCALAPPDATA%\pnpm
# 也可以显式给出路径：.\maintenance\defender-exclusions.ps1 -Path D:\some\path
```

- 只处理**当前存在**的路径；不存在的会列在结果的 `missing` 里。
- 结果写入 `%TEMP%\dsh-defender-exclusions.json` 并打印（含生效列表与 `realTime` 状态）。
- 写入必须走 `Add-MpPreference`，所以这份脚本用 PowerShell 实现，并与安装版保持同一形态（见「哪里还会用到 powershell.exe」）。
- 排除后这些目录不再被实时扫描——只在你信任其内容时保留。
- 验证方式：重启 Windows 后给第一次启动计时，退出后再启动一次对比。
- 实时保护本身保持**开启**，不需要也不建议关闭篡改防护。

## 固定到任务栏

未打包的 Electron 没有应用标识，Windows 只能按 `electron.exe` 分组：右键运行中的窗口显示 "Electron"，固定下来的目标也是 electron.exe（再次打开就是一个空白的 Electron 窗口）。修复由两半组成，缺一不可：

| 一半 | 内容 |
|---|---|
| 应用侧 | `main.ts` 里的 `app.setAppUserModelId('com.deepseek.harness.dev')`（仅未打包的 Windows 启动；打包版保持 electron-builder 派生的 ID） |
| 快捷方式侧 | 桌面**和开始菜单**快捷方式写入同一个 AUMID——Windows 固定时是去开始菜单找匹配项的 |

```powershell
.\maintenance\set-taskbar-identity.cmd
# 可选：-Repo <checkout> -Aumid <id> -Name <快捷方式名>
```

完成后：

1. 右键任务栏上旧的 **Electron** 固定项 → **从任务栏取消固定**；
2. **退出并重启 Desktop**（AUMID 是应用启动时设置的，旧进程没有）；
3. 重新固定：右键运行中的窗口 → **固定到任务栏**，或在开始菜单搜索 "DeepSeek Harness Desktop" → 右键 → 固定。现在应显示我们自己的名称与图标，并与运行中的窗口合并为同一个按钮。

脚本调用仓库里的 Electron，需要 `apps/desktop/node_modules/electron` 存在。若在 DSH 的 shell 里执行，脚本会临时清掉继承来的 `ELECTRON_RUN_AS_NODE`（否则 Electron 会以纯 Node 启动，`require('electron')` 失败）。

## 生效范围与限制

- 只对**开发版**（未打包，从本 checkout 启动）有效。打包安装版的图标在签名资源里，改工作区不会影响它。
- 改动本质是资源替换，不需要额外运行时；重启应用即生效，改源码才需要重新构建。
- Windows 有图标缓存：任务栏/桌面若仍是旧图，重启 explorer 或注销一次。
