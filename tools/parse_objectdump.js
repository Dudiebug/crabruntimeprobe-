#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const dir = path.join(root, 'objectdump');
const files = (fs.existsSync(dir) ? fs.readdirSync(dir) : []).filter(f => /\.(txt|md)$/.test(f) || f.includes('.part'));

const index = { generatedAt: new Date().toISOString(), files: [], classes: {}, structs: {} };
for (const file of files) {
  const full = path.join(dir, file);
  const lines = fs.readFileSync(full, 'utf8').split(/\r?\n/);
  const rec = { file, matches: [] };
  for (const line of lines) {
    let m = line.match(/\bclass\s+([A-Za-z0-9_]+)/i);
    if (m) { index.classes[m[1]] = index.classes[m[1]] || { properties: [], functions: [], raw: [] }; index.classes[m[1]].raw.push(line); rec.matches.push(line); }
    m = line.match(/\bstruct\s+([A-Za-z0-9_]+)/i);
    if (m) { index.structs[m[1]] = index.structs[m[1]] || { properties: [], raw: [] }; index.structs[m[1]].raw.push(line); rec.matches.push(line); }
  }
  index.files.push(rec);
}
fs.writeFileSync(path.join(dir, 'objectdump_index.json'), JSON.stringify(index, null, 2));

const md = ['# OBJECTDUMP_INDEX', '', `Generated: ${index.generatedAt}`, '', `Files scanned: ${index.files.length}`, '', `Classes: ${Object.keys(index.classes).length}`, `Structs: ${Object.keys(index.structs).length}`];
fs.writeFileSync(path.join(root, 'docs', 'OBJECTDUMP_INDEX.md'), md.join('\n'));
console.log('Wrote objectdump_index.json and docs/OBJECTDUMP_INDEX.md');
