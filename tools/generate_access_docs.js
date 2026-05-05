#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { parseIdentityFromFullName, extractFullNameFromSummary } = require('./identity_helpers');

function walk(dir, name) {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full, name));
    else if (!name || entry.name === name) out.push(full);
  }
  return out;
}

function readJsonl(file) {
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(Boolean).map((line, idx) => {
    try {
      const row = JSON.parse(line);
      row.__file = file;
      row.__line = idx + 1;
      return row;
    } catch {
      return null;
    }
  }).filter(Boolean);
}

function readObjectdumpSymbols() {
  const file = path.join(process.cwd(), 'objectdump', 'objectdump_index.json');
  if (!fs.existsSync(file)) return new Set();
  try {
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    const text = JSON.stringify(data);
    return new Set(Array.from(text.matchAll(/\bCrab[A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)?\b/g)).map((m) => m[0]));
  } catch {
    return new Set();
  }
}

function statusRank(status) {
  return {
    SAFE: 6,
    RETURNS_NIL: 5,
    LUA_ERROR: 4,
    UNSAFE_DISABLED: 3,
    SKIPPED_CONTEXT: 2,
    SKIPPED_BY_CONFIG: 1,
    UNTESTED: 0
  }[status] ?? 0;
}

function bestStatus(values) {
  if (values.includes('SAFE')) return 'SAFE';
  return values.sort((a, b) => statusRank(b) - statusRank(a))[0] || 'UNTESTED';
}

function md(value) {
  const s = String(value ?? '');
  return s.replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
}

function classifyHealthSource(row, sessionCrabHcFullName) {
  if (row.sourceScope) return row.sourceScope;
  const symbol = row.symbol || row.probeId || '';
  const probeId = row.probeId || row.probeName || '';
  const fullName = row.fullName || extractFullNameFromSummary(row.valueSummary || '') || sessionCrabHcFullName || '';
  if (symbol.startsWith('CrabPS.') || probeId.startsWith('CrabPS.')) return 'player_state_scoped';
  if (symbol === 'CrabPS') return 'player_state_scoped';
  if (symbol.startsWith('CrabHC') || probeId.startsWith('CrabHC') || probeId === 'FindFirstOf.CrabHC') {
    if (/Destructible|ChaoticBarrel|Barrel/i.test(fullName)) return 'non_player_candidate';
    return 'ambiguous';
  }
  return '';
}

const evidenceRoot = path.join(process.cwd(), 'evidence', 'runtime');
const evidenceFiles = walk(evidenceRoot, 'access_evidence.jsonl');
const probeResultFiles = walk(evidenceRoot, 'probe_results.jsonl');
const evidenceRows = evidenceFiles.flatMap(readJsonl);
const objectdumpSymbols = readObjectdumpSymbols();
const probeCandidatesPath = path.join(process.cwd(), 'docs', 'PROBE_CANDIDATES.md');
const probeCandidatesText = fs.existsSync(probeCandidatesPath) ? fs.readFileSync(probeCandidatesPath, 'utf8') : '';
const docsDir = path.join(process.cwd(), 'docs');
fs.mkdirSync(docsDir, { recursive: true });

const sessionCrabHcFullNames = new Map();
for (const row of evidenceRows) {
  if ((row.probeId || row.probeName) === 'CrabHC.GetFullName' && row.sessionId && row.valueSummary) {
    sessionCrabHcFullNames.set(row.sessionId, row.valueSummary);
  }
}

const byAccess = new Map();
for (const row of evidenceRows) {
  const symbol = row.symbol || row.probeId || 'Unknown';
  const accessMethod = row.accessMethod || row.accessKind || 'Unknown';
  const key = `${symbol}\t${accessMethod}`;
  if (!byAccess.has(key)) {
    byAccess.set(key, {
      symbol,
      owner: row.owner || 'Unknown',
      member: row.member || '',
      accessMethod,
      accessKind: row.accessKind || '',
      contexts: new Set(),
      roles: new Set(),
      statuses: [],
      sessions: new Set(),
      lastResult: '',
      lastSummary: '',
      fullName: '',
      shortName: '',
      nameSource: '',
      objectClass: '',
      sourceScopes: new Set(),
      notes: new Set()
    });
  }
  const entry = byAccess.get(key);
  if (row.context) entry.contexts.add(row.context);
  if (row.role) entry.roles.add(row.role);
  if (row.runtimeStatus) entry.statuses.push(row.runtimeStatus);
  if (row.sessionId) entry.sessions.add(row.sessionId);
  entry.lastResult = row.result || '';
  entry.lastSummary = row.valueSummary || row.error || '';
  const sourceScope = classifyHealthSource(row, sessionCrabHcFullNames.get(row.sessionId));
  if (sourceScope) entry.sourceScopes.add(sourceScope);
  const fullName = row.fullName || extractFullNameFromSummary(row.valueSummary || '');
  if (fullName) {
    const parsed = parseIdentityFromFullName(fullName);
    entry.fullName = fullName;
    entry.shortName = row.shortName || parsed.shortName;
    entry.nameSource = row.nameSource || parsed.nameSource;
    entry.objectClass = row.objectClass || parsed.objectClass;
  }
  if (row.localNotes) entry.notes.add(row.localNotes);
}

