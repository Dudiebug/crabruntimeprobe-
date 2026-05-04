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

function fail(message) {
  console.error(message);
  process.exit(1);
}

function read(file) {
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
}

function safeWrite(file, text) {
  for (const pattern of FORBIDDEN) {
    if (pattern.test(text)) fail(`Forbidden string found while building wiki ${file}: ${pattern}`);
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
}

const repo = process.cwd();
const wikiSrc = path.join(repo, 'wiki-src');
const outDir = path.join(repo, 'dist', 'wiki');
fs.mkdirSync(outDir, { recursive: true });

const generatedNotice = '> Generated from repo docs. Do not edit staged wiki files directly.\n\n';
const pages = [
  ['Home.md', ['RUNTIME_EVIDENCE_INDEX.md']],
  ['Safe-Access-Matrix.md', ['SAFE_ACCESS_MATRIX.md', 'SYMBOL_ACCESS_REFERENCE.md']],
  ['How-To-Read-Runtime-Evidence.md', ['RUNTIME_EVIDENCE_INDEX.md', 'UNTESTED_ACCESS_PATHS.md']],
  ['Known-Unsafe-Paths.md', ['KNOWN_UNSAFE_PATHS.md', 'UNTESTED_ACCESS_PATHS.md']],
  ['CrabInvSync-v2-Design-Notes.md', ['SAFE_ACCESS_MATRIX.md']]
];

for (const [page, docNames] of pages) {
  let text = generatedNotice + read(path.join(wikiSrc, page)).trim() + '\n\n';
  for (const docName of docNames) {
    const docText = read(path.join(repo, 'docs', docName)).trim();
    if (docText) {
      text += `\n\n---\n\n${docText}\n`;
    }
  }
  safeWrite(path.join(outDir, page), text);
}

console.log(`wiki staged at ${path.join('dist', 'wiki')}`);
