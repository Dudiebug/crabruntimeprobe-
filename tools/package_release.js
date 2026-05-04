#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const root = process.cwd();
const distDir = path.join(root, 'dist');
const defaultZip = path.join(distDir, 'CrabRuntimeProbe-ue4ss.zip');
const supportMods = ['BPML_GenericFunctions', 'BPModLoaderMod', 'Keybinds', 'shared'];
const rootRuntimeFiles = ['UE4SS.dll', 'dwmapi.dll', 'UE4SS-settings.ini', 'imgui.ini'];

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : null;
}

function hasFlag(name) {
  return process.argv.includes(name);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function ensureInside(parent, child) {
  const rel = path.relative(path.resolve(parent), path.resolve(child));
  if (rel.startsWith('..') || path.isAbsolute(rel)) {
    fail(`Refusing to operate outside ${parent}: ${child}`);
  }
}

function runCommand(command, args) {
  const result = spawnSync(command, args, {
    stdio: 'inherit'
  });
  if (result.error) fail(result.error.message);
  if (result.status !== 0) fail(`${command} failed with status ${result.status}`);
}

function copyFileIfExists(src, dest, required = true) {
  if (!fs.existsSync(src)) {
    if (required) fail(`Missing required template file: ${src}`);
    return false;
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
  return true;
}

function copyDir(src, dest) {
  if (!fs.existsSync(src)) fail(`Missing required template directory: ${src}`);
  fs.cpSync(src, dest, {
    recursive: true,
    filter: (source) => {
      const parts = path.relative(src, source).split(path.sep);
      const base = path.basename(source).toLowerCase();
      return !parts.includes('.git')
        && !parts.includes('node_modules')
        && !parts.includes('results')
        && !/\.(jsonl|log|dump|tmp)$/i.test(base);
    }
  });
}

function findTemplateRoot(inputPath) {
  const resolved = path.resolve(inputPath);
  if (fs.existsSync(path.join(resolved, 'client'))) return resolved;
  const children = fs.readdirSync(resolved, { withFileTypes: true }).filter((entry) => entry.isDirectory());
  for (const child of children) {
    const candidate = path.join(resolved, child.name);
    if (fs.existsSync(path.join(candidate, 'client'))) return candidate;
  }
  fail(`Could not find template root with a client/ directory under ${inputPath}`);
}

function extractTemplateIfNeeded(templatePath, workDir) {
  const resolved = path.resolve(templatePath);
  if (!fs.existsSync(resolved)) fail(`Template path does not exist: ${resolved}`);

  if (fs.statSync(resolved).isDirectory()) return findTemplateRoot(resolved);

  if (!/\.zip$/i.test(resolved)) fail('Template must be a directory or .zip file.');

  const extractDir = path.join(workDir, 'template');
  fs.mkdirSync(extractDir, { recursive: true });
  runCommand('tar', ['-xf', resolved, '-C', extractDir]);
  return findTemplateRoot(extractDir);
}

function writeModsTxt(modsDir) {
  const text = [
    'BPModLoaderMod : 1',
    'BPML_GenericFunctions : 1',
    'CrabRuntimeProbe : 1',
    '',
    '; Built-in keybinds, do not move up!',
    'Keybinds : 1',
    ''
  ].join('\n');
  fs.writeFileSync(path.join(modsDir, 'mods.txt'), text);
}

function writeInstallTxt(stagingDir) {
  const text = [
    'CrabRuntimeProbe UE4SS Bundle',
    '',
    'Extract ZIP contents into:',
    'Crab Champions\\CrabChampions\\Binaries\\Win64',
    '',
    'First run should use mode = observe.',
    '',
    'Deep inventory, InventoryInfo, health, write, and RPC probes are disabled by default.',
    '',
    'UE4SS is redistributed under UE4SS-LICENSE.txt.',
    '',
    'This package does not include Crab Champions game binaries.',
    '',
    'Included UE4SS support mods from the CrabInvSync template:',
    '- BPML_GenericFunctions',
    '- BPModLoaderMod',
    '- Keybinds',
    '- shared',
    '',
    'These support mods are UE4SS support files, not CrabRuntimeProbe gameplay code.',
    ''
  ].join('\n');
  fs.writeFileSync(path.join(stagingDir, 'INSTALL.txt'), text);
}

function verifyNoForbiddenFiles(stagingDir) {
  const forbidden = [
    'Mods/CrabInventorySync',
    'server',
    'objectdump',
    '.git',
    'node_modules',
    'UE4SS_ObjectDump.txt'
  ];
  const violations = [];

  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      const rel = path.relative(stagingDir, full).replace(/\\/g, '/');
      if (forbidden.some((item) => rel === item || rel.startsWith(`${item}/`) || rel.includes(`/${item}/`))) {
        violations.push(rel);
        continue;
      }
      if (entry.isDirectory()) walk(full);
    }
  }

  walk(stagingDir);
  if (violations.length > 0) fail(`Forbidden files would be packaged:\n${violations.join('\n')}`);
}

