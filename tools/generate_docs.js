#!/usr/bin/env node
const { spawnSync } = require('child_process');
const path = require('path');

function run(script) {
  const scriptPath = path.join('tools', script);
  console.log(`Running ${scriptPath}...`);
  const result = spawnSync(process.execPath, [scriptPath], { stdio: 'inherit' });
  if (result.error) {
    console.error(`${scriptPath} failed: ${result.error.message}`);
    process.exit(1);
  }
  if (result.status !== 0) {
    console.error(`${scriptPath} exited with status ${result.status}`);
    process.exit(result.status || 1);
  }
}

run('parse_objectdump.js');
run('generate_probe_candidates.js');
console.log('Docs generation complete.');
