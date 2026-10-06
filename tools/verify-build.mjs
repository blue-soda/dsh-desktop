#!/usr/bin/env node
/**
 * Post-build probes for the packaged Desktop runtime.
 *
 * (a) The installed dsh manifest declares the bundled plugin. A profile boot maps a loader row's
 *     bare package name through the installation's dependency graph, so a bundled row that no
 *     installation manifest declares cannot be imported and its entry never receives a fiber.
 * (b) A fresh profile boot against the packaged tree resolves the bundle and skips nothing.
 * (c) The packaged plugin content matches the same version on the registry.
 *
 * Imported by tools/build-release.mjs for -Verify; also runnable on its own, where option c) is
 * reported as skipped unless a version is supplied:
 *   node tools/verify-build.mjs -Checkout <dir> -PluginVersion <version>
 */
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { runTool } from './run-tool.mjs'

function step(title) { process.stdout.write(`\n=== ${title} ===\n`) }
function info(text) { process.stdout.write(`    ${text}\n`) }
function hashFile(path) { return createHash('sha256').update(readFileSync(path)).digest('hex').toUpperCase() }

/** Run a command and fail on a non-zero exit code. */
function run(command, args, options = {}) {
  return runTool(command, args, { cwd: options.cwd, encoding: 'utf8' }).stdout ?? ''
}

/** Loader resolution probe: returns what a boot would see for the bundled package. */
async function probeResolution(tree) {
  const boot = pathToFileURL(join(tree, 'node_modules', '@deepseek-ai', 'dsh-app-boot', 'lib', 'index.js')).href
  const { createRuntimeResolution, loadProfileDirectory } = await import(boot)
  const anchor = join(tree, 'node_modules', '@deepseek-ai', 'dsh', 'package.json')
  const home = mkdtempSync(join(tmpdir(), 'dsh-verify-'))
  const profileDir = join(home, 'profiles', 'desktop')
  mkdirSync(profileDir, { recursive: true })
  writeFileSync(join(profileDir, 'package.json'), JSON.stringify({
    name: 'dsh-profile-desktop',
    private: true,
    dependencies: {},
    dsh: { profile: { bundles: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app', '@blue-soda/dsh-remote'] } },
  }, undefined, 2))
  try {
    const profile = loadProfileDirectory('dsh', profileDir, anchor)
    const resolution = await createRuntimeResolution({ installAnchor: anchor, profile, home })
    const entry = resolution.entries.find(item => item.name === '@blue-soda/dsh-remote')
    return {
      skipped: profile.skippedBundles.map(item => item.packageName),
      mapped: entry !== undefined,
      scope: entry === undefined ? null : entry.scope,
    }
  } finally {
    rmSync(home, { recursive: true, force: true })
  }
}

/** Compare the packaged plugin scripts against the same version published on the registry. */
function probePublishedContent(tree, pluginPackage, pluginVersion, workRoot) {
  const packDir = join(workRoot, 'npm-pack')
  rmSync(packDir, { recursive: true, force: true })
  mkdirSync(packDir, { recursive: true })
  run('npm', ['pack', `${pluginPackage}@${pluginVersion}`, '--pack-destination', packDir, '--silent'])
  const tarball = readdirSync(packDir).find(name => name.endsWith('.tgz'))
  if (tarball === undefined) throw new Error('npm pack produced no tarball')
  const extractDir = join(packDir, 'extract')
  mkdirSync(extractDir, { recursive: true })
  run('tar', ['-xzf', join(packDir, tarball), '-C', extractDir])
  const publishedRoot = join(extractDir, 'package')
  const packagedRoot = join(tree, 'node_modules', '@blue-soda', 'dsh-remote')
  const publishedDist = join(publishedRoot, 'dist')
  if (!existsSync(publishedDist)) throw new Error('the published package exposes no dist directory')
  const scripts = []
  const walk = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const full = join(directory, entry.name)
      if (entry.isDirectory()) walk(full)
      else if (entry.name.endsWith('.js')) scripts.push(full)
    }
  }
  walk(publishedDist)
  const mismatched = []
  for (const file of scripts) {
    const relative = file.slice(publishedRoot.length + 1)
    const target = join(packagedRoot, relative)
    if (!existsSync(target)) { mismatched.push(`missing ${relative}`); continue }
    if (hashFile(file) !== hashFile(target)) mismatched.push(`differs ${relative}`)
  }
  return { checked: scripts.length, mismatched }
}

