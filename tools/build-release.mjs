#!/usr/bin/env node
/**
 * Build the customized DeepSeek Harness Desktop installer from a pinned upstream commit.
 *
 * Everything happens inside this kit's own `build` directory: the upstream repository is cloned
 * there, reset to the base commit, the kit patch is applied, dependencies are installed, the
 * Windows x64 installer is packaged, and the artifacts land in `dist` with a checksum file and
 * generated release notes. No other checkout is written to.
 *
 * Invoked by `build-release.cmd`. Options are accepted as `-Tag`/`--tag` and are case-insensitive:
 *   -Tag <name>     release tag used by the notes and by -Upload (default r<timestamp>)
 *   -Upload         create the GitHub release for the tag (off by default)
 *   -Verify         run the post-build probes
 *   -Clean          delete build, dist, and leftover dsh-* temp entries, then exit
 *   -Source <url>   upstream git URL (default https://github.com/deepseek-ai/deepseek-harness.git)
 *   -Base <commit>  upstream commit the patch applies to (default 5badb15009)
 */
import { createHash } from 'node:crypto'
import {
  copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync,
} from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { captureTool, runTool, spawnTool } from './run-tool.mjs'
import { verifyBuild } from './verify-build.mjs'

const kitRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const buildRoot = join(kitRoot, 'build')
const checkout = join(buildRoot, 'dsh')
const distDir = join(kitRoot, 'dist')
const patchPath = join(kitRoot, 'dsh-desktop.patch')
const envTemplate = join(kitRoot, '.env.windows.template')
const notesTemplate = join(kitRoot, 'release-notes.template.md')
const releaseRepo = 'blue-soda/dsh-desktop'
const electronMirror = 'https://npmmirror.com/mirrors/electron/'
const pluginPackage = '@blue-soda/dsh-remote'
const desktopFilter = '@deepseek-ai/dsh-desktop'
const utf8 = 'utf8'

function step(title) { process.stdout.write(`\n=== ${title} ===\n`) }
function info(text) { process.stdout.write(`    ${text}\n`) }

/** Options arrive as `-Name value` or `-Flag`; normalize the leading dashes and case. */
function parseArguments(argv) {
  const values = {}
  for (let index = 0; index < argv.length; index++) {
    const token = argv[index]
    if (!token.startsWith('-')) continue
    const name = token.replace(/^-+/, '').toLowerCase()
    const next = argv[index + 1]
    if (next === undefined || next.startsWith('-')) values[name] = 'true'
    else { values[name] = next; index++ }
    if (values[name] === 'true' && name !== 'upload' && name !== 'verify' && name !== 'clean') values[name] = undefined
  }
  return values
}

/** Run a command with inherited stdio and fail the build on a non-zero exit code. */
function run(command, args, options = {}) {
  info(`> ${command} ${args.join(' ')}`)
  runTool(command, args, { cwd: options.cwd, env: options.env ?? process.env })
}

/** Run a command and capture trimmed stdout, failing on a non-zero exit code. */
function capture(command, args, options = {}) {
  return captureTool(command, args, { cwd: options.cwd })
}

function hashFile(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex').toUpperCase()
}

function timestampTag() {
  const now = new Date()
  const pad = (value) => String(value).padStart(2, '0')
  return `r${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}`
}

/** Refuse any destructive path that is not inside its expected parent. */
function guard(path, parent) {
  const full = resolve(path)
  if (full !== resolve(parent) && !full.startsWith(resolve(parent) + sep)) {
    throw new Error(`refusing to touch ${full}: outside ${resolve(parent)}`)
  }
  return full
}

function clean() {
  step('Clean')
  for (const path of [buildRoot, distDir]) {
    if (existsSync(path)) { rmSync(path, { recursive: true, force: true }); info(`removed ${path}`) }
  }
  // Only this kit's own temporary entries. A blanket dsh-* pattern would also delete unrelated
  // leftovers of the DSH test suite and of other sessions sharing the temporary directory.
  const owned = [/^dsh-verify-/, /^dsh-build-/, /^dsh-defender-exclusions\./]
  for (const entry of readdirSync(tmpdir())) {
    if (!owned.some(pattern => pattern.test(entry))) continue
    rmSync(join(tmpdir(), entry), { recursive: true, force: true })
    info(`removed ${join(tmpdir(), entry)}`)
  }
}

