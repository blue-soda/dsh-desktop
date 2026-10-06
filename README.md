# DSH 使用体验恢复包（dsh-restore-kit）

把 Electron 开发版的 DeepSeek Harness Desktop 恢复成你习惯的样子。本仓库同时发布**打包好的定制版安装包**（[最新 Release](https://github.com/blue-soda/dsh-restore-kit/releases/latest)）。

定制共五块：

1. **图标外观** —— 窗口/任务栏图标、托盘图标、关于面板图标、桌面快捷方式图标
2. **启动方式** —— 无终端窗口的快捷方式、快速启动脚本、`dsh` 进 TUI 的命令
3. **冷启动性能** —— Windows Defender 排除项（消除实时扫描造成的冷启动开销）
4. **任务栏身份** —— 让固定到任务栏的项目显示为 DSH，而不是 Electron
5. **自带插件** —— 安装包内置 `ds-harness-remote` 并默认启用（见下方「自带的 remote 插件」）

本包是自包含的：换电脑或重新 clone 仓库后照下面做一遍即可复原。

## 包含什么

| 文件 | 作用 |
|---|---|
| `source.png` | 源美术图（透明背景 PNG，越大越好） |
| `make-icons.py` | 生成脚本：居中补方 → 按模式裁剪（默认 `--mode head` 头部特写，`--mode full` 整身）→ 收紧到内容边界 + 2% 余量 |
| `main.ts.patch` | `apps/desktop/src/main.ts` 的**两处**源码改动：窗口图标 + 未打包启动的 AppUserModelID |
| `apply-icons.ps1` | 一键：生成资源 + 检查/应用 patch + 提示构建（没有 Python 时自动退回预生成副本） |
| `generated/` | 三个仓库资源的**预生成副本**，仅在无法运行 `make-icons.py` 时使用（无 Python/Pillow） |
| `bin/` | 机器级启动器副本（`dsh.cmd` 进 TUI、`dsh-desktop.cmd` 快速启动、`dsh-desktop-full.cmd` 完整准备、`dsh-desktop.vbs` 无窗口包装） |
| `bin/dsh-desktop.ico` | **桌面快捷方式图标**。它不在仓库里，`make-icons.py` 也只在 `%USERPROFILE%\bin` 已存在时才写；放进包里可去掉"先拷脚本再生成"的顺序依赖 |
| `maintenance/defender-exclusions.ps1` | 添加/移除 Windows Defender 的三个路径排除项，消除冷启动时的实时扫描成本。自助提权，`-Remove` 可撤销 |
| `maintenance/set-taskbar-identity.ps1` | 把同一个 AUMID 写进桌面与开始菜单快捷方式，修复"固定到任务栏显示 Electron" |
| `maintenance/shortcut-writer/` | 上面脚本调用的极小 Electron 应用（用 `shell.writeShortcutLink` 写快捷方式并输出 `result.json`） |

> 图标都能由 `source.png` + `make-icons.py` 重新生成（输出确定），所以 `generated/` 与 `bin/dsh-desktop.ico`
> 属于**冗余保险**而非必需品。改动余量或裁剪方式后请重新生成，并同步覆盖这两处副本，避免与脚本输出不一致。

## 自带的 remote 插件

发布的安装包内置 [`ds-harness-remote`](https://github.com/blue-soda/ds-harness-remote)，用于从其他设备远程接入本机的 DSH。它**随包安装、默认启用**，用户不需要自己 `dsh plugin add`。

**它是怎么进去的**：插件 tarball 放在 DSH 仓库的 `apps/desktop/vendor/`，构建时打进运行时，并写进运行时里 `@deepseek-ai/dsh` 的依赖清单。最后一步不能省——profile 启动时按**安装清单的依赖图**解析插件行的包名，清单没声明就会解析失败：该行拿不到 fiber，插件页显示「已启用 / 未运行」，UI 也不会出现。

**默认配置**：新建 profile 时会在 `%USERPROFILE%\.dsh\profiles\desktop\cordis.patch.yml` 写入下面这段；此后由用户自己维护，升级不会覆盖已有条目。

```yaml
- id: ds-harness-remote
  config:
    enabled: true
    role: both                  # host 与 client 同时启用
    serverUrl: https://sakakibara.ink:8443
    codex:
      enabled: true
```

| 项 | 说明 |
|---|---|
| `role` | `host`（本机作为被接入端）/ `client`（本机作为接入端）/ `both`。发行版默认 `both`，启动时会分别建立两套设备身份 |
| `serverUrl` | 连接的中继服务器。发行版固定指向 `https://sakakibara.ink:8443` |
| **首次连接要授权** | 设备凭证**不随包分发**（否则所有安装会共用同一个设备身份），用户需在 Remote 界面完成一次授权 |
| **隐私** | 启用后插件会与该服务器建立连接，并在 `%USERPROFILE%\.dsh\remote\` 下生成设备密钥与服务器凭证 |
| **关闭方式** | 把上面 `enabled` 改成 `false`，或删掉整段；改完重启应用生效 |

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

## 在新电脑 / 新 checkout 上恢复

```powershell
# 1) 仓库就位后，运行本包（默认 Python 用 DSH 自带的那份，含 Pillow）
pwsh -File $env:USERPROFILE\dsh-restore-kit\apply-icons.ps1

# 2) 按提示构建（构建期间不要启动 Desktop，tsdown 会先清空 lib/*.js）
cd C:\Workspace\deepseek-harness
pnpm --filter @deepseek-ai/dsh-desktop run build

# 3) 重建机器级部件：把 bin\ 里的脚本拷到 %USERPROFILE%\bin，
#    设置用户级 DSH_HOME 与 PATH，再重建桌面快捷方式（见下方脚本片段）

# 4) 冷启动优化（可选，会弹 UAC）
pwsh -File $env:USERPROFILE\dsh-restore-kit\maintenance\defender-exclusions.ps1

# 5) 任务栏身份（把 AUMID 写进快捷方式，配合已构建的 main.ts）
pwsh -File $env:USERPROFILE\dsh-restore-kit\maintenance\set-taskbar-identity.ps1
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
  python make-icons.py --mode full    # 换回整身；改完记得重启应用
  ```
- **更大/更小**：`--margin`（0 = 图形贴满整块画布；当前 0.02）。
- **头部窗口的位置与大小**：改 `make-icons.py` 顶部的 `HEAD_EDGE`（默认 0.58）与 `HEAD_CENTRE`（默认 0.50, 0.36）。
- **注意**：不要运行 `pnpm run render:tray-icon`，它会从仓库自带的 `icon-windows.svg` 重新生成**官方**托盘图标，覆盖你的定制。
- 改完任何参数后，记得把新的三个资源与 `bin\dsh-desktop.ico` 重新拷进本包的 `generated\` 和 `bin\`，否则包内副本会与脚本输出不一致。

## 冷启动优化：Defender 排除项

开发版 Desktop 冷启动要读取大量文件（checkout、`~/.dsh`、pnpm store），而 Windows Defender 的**实时扫描会为每个文件收费**——这是冷启动里最贵的一项。脚本给这三个目录加排除项，**整机的实时保护不受影响**：

```powershell
# 添加（会弹出 UAC，自助提权）
pwsh -File $env:USERPROFILE\dsh-restore-kit\maintenance\defender-exclusions.ps1

# 撤销（同样提权）
pwsh -File $env:USERPROFILE\dsh-restore-kit\maintenance\defender-exclusions.ps1 -Remove
```

- 只处理**当前存在**的路径；不存在的会列在结果的 `missing` 里。
- 结果写入 `%TEMP%\defender-exclusions-result.json` 并打印（含生效列表与 `realTime` 状态）。
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
pwsh -File $env:USERPROFILE\dsh-restore-kit\maintenance\set-taskbar-identity.ps1
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
