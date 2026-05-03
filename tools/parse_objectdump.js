#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const root = process.cwd();
const dir = path.join(root, 'objectdump');
const outJson = path.join(dir, 'objectdump_index.json');
const outMd = path.join(root, 'docs', 'OBJECTDUMP_INDEX.md');

const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => f !== 'README.md' && (/\.(txt|md)$/.test(f) || /\.part/.test(f))) : [];

if (files.length === 0) {
  console.log('No object dump files found. Skipping object dump index generation.');
  process.exit(0);
}

const idx = { files: [], classes: {}, structs: {} };

for (const file of files) {
  const full = path.join(dir, file);
  const lines = fs.readFileSync(full, 'utf8').split(/\r?\n/);
  idx.files.push(file);
  for (const line of lines) {
    const cls = line.match(/\bclass\s+([A-Za-z0-9_]+)/i);
    const str = line.match(/\bstruct\s+([A-Za-z0-9_]+)/i);
    const prop = line.match(/\b([A-Za-z0-9_]+)\s*:\s*([A-Za-z0-9_<>\[\]]+)/);
    const fn = line.match(/\b([A-Za-z0-9_]+)\s*\(.*\)/);
    if (cls) idx.classes[cls[1]] = idx.classes[cls[1]] || { properties: [], functions: [], raw: [] };
    if (str) idx.structs[str[1]] = idx.structs[str[1]] || { properties: [], raw: [] };
    if (cls) idx.classes[cls[1]].raw.push(line);
    if (str) idx.structs[str[1]].raw.push(line);
    if (prop && cls) idx.classes[cls[1]].properties.push({ name: prop[1], type: prop[2], raw: line });
    if (fn && cls) idx.classes[cls[1]].functions.push({ name: fn[1], raw: line });
  }
}

fs.writeFileSync(outJson, JSON.stringify(idx, null, 2));
let md = '# Object Dump Index\n\n';
md += `Files parsed: ${idx.files.length}\n\n`;
md += '## Classes\n\n';
for (const name of Object.keys(idx.classes).sort()) md += `- ${name}\n`;
md += '\n## Structs\n\n';
for (const name of Object.keys(idx.structs).sort()) md += `- ${name}\n`;
fs.writeFileSync(outMd, md);
console.log('Wrote', outJson, 'and', outMd);
