#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

function collectArgs(name) {
  const values = [];
  for (let i = 0; i < process.argv.length; i += 1) {
    if (process.argv[i] === name && process.argv[i + 1]) {
      values.push(process.argv[i + 1]);
      i += 1;
    }
  }
  return values;
}

function arg(name) {
  const values = collectArgs(name);
  return values.length > 0 ? values[values.length - 1] : null;
}

function readRows(resultsPaths) {
  const rows = [];
  const warnings = [];
  for (const resultsPath of resultsPaths) {
    if (!fs.existsSync(resultsPath)) {
      warnings.push(`Missing results file: ${resultsPath}`);
      continue;
    }
    const lines = fs.readFileSync(resultsPath, 'utf8').split(/\r?\n/).filter(Boolean);
    for (let i = 0; i < lines.length; i += 1) {
      try {
        const row = JSON.parse(lines[i]);
        row.__sourceFile = resultsPath;
        row.__lineNumber = i + 1;
        rows.push(row);
      } catch (err) {
        warnings.push(`${resultsPath}:${i + 1}: invalid JSON (${err.message})`);
      }
    }
  }
  return { rows, warnings };
}

function normalizeResult(result) {
  return String(result || 'unknown').toLowerCase();
}

function classify(vals, crashSuspect) {
  if (crashSuspect) return 'CRASH_SUSPECT';
  const normalized = vals.map(normalizeResult);
  if (normalized.includes('lua_error')) return 'LUA_ERROR';
  if (normalized.includes('unsafe_disabled')) return 'UNSAFE_DISABLED';
  if (normalized.includes('skipped_context')) return 'SKIPPED_CONTEXT';
  if (normalized.includes('skipped_by_config')) return 'SKIPPED_BY_CONFIG';
  if (normalized.includes('ok')) return 'SAFE';
  if (normalized.includes('nil')) return 'RETURNS_NIL';
  return 'UNKNOWN';
}

function extractBreadcrumbOperation(line) {
  const match = line.match(/\[CrabRuntimeProbe\]\[breadcrumb\]\s+(.+?)\s+(enter|exit)\b/);
  if (!match) return null;
  return { operation: match[1], phase: match[2] };
}

function findCrashSuspect(logPath) {
  if (!logPath || !fs.existsSync(logPath)) return null;
  const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/);
  const open = [];
  for (const line of lines) {
    const crumb = extractBreadcrumbOperation(line);
    if (!crumb) continue;
    if (crumb.phase === 'enter') {
      open.push(crumb.operation);
    } else if (crumb.phase === 'exit') {
      for (let i = open.length - 1; i >= 0; i -= 1) {
        if (open[i] === crumb.operation) {
          open.splice(i, 1);
          break;
        }
      }
    }
  }
  return open.length > 0 ? open[open.length - 1] : null;
}

const resultsPaths = collectArgs('--results');
const logPath = arg('--ue4ss-log');

if (resultsPaths.length === 0) {
  console.error('Pass --results <path> at least once');
  process.exit(1);
}

const { rows, warnings } = readRows(resultsPaths);
if (rows.length === 0) {
  console.error('No valid result rows found.');
  for (const warning of warnings) console.error(warning);
  process.exit(1);
}

const byProbe = {};
for (const row of rows) {
  const probeId = row.probeId || 'unknown';
  byProbe[probeId] = byProbe[probeId] || {
    values: [],
    rows: 0,
    categories: new Set(),
    contexts: new Set(),
    modes: new Set(),
    lastTick: null
  };
  byProbe[probeId].values.push(row.result || 'unknown');
  byProbe[probeId].rows += 1;
  if (row.category) byProbe[probeId].categories.add(row.category);
  if (row.context) byProbe[probeId].contexts.add(row.context);
  if (row.mode) byProbe[probeId].modes.add(row.mode);
  if (row.tick !== undefined) byProbe[probeId].lastTick = row.tick;
}

const crashSuspect = findCrashSuspect(logPath);
const docs = path.join(process.cwd(), 'docs');
fs.mkdirSync(docs, { recursive: true });

let probeResults = '# Probe Results\n\n';
probeResults += 'Observe mode rows use `probeId = "Observe.Context"` and `category = "observe"`. They are passive context snapshots only: no curated registry probes, direct field reads, inventory array reads, health reads, RPCs, or gameplay state writes. Observe mode waits for `startupWarmupTicks`, then writes every `observeIntervalTicks`.\n\n';
probeResults += 'Active mode rows come from the curated probe registry after warmup, context stability, interval pacing, and safety gates.\n\n';
probeResults += `Result files read: ${resultsPaths.length}\n\n`;
if (warnings.length > 0) {
  probeResults += '## Warnings\n\n';
  probeResults += warnings.map((warning) => `- ${warning}`).join('\n') + '\n\n';
}
probeResults += '## Probe Status\n\n';
probeResults += '| Probe | Status | Rows | Modes | Categories | Contexts | Last tick |\n';
probeResults += '|---|---|---:|---|---|---|---:|\n';

let matrix = '# Safe Access Matrix\n\n';
matrix += '| Probe | Status | Runtime evidence |\n|---|---|---|\n';

for (const probe of Object.keys(byProbe).sort()) {
  const entry = byProbe[probe];
  const isCrash = crashSuspect === probe;
  const status = classify(entry.values, isCrash);
  const modes = Array.from(entry.modes).sort().join(', ');
  const categories = Array.from(entry.categories).sort().join(', ');
  const contexts = Array.from(entry.contexts).sort().join(', ');
  probeResults += `| \`${probe}\` | ${status} | ${entry.rows} | ${modes} | ${categories} | ${contexts} | ${entry.lastTick ?? ''} |\n`;
  matrix += `| \`${probe}\` | ${status} | ${entry.values.map(normalizeResult).join(', ')} |\n`;
}

let crash = '# Crash Phase Summary\n\n';
if (logPath) {
  crash += `UE4SS log: \`${logPath}\`\n\n`;
}
crash += crashSuspect
  ? `Last unmatched breadcrumb suggests: **${crashSuspect}**\n`
  : 'No crash suspect inferred from unmatched breadcrumbs.\n';

fs.writeFileSync(path.join(docs, 'PROBE_RESULTS.md'), probeResults);
fs.writeFileSync(path.join(docs, 'SAFE_ACCESS_MATRIX.md'), matrix);
fs.writeFileSync(path.join(docs, 'CRASH_PHASE_SUMMARY.md'), crash);
console.log('Summaries generated in docs/.');
