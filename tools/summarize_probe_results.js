#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const getArg = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i+1] : null; };
const resultsPath = getArg('--results');
const logPath = getArg('--ue4ss-log');
let rows = [];
if (resultsPath && fs.existsSync(resultsPath)) {
  rows = fs.readFileSync(resultsPath, 'utf8').split(/\r?\n/).filter(Boolean).map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
}
const byProbe = new Map();
for (const r of rows) {
  if (!byProbe.has(r.probeId)) byProbe.set(r.probeId, new Set());
  byProbe.get(r.probeId).add((r.result || 'UNKNOWN').toUpperCase());
}
let crashSuspect = '';
if (logPath && fs.existsSync(logPath)) {
  const log = fs.readFileSync(logPath, 'utf8').trim().split(/\r?\n/);
  const crumbs = log.filter(l => l.includes('[CrabRuntimeProbe] breadcrumb:'));
  const last = crumbs[crumbs.length - 1] || '';
  if (last.includes(' enter')) crashSuspect = last.split('breadcrumb: ')[1];
}
const safe = ['# SAFE_ACCESS_MATRIX', '', '| Probe | Classification |', '|---|---|'];
for (const [probe, set] of byProbe.entries()) safe.push(`| ${probe} | ${Array.from(set).join(',')} |`);
if (crashSuspect) safe.push(`| ${crashSuspect} | CRASH_SUSPECT |`);
fs.writeFileSync(path.join(root, 'docs', 'SAFE_ACCESS_MATRIX.md'), safe.join('\n'));
fs.writeFileSync(path.join(root, 'docs', 'PROBE_RESULTS.md'), '# PROBE_RESULTS\n\nRows: ' + rows.length + '\n');
fs.writeFileSync(path.join(root, 'docs', 'CRASH_PHASE_SUMMARY.md'), '# CRASH_PHASE_SUMMARY\n\n' + (crashSuspect || 'No crash suspect inferred.') + '\n');
console.log('Wrote summaries');
