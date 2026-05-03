#!/usr/bin/env node
const { execSync } = require('child_process');
execSync('node tools/parse_objectdump.js', { stdio: 'inherit' });
if (require('fs').existsSync('objectdump/objectdump_index.json')) execSync('node tools/generate_probe_candidates.js', { stdio: 'inherit' });
console.log('Docs generation complete.');
