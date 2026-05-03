#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const idxPath = path.join(process.cwd(), 'objectdump', 'objectdump_index.json');
if (!fs.existsSync(idxPath)) {
  console.log('No object dump index found. Skipping probe candidate generation.');
  process.exit(0);
}
const idx = JSON.parse(fs.readFileSync(idxPath, 'utf8'));
const classes = Object.keys(idx.classes || {}).sort();
const mdPath = path.join(process.cwd(), 'docs', 'PROBE_CANDIDATES.md');
let md = '# Probe Candidates (Generated)\n\n';
md += 'Derived from object dump presence only; runtime safety unknown.\n';
md += 'This tool does not generate runtime Lua probes.\n\n';
classes.forEach(c => { md += `- ${c}\n`; });
fs.writeFileSync(mdPath, md);
console.log('Wrote', mdPath);
