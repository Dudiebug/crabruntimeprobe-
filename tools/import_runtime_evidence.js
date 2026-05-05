#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const FORBIDDEN = [
  /C:\\Users\\/i,
  /C:\\\\Users\\\\/i,
  /private key/i,
  /token/i,
  /password/i,
  /UE4Minidump/i,
  /CrashContext\.runtime-xml/i
];

function arg(name) {
  const idx = process.argv.indexOf(name);
  return idx >= 0 ? process.argv[idx + 1] : null;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function walk(dir) {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full));
    else out.push(full);
  }
  return out;
}

function sessionIdFromName(file) {
  const base = path.basename(file);
  let match = base.match(/^probe_results_(.+)\.jsonl$/);
  if (match) return match[1];
  match = base.match(/^access_evidence_(.+)\.jsonl$/);
  if (match) return match[1];
  match = base.match(/^session_manifest_(.+)\.json$/);
  if (match) return match[1];
  return null;
}

function destinationName(file) {
  const base = path.basename(file);
  if (/^probe_results_.*\.jsonl$/.test(base)) return 'probe_results.jsonl';
  if (/^access_evidence_.*\.jsonl$/.test(base)) return 'access_evidence.jsonl';
  if (/^session_manifest_.*\.json$/.test(base)) return 'session_manifest.json';
  if (base === 'diagnostic_summary.txt') return 'diagnostic_summary.txt';
  return null;
}

function assertImportable(file) {
  const base = path.basename(file);
  if (/\.(dmp|mdmp)$/i.test(base)) fail(`Refusing to import crash dump: ${file}`);
  if (/CrashContext\.runtime-xml/i.test(base)) fail(`Refusing to import crash XML: ${file}`);
  let text = fs.readFileSync(file, 'utf8');
  if (base === 'diagnostic_summary.txt') {
    text = text.replace(/[A-Z]:\\Users\\[^\r\n]+/gi, '<REDACTED_LOCAL_PATH>');
    text = text.replace(/[A-Z]:\\(?!Users\\)[^\r\n]+/gi, '<REDACTED_LOCAL_PATH>');
  }
  for (const pattern of FORBIDDEN) {
    if (pattern.test(text)) {
      fail(`Refusing to import forbidden or unredacted sensitive content from ${file}: ${pattern}`);
    }
  }
  return text.replace(/[A-Z]:\\(?!Users\\)[^\r\n"]+/g, '<REDACTED_LOCAL_PATH>');
}

function normalizeManifestText(text) {
  try {
    const manifest = JSON.parse(text);
    const gates = manifest.safetyGates || {};
    const active = Object.keys(gates).filter((key) => gates[key] === true);
    manifest.activeResearchGates = active;
    manifest.warning = active.length > 0 ? `research gates enabled: ${active.join(', ')}` : '';
    return JSON.stringify(manifest);
  } catch {
    return text;
  }
}

const fromArg = arg('--from');
if (!fromArg) fail('Usage: node tools/import_runtime_evidence.js --from "<path to Mods/CrabRuntimeProbe/Scripts/results>"');

const fromDir = path.resolve(fromArg);
if (!fs.existsSync(fromDir) || !fs.statSync(fromDir).isDirectory()) {
  fail(`Input directory does not exist: ${fromDir}`);
}

const candidateDirs = [fromDir];
const parent = path.dirname(fromDir);
if (path.basename(fromDir).toLowerCase() === 'results') candidateDirs.push(parent);

const files = [];
for (const dir of candidateDirs) {
  for (const file of walk(dir)) {
    const base = path.basename(file);
    if (
      /^probe_results_.*\.jsonl$/.test(base) ||
      /^access_evidence_.*\.jsonl$/.test(base) ||
      /^session_manifest_.*\.json$/.test(base) ||
      base === 'diagnostic_summary.txt' ||
      /\.(dmp|mdmp)$/i.test(base) ||
      /CrashContext\.runtime-xml/i.test(base)
    ) {
      files.push(file);
    }
  }
}
const uniqueFiles = Array.from(new Set(files));

for (const file of uniqueFiles) {
  const base = path.basename(file);
  if (/\.(dmp|mdmp)$/i.test(base) || /CrashContext\.runtime-xml/i.test(base)) {
    assertImportable(file);
  }
}

const sessions = new Map();
for (const file of uniqueFiles) {
  const sessionId = sessionIdFromName(file);
  if (!sessionId) continue;
  if (!sessions.has(sessionId)) sessions.set(sessionId, []);
  sessions.get(sessionId).push(file);
}

const diagnostic = uniqueFiles.find((file) => path.basename(file) === 'diagnostic_summary.txt');
if (diagnostic) {
  for (const list of sessions.values()) list.push(diagnostic);
}

const outRoot = path.join(process.cwd(), 'evidence', 'runtime');
fs.mkdirSync(outRoot, { recursive: true });

for (const [sessionId, sessionFiles] of sessions.entries()) {
  const sessionDir = path.join(outRoot, sessionId);
  fs.mkdirSync(sessionDir, { recursive: true });
  for (const file of sessionFiles) {
    const destName = destinationName(file);
    if (!destName) continue;
    let text = assertImportable(file);
    if (destName === 'session_manifest.json') {
      text = normalizeManifestText(text);
    }
    fs.writeFileSync(path.join(sessionDir, destName), text);
  }
}

console.log(`imported evidence sessions = ${sessions.size}`);