const rows = Array.from(byAccess.values()).sort((a, b) =>
  a.owner.localeCompare(b.owner) || a.symbol.localeCompare(b.symbol) || a.accessMethod.localeCompare(b.accessMethod)
);

function matrixTable(entries) {
  let out = '| Symbol | Access method | Contexts confirmed | Roles confirmed | Runtime status | Last result | Evidence sessions | Notes |\n';
  out += '|---|---|---|---|---|---|---|---|\n';
  for (const entry of entries) {
    const status = bestStatus(entry.statuses);
    const contexts = status === 'SAFE' ? Array.from(entry.contexts).sort().join(', ') : Array.from(entry.contexts).sort().join(', ');
    const roles = status === 'SAFE' ? Array.from(entry.roles).sort().join(', ') : Array.from(entry.roles).sort().join(', ');
    const identityNote = entry.shortName ? `shortName=${entry.shortName} nameSource=${entry.nameSource} objectClass=${entry.objectClass}` : '';
    const sourceScope = Array.from(entry.sourceScopes).sort().join(', ');
    const sourceNote = sourceScope ? `sourceScope=${sourceScope}` : '';
    const scalarNote = entry.lastSummary && !identityNote ? `value=${entry.lastSummary}` : '';
    const notes = Array.from(entry.notes).sort().join('; ') || [sourceNote, identityNote, scalarNote].filter(Boolean).join('; ') || '';
    out += `| \`${md(entry.symbol)}\` | ${md(entry.accessMethod)} | ${md(contexts)} | ${md(roles)} | ${status} | ${md(entry.lastResult)} | ${md(Array.from(entry.sessions).sort().join(', '))} | ${md(notes)} |\n`;
  }
  return out;
}

let index = '# Runtime Evidence Index\n\n';
index += 'Generated from imported runtime evidence under `evidence/runtime/`.\n\n';
index += `- Access evidence files: ${evidenceFiles.length}\n`;
index += `- Probe result files: ${probeResultFiles.length}\n`;
index += `- Evidence rows: ${evidenceRows.length}\n`;
index += `- Objectdump symbols discovered: ${objectdumpSymbols.size}\n\n`;
index += `- Probe candidates doc present: ${probeCandidatesText ? 'yes' : 'no'}\n\n`;
index += 'Objectdump discovery means a symbol exists in static dump data. It does not mean runtime access is safe.\n';
index += '\n## Health Source Scope Notes\n\n';
index += '- `CrabPS` health rows are player-state-scoped because the probe path starts from `CrabPC -> PlayerState -> CrabPS`.\n';
index += '- `FindFirstOf.CrabHC` is unscoped and ambiguous as a player-health source. Session `20260505T002614Z` observed `BP_Destructible_ChaoticBarrel10.HC`, so unscoped `CrabHC` must not be used as the CrabInvSync v2 player health source.\n';
index += '- `CrabHC` read success proves only that the observed component can be read. It does not prove player ownership unless a later discovery phase establishes that relationship.\n';
index += '\n## Confirmed SAFE Access Rows\n\n';
const safeRows = rows.filter((row) => bestStatus(row.statuses) === 'SAFE');
if (safeRows.length === 0) {
  index += '- None yet.\n';
} else {
  index += matrixTable(safeRows);
}

let matrix = '# Safe Access Matrix\n\n';
matrix += 'SAFE status is scoped to the contexts, roles, lifecycle states, and access method shown in the evidence. DirectField and GetPropertyValue are separate access paths.\n\n';
matrix += 'Health source scope matters: `CrabPS` health rows are player-state-scoped; unscoped `FindFirstOf.CrabHC` is ambiguous and has already found `BP_Destructible_ChaoticBarrel10.HC`, so it is not player-health proof.\n\n';
matrix += matrixTable(rows);

