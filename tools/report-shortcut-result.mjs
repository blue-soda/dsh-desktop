#!/usr/bin/env node
/**
 * Print the outcome recorded by maintenance/shortcut-writer.
 *
 * The writer is an Electron application, which does not attach to the parent console on Windows,
 * so it reports through result.json instead of stdout.
 *
 *   node tools/report-shortcut-result.mjs <path to result.json>
 */
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const target = process.argv[2]
if (target === undefined) {
  process.stderr.write('usage: node tools/report-shortcut-result.mjs <result.json>\n')
  process.exitCode = 1
} else {
  try {
    const result = JSON.parse(readFileSync(resolve(target), 'utf8'))
    let failures = 0
    for (const entry of result.results ?? []) {
      const state = entry.written === true ? 'OK  ' : 'FAIL'
      if (entry.written !== true) failures++
      process.stdout.write(`  ${state} ${entry.file}\n`)
    }
    process.stdout.write(`  AppUserModelID = ${result.appUserModelId ?? '(unknown)'}\n`)
    if (failures > 0) process.exitCode = 1
    else process.stdout.write('  Next: unpin the old taskbar entry, restart the app, then pin again.\n')
  } catch (error) {
    process.stderr.write(`report-shortcut-result: ${error instanceof Error ? error.message : String(error)}\n`)
    process.exitCode = 1
  }
}