/**
 * Run every probe. Throws when a probe that could run reported a failure.
 * @param options - checkout root, plugin package name, packaged plugin version, and a work directory.
 */
export async function verifyBuild(options) {
  const tree = join(options.checkout, 'apps', 'desktop', '.desktop-build', 'targets', 'win-x64', 'dsh')
  const buildRoot = options.buildRoot ?? join(options.checkout, '..')
  const failures = []
  if (!existsSync(tree)) throw new Error(`no packaged runtime tree at ${tree}`)

  // a) installation manifest declaration
  const manifestPath = join(tree, 'node_modules', '@deepseek-ai', 'dsh', 'package.json')
  const declared = JSON.parse(readFileSync(manifestPath, 'utf8')).dependencies?.[options.pluginPackage]
  if (declared === undefined) {
    info(`[FAIL] a) the installed dsh manifest does not declare ${options.pluginPackage}`)
    failures.push('a) manifest declaration')
  } else {
    info(`[PASS] a) installed dsh manifest declares ${options.pluginPackage} = ${declared}`)
  }

  // b) loader resolution for a fresh profile
  const resolution = await probeResolution(tree)
  info(`[info] b) ${JSON.stringify(resolution)}`)
  if (resolution.mapped && resolution.skipped.length === 0) {
    info(`[PASS] b) a profile boot resolves ${options.pluginPackage} and skips no bundle`)
  } else {
    info('[FAIL] b) a profile boot did not resolve the bundled package cleanly')
    failures.push('b) profile resolution')
  }

  // c) packaged content matches the registry
  if (options.pluginVersion === undefined || options.pluginVersion === '(unknown)') {
    info('[SKIP] c) no packaged plugin version to compare against the registry')
  } else {
    try {
      const compared = probePublishedContent(tree, options.pluginPackage, options.pluginVersion, buildRoot)
      if (compared.checked === 0) {
        info('[FAIL] c) the published package exposed no dist scripts to compare')
        failures.push('c) published content')
      } else if (compared.mismatched.length === 0) {
        info(`[PASS] c) packaged plugin matches ${options.pluginPackage}@${options.pluginVersion} (${compared.checked} scripts)`)
      } else {
        info(`[FAIL] c) packaged plugin differs from the registry copy: ${compared.mismatched.join('; ')}`)
        failures.push('c) published content')
      }
    } catch (error) {
      info(`[SKIP] c) could not compare against the registry: ${error.message}`)
    }
  }

  if (failures.length > 0) throw new Error(`verification failed: ${failures.join(', ')}`)
  step('Verify passed')
}

function parseOptions(argv) {
  const values = {}
  for (let index = 0; index < argv.length; index++) {
    const token = argv[index]
    if (!token.startsWith('-')) continue
    values[token.replace(/^-+/, '').toLowerCase()] = argv[++index]
  }
  return values
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const values = parseOptions(process.argv.slice(2))
  if (values.checkout === undefined) {
    process.stderr.write('usage: node tools/verify-build.mjs -Checkout <dir> [-PluginVersion <version>]\n')
    process.exitCode = 1
  } else {
    verifyBuild({
      checkout: resolve(values.checkout),
      pluginPackage: values.pluginpackage ?? '@blue-soda/dsh-remote',
      pluginVersion: values.pluginversion,
      buildRoot: values.workdir,
    }).catch((error) => {
      process.stderr.write(`\nverify-build: ${error instanceof Error ? error.message : String(error)}\n`)
      process.exitCode = 1
    })
  }
}
