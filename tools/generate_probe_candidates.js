#!/usr/bin/env node
const fs = require('fs'); const path = require('path');
const p = path.join(process.cwd(),'objectdump/objectdump_index.json');
const idx = fs.existsSync(p) ? JSON.parse(fs.readFileSync(p,'utf8')) : {classes:{}};
const lines = ['# Probe Candidates','','Generated from objectdump index.'];
const lua = ['return {'];
for (const c of Object.keys(idx.classes||{})) { lines.push(`- ${c}`); lua.push(`  "FindFirstOf.${c}",`); }
lua.push('}');
fs.writeFileSync(path.join(process.cwd(),'docs/PROBE_CANDIDATES.md'), lines.join('\n'));
fs.writeFileSync(path.join(process.cwd(),'client/Mods/CrabRuntimeProbe/Scripts/generated_probe_candidates.lua'), lua.join('\n'));