function preflight(tag) {
  step(`Preflight (tag ${tag})`)
  for (const command of ['git', 'node', 'pnpm', 'gh']) {
    const version = capture(command, ['--version']).split('\n')[0]
    info(`${command} ${version}`)
  }
  if (!existsSync(patchPath)) throw new Error(`missing ${patchPath}`)
  info(`patch: ${patchPath} (${statSync(patchPath).size} bytes)`)
}

function resolveCheckout(source, base) {
  step(`Isolated checkout at ${checkout}`)
  guard(checkout, buildRoot)
  if (!existsSync(join(checkout, '.git'))) {
    mkdirSync(buildRoot, { recursive: true })
    run('git', ['clone', '--no-checkout', '--filter=blob:none', source, checkout])
  } else {
    info('reusing the existing clone')
  }
  // A clone made from a local checkout already carries upstream history, and github.com is not
  // always reachable; a failed fetch is fatal only when the base commit is missing.
  const hasBase = spawnTool('git', ['-C', checkout, 'cat-file', '-e', `${base}^{commit}`], { stdio: 'ignore' }).status === 0
  try {
    run('git', ['-C', checkout, 'fetch', '--prune', 'origin'])
  } catch (error) {
    if (!hasBase) throw error
    info(`warning: could not fetch origin (${error.message}); continuing with the history that already has ${base}`)
  }
  run('git', ['-C', checkout, 'checkout', '--force', base])
  run('git', ['-C', checkout, 'clean', '-fdx', 'apps/desktop/resources', 'apps/desktop/src'])
  run('git', ['-C', checkout, 'apply', '--binary', '--check', patchPath])
  run('git', ['-C', checkout, 'apply', '--binary', patchPath])
  info(`source state: ${capture('git', ['-C', checkout, 'rev-parse', '--short', 'HEAD'])} + dsh-desktop.patch`)
}

function writeEnvFile() {
  step('Packaging environment')
  const target = join(checkout, 'apps', 'desktop', '.env.windows')
  copyFileSync(envTemplate, target)
  info(`wrote ${target}`)
  for (const line of readFileSync(target, utf8).split('\n')) if (/^[A-Z]/.test(line)) info(`  ${line.trim()}`)
}

function build() {
  step('Install dependencies and package (the long step)')
  const environment = { ...process.env, ELECTRON_MIRROR: electronMirror }
  info(`ELECTRON_MIRROR=${electronMirror}`)
  try {
    run('pnpm', ['install'], { cwd: checkout, env: environment })
  } catch (error) {
    throw new Error(`pnpm install failed. A slow or blocked registry is the usual cause: uncomment `
      + `DSH_DESKTOP_NPM_REGISTRY in .env.windows.template (for example https://registry.npmmirror.com) and re-run. ${error.message}`)
  }
  try {
    run('pnpm', ['--filter', desktopFilter, 'run', 'package:win:x64:unsigned'], { cwd: checkout, env: environment })
  } catch (error) {
    throw new Error(`packaging failed. When the log shows 'download:electron ... fetch failed' the GitHub release CDN `
      + `is unreachable; ELECTRON_MIRROR was already set to ${electronMirror}, so retry once the network settles. ${error.message}`)
  }
}

