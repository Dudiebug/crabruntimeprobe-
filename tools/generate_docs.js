#!/usr/bin/env node
const { spawnSync } = require('child_process');
const path = require('path');
const root = path.resolve(__dirname, '..');
spawnSync(process.execPath, [path.join(root, 'tools/parse_objectdump.js')], { stdio: 'inherit' });
spawnSync(process.execPath, [path.join(root, 'tools/generate_probe_candidates.js')], { stdio: 'inherit' });
console.log('Docs generation complete (result summaries require explicit --results).');