const byOwner = new Map();
for (const row of rows) {
  if (!byOwner.has(row.owner)) byOwner.set(row.owner, []);
  byOwner.get(row.owner).push(row);
}
let reference = '# Symbol Access Reference\n\n';
reference += 'Grouped by owner. A symbol may have multiple access methods with different runtime statuses.\n\n';
for (const owner of Array.from(byOwner.keys()).sort()) {
  reference += `## ${owner}\n\n`;
  reference += matrixTable(byOwner.get(owner));
  reference += '\n';
}

let unsafe = '# Known Unsafe Paths\n\n';
unsafe += '- HUD ReceiveDrawHUD tick hook is known unsafe in current Crab Champions/UE4SS evidence and remains blocked by default.\n';
unsafe += '- `FindFirstOf.CrabHC` is not a safe player-health source. It is unscoped and session `20260505T002614Z` found `BP_Destructible_ChaoticBarrel10.HC`, a destructible/barrel component.\n';
const unsafeRows = rows.filter((row) => ['LUA_ERROR', 'UNSAFE_DISABLED'].includes(bestStatus(row.statuses)));
if (unsafeRows.length > 0) {
  unsafe += '\n' + matrixTable(unsafeRows);
}

let untested = '# Untested Access Paths\n\n';
untested += 'The following areas remain UNTESTED or UNSAFE_DISABLED unless explicit runtime evidence is imported later.\n\n';
untested += '| Symbol | Access method | Runtime status | Notes |\n';
untested += '|---|---|---|---|\n';
const defaultUntested = [
  ['CrabPS.InventoryInfo', 'GetPropertyValue', 'UNTESTED', 'InventoryInfo probes are disabled.'],
  ['CrabPS.InventoryInfo', 'DirectField', 'UNTESTED', 'Direct field access is a separate risk class.'],
  ['CrabInventoryInfo.*', 'array traversal', 'UNTESTED', 'Deep arrays are disabled.'],
  ['CrabHC.Health', 'read', 'UNTESTED', 'Health probes are disabled.'],
  ['CrabHC.HealthInfo.*', 'write', 'UNTESTED', 'Health writes are disabled.'],
  ['CrabHC.PlayerOwnership', 'discovery', 'UNTESTED', 'Player-owned CrabHC discovery is not proven yet; unscoped FindFirstOf.CrabHC is ambiguous.'],
  ['CrabPS.HealthInfo.*', 'write', 'UNTESTED', 'Health writes are disabled.'],
  ['CrabPS.HealthInfo.*', 'joined-client', 'UNTESTED', 'Multiplayer/joined-client health evidence does not exist yet.'],
  ['CrabHC.HealthInfo.*', 'multiplayer', 'UNTESTED', 'Multiplayer max-health math is untested.'],
  ['GameplayState.*', 'write', 'UNSAFE_DISABLED', 'Writes are disabled.'],
  ['RPC.*', 'rpc', 'UNSAFE_DISABLED', 'RPC probes are disabled.']
];
for (const [symbol, method, status, notes] of defaultUntested) {
  const hasEvidence = rows.some((row) => row.symbol === symbol && row.accessMethod === method);
  if (!hasEvidence) untested += `| \`${symbol}\` | ${method} | ${status} | ${notes} |\n`;
}

fs.writeFileSync(path.join(docsDir, 'RUNTIME_EVIDENCE_INDEX.md'), index);
fs.writeFileSync(path.join(docsDir, 'SAFE_ACCESS_MATRIX.md'), matrix);
fs.writeFileSync(path.join(docsDir, 'SYMBOL_ACCESS_REFERENCE.md'), reference);
fs.writeFileSync(path.join(docsDir, 'KNOWN_UNSAFE_PATHS.md'), unsafe);
fs.writeFileSync(path.join(docsDir, 'UNTESTED_ACCESS_PATHS.md'), untested);

console.log('generated access docs = docs/RUNTIME_EVIDENCE_INDEX.md, docs/SAFE_ACCESS_MATRIX.md, docs/SYMBOL_ACCESS_REFERENCE.md, docs/KNOWN_UNSAFE_PATHS.md, docs/UNTESTED_ACCESS_PATHS.md');