function listFiles(dir) {
  const out = [];
  function walk(current) {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const full = path.join(current, entry.name);
      const rel = path.relative(dir, full).replace(/\\/g, '/');
      if (entry.isDirectory()) walk(full);
      else out.push(rel);
    }
  }
  walk(dir);
  return out.sort();
}

function main() {
  const template = arg('--template') || arg('--template-zip') || arg('--template-dir');
  if (!template) {
    fail('Usage: node tools/package_release.js --template <CrabInvSync checkout dir or zip> [--out dist/CrabRuntimeProbe-ue4ss.zip] [--keep-staging]');
  }

  const outZip = path.resolve(arg('--out') || defaultZip);
  ensureInside(root, outZip);
  fs.mkdirSync(distDir, { recursive: true });
  fs.mkdirSync(path.dirname(outZip), { recursive: true });

  const workDir = path.join(distDir, 'package-work');
  const stagingDir = path.join(workDir, 'CrabRuntimeProbe-ue4ss');
  ensureInside(distDir, workDir);
  ensureInside(distDir, stagingDir);
  fs.rmSync(workDir, { recursive: true, force: true });
  fs.mkdirSync(stagingDir, { recursive: true });

  const templateRoot = extractTemplateIfNeeded(template, workDir);
  const templateClient = path.join(templateRoot, 'client');
  const sourceClient = path.join(root, 'client');
  const stagingMods = path.join(stagingDir, 'Mods');

  for (const file of rootRuntimeFiles) {
    const localSource = path.join(sourceClient, file);
    const templateSource = path.join(templateClient, file);
    copyFileIfExists(fs.existsSync(localSource) ? localSource : templateSource, path.join(stagingDir, file), file !== 'imgui.ini');
  }

  const localUe4ssLicense = path.join(root, 'UE4SS-LICENSE.txt');
  copyFileIfExists(fs.existsSync(localUe4ssLicense) ? localUe4ssLicense : path.join(templateRoot, 'UE4SS-LICENSE.txt'), path.join(stagingDir, 'UE4SS-LICENSE.txt'), true);
  copyFileIfExists(path.join(root, 'LICENSE'), path.join(stagingDir, 'CrabRuntimeProbe-LICENSE.txt'), true);
  copyFileIfExists(path.join(root, 'README.md'), path.join(stagingDir, 'CrabRuntimeProbe-README.md'), true);

  for (const modName of supportMods) {
    const localSupport = path.join(sourceClient, 'Mods', modName);
    copyDir(fs.existsSync(localSupport) ? localSupport : path.join(templateClient, 'Mods', modName), path.join(stagingMods, modName));
  }

  copyDir(path.join(root, 'client', 'Mods', 'CrabRuntimeProbe'), path.join(stagingMods, 'CrabRuntimeProbe'));
  writeModsTxt(stagingMods);
  writeInstallTxt(stagingDir);
  verifyNoForbiddenFiles(stagingDir);

  fs.rmSync(outZip, { force: true });
  runCommand('tar', ['-a', '-cf', outZip, '-C', stagingDir, '.']);

  const manifest = {
    generatedAt: new Date().toISOString(),
    template: path.resolve(template),
    output: outZip,
    installTarget: 'Crab Champions/CrabChampions/Binaries/Win64',
    files: listFiles(stagingDir)
  };
  fs.writeFileSync(path.join(distDir, 'CrabRuntimeProbe-ue4ss-manifest.json'), JSON.stringify(manifest, null, 2));

  if (!hasFlag('--keep-staging')) {
    fs.rmSync(workDir, { recursive: true, force: true });
  }

  console.log(`Wrote ${outZip}`);
  console.log('Extract ZIP contents into Crab Champions/CrabChampions/Binaries/Win64');
}

main();
