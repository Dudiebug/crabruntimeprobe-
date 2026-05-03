#!/usr/bin/env node
const fs = require('fs');
const args = process.argv.slice(2);
const arg = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : null; };
const resultsPath = arg('--results') || 'client/Mods/CrabRuntimeProbe/Scripts/results/probe_results.jsonl';
const logPath = arg('--ue4ss-log');
const rows = fs.existsSync(resultsPath) ? fs.readFileSync(resultsPath, 'utf8').split(/\r?\n/).filter(Boolean).map(l => { try { return JSON.parse(l);} catch {return null;} }).filter(Boolean) : [];
const map = new Map();
for (const r of rows) map.set(r.probeId, r.result);
let crash = 'UNKNOWN';
if (logPath && fs.existsSync(logPath)) {
  const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/).filter(Boolean);
  const before = lines.filter(l => l.includes('breadcrumb before')).slice(-1)[0] || '';
  const after = lines.filter(l => l.includes('breadcrumb after')).slice(-1)[0] || '';
  if (before && before !== after) crash = before.replace(/^.*breadcrumb before\s+/, '').trim();
}
const matrix = ['# Safe Access Matrix', '', '| Probe | Classification |', '|---|---|'];
for (const [k,v] of map.entries()) matrix.push(`| ${k} | ${String(v).toUpperCase()} |`);
if (crash !== 'UNKNOWN') matrix.push(`| ${crash} | CRASH_SUSPECT |`);
fs.writeFileSync('docs/SAFE_ACCESS_MATRIX.md', matrix.join('\n'));
fs.writeFileSync('docs/PROBE_RESULTS.md', `# Probe Results\n\nTotal results: ${rows.length}\n`);
fs.writeFileSync('docs/CRASH_PHASE_SUMMARY.md', `# Crash Phase Summary\n\nCrash suspect: ${crash}\n`);
