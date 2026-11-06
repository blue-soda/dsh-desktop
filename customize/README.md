# dsh-customize

Adds this distribution's touches to an installed **DeepSeek Harness Desktop**, without replacing the
application. Useful when you update to an official build and want the plugin, the icons and the
Windows Security exclusions back.

## Usage

```powershell
.\dsh-customize.cmd                  # detect, then ask when several copies exist
.\dsh-customize.cmd -DryRun          # show every planned action, change nothing
.\dsh-customize.cmd -All             # apply the icons to every detected installation
.\dsh-customize.cmd -InstallPath 'C:\Program Files\DeepSeek Harness'
.\dsh-customize.cmd -PluginSpec '^0.5.7' -ServerUrl 'https://example:8443'
```

Flags: `-SkipIcons`, `-SkipPlugin`, `-SkipDefender`, `-ExeIcon`, `-RceditPath <path>`, `-IncludeCustom`, `-Profile <name>`.

`-ExeIcon` embeds `assets\icon.ico` into `DeepSeek Harness.exe` with `rcedit`, which is what the
shortcut, Explorer and Alt-Tab icons come from. It needs the application closed, backs the executable
up first, and restores it when `rcedit` fails. Only the shell caches icons: run `ie4uinit.exe -show`
or sign out to see the change.

## How the install directory is found

Nothing is hard-coded. The script enumerates every copy it can see and labels it:

| Source | What it contributes |
|---|---|
| `-InstallPath` | Skips detection entirely; validated by the presence of `DeepSeek Harness.exe` |
| This script's own folder (and two parents) | Covers the case where the script is dropped into the install tree |
| Uninstall registry (`HKCU`, `HKLM`, `WOW6432Node`) | Path **and** `DisplayVersion`; the only reliable version source |
| Running processes | Shows which copy is currently in use |
| `C:\Programs`, `C:\Program Files`, `C:\Program Files (x86)`, `%LOCALAPPDATA%\Programs` | Copies the registry does not know about (depth 2) |

Each candidate is reported as `version / custom / running / source / path`:

- `custom` — the copy already carries this kit (`resources\defender-exclusions.ps1` exists);
- `running` — a process of that copy is live, so its files cannot be replaced until it closes;
- a build-tree artifact (`win-unpacked`, `.desktop-build`, `\build\dsh\`) is flagged and never
  selected automatically.

The executable's own `ProductVersion` is **not** used: Electron drops the pre-release suffix, so both
`0.2.2-alpha.2` and `0.2.2-rc.1` report `0.2.2.0`. The uninstall entry keeps the real version.

Selection: one usable candidate is used directly; several are printed as a numbered table and the
script asks which one (or `A` for all). With no candidate at all, it asks for a path and validates it.
Stock copies are preferred; `-IncludeCustom` widens the choice to copies that are already customized.

## What it changes

| Target | Change |
|---|---|
| `<install>\resources\icon.png`, `tray.ico` | Replaced from `assets\` (originals kept as `*.bak-<timestamp>`) |
| Profile (`~/.dsh\profiles\<profile>`) | Installs the plugin when `dsh` is on `PATH`, then appends the seed entry if absent |
| Windows Security | Adds `<install>` and `~/.dsh` exclusions through one elevated step |

It never touches `app.asar` or the sealed runtime tree: those are integrity-checked, so rewriting
them breaks startup.

## What stays stock

The first-launch authorization dialog and the taskbar identity (AUMID) live in `app.asar` and are not
reproduced here. The exclusion script is run once from this tool instead of being offered at launch.
