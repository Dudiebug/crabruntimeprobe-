#!/usr/bin/env node
const fs = require('fs');
const idxPath = 'objectdump/objectdump_index.json';
if (!fs.existsSync(idxPath)) {
  console.error('missing objectdump index');
  process.exit(1);
}
const idx = JSON.parse(fs.readFileSync(idxPath, 'utf8'));
const classes = idx.classes.filter(c => /Crab|Inventory|Health|Weapon|Ability|Melee/i.test(c)).slice(0, 200);
const md = ['# Probe Candidates', '', 'Generated from object dump index.', ''];
const lua = ['return {'];
for (const c of classes) {
  md.push(`- ${c}`);
  lua.push(`  { className = ${JSON.stringify(c)} },`);
}
lua.push('}');
fs.writeFileSync('docs/PROBE_CANDIDATES.md', md.join('\n'));
fs.writeFileSync('client/Mods/CrabRuntimeProbe/Scripts/generated_probe_candidates.lua', lua.join('\n'));
