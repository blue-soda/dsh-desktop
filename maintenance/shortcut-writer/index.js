// Write the DSH development shortcuts with an application identifier, using Electron's own
// shell.writeShortcutLink — the same implementation installers rely on.
//
// Driven by maintenance/set-taskbar-identity.ps1, which passes environment variables and
// reads result.json. A GUI Electron process does not attach to the parent console, so the
// outcome is written to result.json rather than stdout.
const { app, shell } = require('electron')
const fs = require('node:fs')
const path = require('node:path')
const os = require('node:os')

const appUserModelId = process.env.DSH_SHORTCUT_AUMID ?? 'com.deepseek.harness.dev'
const shortcutName = process.env.DSH_SHORTCUT_NAME ?? 'DeepSeek Harness Desktop'
const repo = process.env.DSH_SHORTCUT_REPO ?? 'C:\\Workspace\\deepseek-harness'
const home = os.homedir()

const options = {
  target: path.join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'wscript.exe'),
  args: `"${path.join(home, 'bin', 'dsh-desktop.vbs')}"`,
  cwd: repo,
  description: 'DeepSeek Harness Desktop (development build)',
  icon: path.join(home, 'bin', 'dsh-desktop.ico'),
  iconIndex: 0,
  appUserModelId,
}

app.whenReady().then(() => {
  const destinations = [
    path.join(home, 'Desktop'),
    path.join(process.env.APPDATA, 'Microsoft', 'Windows', 'Start Menu', 'Programs'),
  ]
  const results = destinations.map((directory) => {
    const file = path.join(directory, `${shortcutName}.lnk`)
    const updated = shell.writeShortcutLink(file, 'update', options)
    const written = updated || shell.writeShortcutLink(file, 'create', options)
    return { file, updated, written, exists: fs.existsSync(file) }
  })
  fs.writeFileSync(path.join(__dirname, 'result.json'), JSON.stringify({
    appUserModelId, shortcutName, options, results,
  }, undefined, 2))
  app.exit(results.every((entry) => entry.written) ? 0 : 1)
})
