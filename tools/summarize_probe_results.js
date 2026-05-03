#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i > -1 ? process.argv[i + 1] : null;
}
const resultsPath = arg('--results');
const logPath = arg('--ue4ss-log');
if (!resultsPath || !fs.existsSync(resultsPath)) {
  console.error('Pass --results <path>'); process.exit(1);
}
const rows = fs.readFileSync(resultsPath, 'utf8').split(/\r?\n/).filter(Boolean).map(l => JSON.parse(l));
const byProbe = {};
for (const r of rows) byProbe[r.probeId] = byProbe[r.probeId] || [] , byProbe[r.probeId].push(r.result || 'unknown');
const classify = (vals) => vals.includes('ok') ? 'SAFE' : (vals[vals.length - 1] || 'UNKNOWN').toUpperCase();
let crashSuspect = null;
if (logPath && fs.existsSync(logPath)) {
  const log = fs.readFileSync(logPath, 'utf8').trim().split(/\r?\n/);
  const b = log.filter(l => l.includes('[CrabRuntimeProbe][breadcrumb]'));
  const last = b[b.length - 1] || '';
  if (last.includes(' enter')) crashSuspect = last.split('] ').pop().replace(' enter', '');
}

const docs = path.join(process.cwd(), 'docs');
let probeResults = '# Probe Results\n\n';
let matrix = '# Safe Access Matrix\n\n| Probe | Status |\n|---|---|\n';
for (const probe of Object.keys(byProbe).sort()) {
  const status = (crashSuspect === probe) ? 'CRASH_SUSPECT' : classify(byProbe[probe]);
  probeResults += `- ${probe}: ${status}\n`;
  matrix += `| ${probe} | ${status} |\n`;
}
let crash = '# Crash Phase Summary\n\n';
crash += crashSuspect ? `Last unmatched breadcrumb suggests: **${crashSuspect}**\n` : 'No crash suspect inferred.\n';
fs.writeFileSync(path.join(docs, 'PROBE_RESULTS.md'), probeResults);
fs.writeFileSync(path.join(docs, 'SAFE_ACCESS_MATRIX.md'), matrix);
fs.writeFileSync(path.join(docs, 'CRASH_PHASE_SUMMARY.md'), crash);
console.log('Summaries generated in docs/.');
