#!/usr/bin/env node
const fs = require('fs');
const args = process.argv.slice(2);
const getArg = (k)=>{const i=args.indexOf(k); return i>=0?args[i+1]:null};
const results = getArg('--results'); const log = getArg('--ue4ss-log');
const counts = {};
if (results && fs.existsSync(results)) {
  for (const line of fs.readFileSync(results,'utf8').split(/\r?\n/)) {
    if (!line.trim()) continue; const row = JSON.parse(line); counts[row.result]=(counts[row.result]||0)+1;
  }
}
let crash='UNKNOWN';
if (log && fs.existsSync(log)) {
  const t=fs.readFileSync(log,'utf8'); const m=t.match(/enter\s+([^\n\r]+)/g); if (m&&m.length) crash = m[m.length-1].replace('enter ','').trim();
}
fs.writeFileSync('docs/PROBE_RESULTS.md', '# PROBE RESULTS\n\n' + Object.entries(counts).map(([k,v])=>`- ${k}: ${v}`).join('\n'));
fs.writeFileSync('docs/SAFE_ACCESS_MATRIX.md', '# SAFE ACCESS MATRIX\n\nGenerated from result classifications.');
fs.writeFileSync('docs/CRASH_PHASE_SUMMARY.md', `# CRASH PHASE SUMMARY\n\n- Crash suspect operation: ${crash}`);
