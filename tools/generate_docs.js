#!/usr/bin/env node
const { execSync } = require('child_process');

execSync('node tools/parse_objectdump.js', { stdio: 'inherit' });
try { execSync('node tools/generate_probe_candidates.js', { stdio: 'inherit' }); } catch (_) {}
console.log('Docs generation complete.');
