#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const idxPath = path.join(root, 'objectdump', 'objectdump_index.json');
let idx = { classes: {} };
if (fs.existsSync(idxPath)) idx = JSON.parse(fs.readFileSync(idxPath, 'utf8'));
const classes = Object.keys(idx.classes || {}).sort();
const md = ['# PROBE_CANDIDATES', '', 'Auto-generated candidates from object dump:', ''];
classes.forEach(c => md.push(`- ${c}`));
fs.writeFileSync(path.join(root, 'docs', 'PROBE_CANDIDATES.md'), md.join('\n'));

const lua = ['-- generated; do not manually curate here', 'return {'];
classes.slice(0, 200).forEach(c => lua.push(`  "FindFirstOf.${c}",`));
lua.push('}');
fs.writeFileSync(path.join(root, 'client/Mods/CrabRuntimeProbe/Scripts/generated_probe_candidates.lua'), lua.join('\n'));
console.log('Generated probe candidates');
