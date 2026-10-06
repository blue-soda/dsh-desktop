#!/usr/bin/env node
/**
 * External-command helpers for Windows.
 *
 * Node cannot start a `.cmd` or `.bat` shim directly: `spawnSync('pnpm', ...)` fails with ENOENT
 * even though `pnpm` is on PATH, because the shim is `pnpm.cmd`. These helpers resolve a command
 * through PATH and PATHEXT, run batch shims through `cmd.exe /d /s /c`, and run real executables
 * directly with `shell: false` so arguments with spaces stay intact.
 */
import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { delimiter, join } from 'node:path'

const pathExtensions = (process.env.PATHEXT ?? '.COM;.EXE;.BAT;.CMD').split(';').filter(Boolean)

/**
 * Resolve a command name to an executable path through PATH and PATHEXT.
 * @param command - Command name, or a path that is used as given.
 * @returns The resolved absolute path, or undefined when nothing matches.
 */
export function resolveCommand(command) {
  if (command.includes('/') || command.includes('\\')) return command
  for (const directory of (process.env.PATH ?? '').split(delimiter)) {
    if (directory === '') continue
    for (const extension of pathExtensions) {
      const candidate = join(directory, command + extension)
      if (existsSync(candidate)) return candidate
    }
  }
  return undefined
}

/** Quote one argument for the `cmd.exe` command line. */
function quoteForCmd(value) {
  if (value !== '' && !/[\s"&|<>^()%!]/.test(value)) return value
  return `"${value.replace(/"/g, '""')}"`
}

/**
 * Start a command, routing batch shims through cmd.exe.
 * @param command - Command name or path.
 * @param args - Argument list, passed without shell interpretation for real executables.
 * @param options - spawnSync options; `stdio` defaults to 'inherit'.
 * @returns The spawnSync result.
 */
export function spawnTool(command, args, options = {}) {
  const resolved = resolveCommand(command) ?? command
  const settings = { stdio: 'inherit', ...options }
  if (/\.(cmd|bat)$/iu.test(resolved)) {
    // cmd.exe wants one command string: /d /s /c "<line>". windowsVerbatimArguments keeps Node from
    // re-quoting that argument, which would reach cmd.exe as \"...\" and fail to run.
    const line = [resolved, ...args].map(quoteForCmd).join(' ')
    return spawnSync(process.env.ComSpec ?? 'cmd.exe', ['/d', '/s', '/c', `"${line}"`],
      { ...settings, windowsVerbatimArguments: true })
  }
  return spawnSync(resolved, args, settings)
}

/**
 * Run a command with inherited stdio and throw when it fails.
 * @param command - Command name or path.
 * @param args - Argument list.
 * @param options - spawnSync options.
 */
export function runTool(command, args, options = {}) {
  const result = spawnTool(command, args, options)
  if (result.error) throw new Error(`${command} could not start: ${result.error.message}`)
  if (result.status !== 0) throw new Error(`${command} ${args[0] ?? ''} exited with ${result.status}`)
  return result
}

/**
 * Run a command and capture trimmed stdout, throwing when it fails.
 * @param command - Command name or path.
 * @param args - Argument list.
 * @param options - spawnSync options.
 * @returns Trimmed stdout.
 */
export function captureTool(command, args, options = {}) {
  const result = spawnTool(command, args, { stdio: 'pipe', encoding: 'utf8', ...options })
  if (result.error) throw new Error(`${command} could not start: ${result.error.message}`)
  if (result.status !== 0) {
    throw new Error(`${command} ${args[0] ?? ''} exited with ${result.status}: ${String(result.stderr).trim()}`)
  }
  return String(result.stdout).trim()
}