function exportArtifacts() {
  step('Collect artifacts')
  const artifacts = join(checkout, 'apps', 'desktop', '.desktop-build', 'targets', 'win-x64', 'unsigned-artifacts')
  if (!existsSync(artifacts)) throw new Error(`no artifact directory at ${artifacts}`)
  const installers = readdirSync(artifacts).filter(name => name.endsWith('.exe'))
  if (installers.length === 0) throw new Error(`no installer found in ${artifacts}`)
  const name = installers
    .map(entry => ({ entry, time: statSync(join(artifacts, entry)).mtimeMs }))
    .sort((left, right) => right.time - left.time)[0].entry
  mkdirSync(distDir, { recursive: true })
  const installerPath = join(distDir, name)
  const blockmapName = `${name}.blockmap`
  const blockmapPath = join(distDir, blockmapName)
  copyFileSync(join(artifacts, name), installerPath)
  copyFileSync(join(artifacts, blockmapName), blockmapPath)
  const sha256 = hashFile(installerPath)
  const blockmapSha256 = hashFile(blockmapPath)
  const sumsPath = join(distDir, 'SHA256SUMS.txt')
  writeFileSync(sumsPath, `${sha256}  ${name}\n${blockmapSha256}  ${blockmapName}\n`, 'ascii')
  const manifestPath = join(checkout, 'apps', 'desktop', '.desktop-build', 'targets', 'win-x64', 'dsh',
    'node_modules', '@blue-soda', 'dsh-remote', 'package.json')
  const pluginVersion = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, utf8)).version : '(unknown)'
  info(`installer : ${installerPath} (${(statSync(installerPath).size / 1048576).toFixed(1)} MB)`)
  info(`sha256    : ${sha256}`)
  info(`blockmap  : ${blockmapSha256}`)
  info(`plugin    : ${pluginPackage}@${pluginVersion}`)
  return { name, installerPath, blockmapPath, sumsPath, sha256, blockmapSha256, pluginVersion }
}

function writeNotes(tag, base, artifact) {
  step('Release notes')
  let text = readFileSync(notesTemplate, utf8)
  const replacements = {
    '{{TAG}}': tag,
    '{{BUILD_DATE}}': new Date().toISOString().slice(0, 16).replace('T', ' '),
    '{{BASE}}': base,
    '{{EXE_NAME}}': artifact.name,
    '{{SIZE_MB}}': (statSync(artifact.installerPath).size / 1048576).toFixed(1),
    '{{SHA256}}': artifact.sha256,
    '{{BLOCKMAP_SHA256}}': artifact.blockmapSha256,
    '{{PLUGIN_VERSION}}': artifact.pluginVersion,
  }
  for (const [token, value] of Object.entries(replacements)) text = text.replaceAll(token, value)
  const leftover = /\{\{[A-Z_]+\}\}/.exec(text)
  if (leftover !== null) throw new Error(`unreplaced placeholder in the generated notes: ${leftover[0]}`)
  const notesPath = join(distDir, `RELEASE-NOTES-${tag}.md`)
  writeFileSync(notesPath, text, utf8)
  info(`wrote ${notesPath}`)
  return notesPath
}

function upload(tag, artifact, notesPath) {
  step(`Upload release ${tag}`)
  const title = `DeepSeek Harness Desktop 定制版 0.2.1-alpha.1（${tag}，内置插件 ${artifact.pluginVersion}）`
  run('gh', ['release', 'create', tag, '-R', releaseRepo, '--title', title, '--notes-file', notesPath,
    artifact.installerPath, artifact.blockmapPath, artifact.sumsPath])
  info(`https://github.com/${releaseRepo}/releases/tag/${tag}`)
}

async function main() {
  const options = parseArguments(process.argv.slice(2))
  if (options.clean === 'true') { clean(); return }

  const tag = options.tag ?? timestampTag()
  const base = options.base ?? '5badb15009'
  const source = options.source ?? 'https://github.com/deepseek-ai/deepseek-harness.git'

  preflight(tag)
  resolveCheckout(source, base)
  writeEnvFile()
  build()
  const artifact = exportArtifacts()
  const notesPath = writeNotes(tag, base, artifact)
  if (options.verify === 'true') {
    await verifyBuild({ checkout, pluginPackage, pluginVersion: artifact.pluginVersion, buildRoot })
  }
  if (options.upload === 'true') upload(tag, artifact, notesPath)

  step('Done')
  info(`tag        : ${tag}`)
  info(`installer  : ${artifact.installerPath}`)
  info(`sha256     : ${artifact.sha256}`)
  info(`plugin     : ${pluginPackage}@${artifact.pluginVersion}`)
  info(`notes      : ${notesPath}`)
  if (options.upload !== 'true') info(`publish with: build-release.cmd -Tag ${tag} -Upload`)
}

main().catch((error) => {
  process.stderr.write(`\nbuild-release: ${error instanceof Error ? error.message : String(error)}\n`)
  process.exitCode = 1
})
