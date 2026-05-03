#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const idxPath = path.join(process.cwd(), 'objectdump', 'objectdump_index.json');
if (!fs.existsSync(idxPath)) {
  console.error('Missing objectdump_index.json; run parse_objectdump first');
  process.exit(1);
}
const idx = JSON.parse(fs.readFileSync(idxPath, 'utf8'));
const classes = Object.keys(idx.classes || {}).sort();
const mdPath = path.join(process.cwd(), 'docs', 'PROBE_CANDIDATES.md');
const luaPath = path.join(process.cwd(), 'client/Mods/CrabRuntimeProbe/Scripts/generated_probe_candidates.lua');
let md = '# Probe Candidates (Generated)\n\n';
md += 'Derived from object dump presence only; runtime safety unknown.\n\n';
classes.forEach(c => { md += `- ${c}\n`; });
fs.writeFileSync(mdPath, md);
const lua = 'return ' + JSON.stringify(classes, null, 2).replace(/"/g, "'") + '\n';
fs.writeFileSync(luaPath, lua);
console.log('Wrote', mdPath, 'and', luaPath);
