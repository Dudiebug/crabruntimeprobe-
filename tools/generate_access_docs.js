#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { parseIdentityFromFullName, extractFullNameFromSummary } = require('./identity_helpers');
const { classifyCrystalsReadEvidence, classifySafeScalarWatchEvidence, classifyPerkDataAssetCatalogEvidence, classifySlotsReadEvidence, classifyLocalInventoryArrayEvidence, classifyLocalInventoryArrayShapeConfirmEvidence, classifyLocalInventoryUserdataIntrospectionEvidence, classifyResourceVisibilityEvidence, hasConfirmedVisibleRosterEvidence, hasCrashSuspectEvidenceForSession, hasRawIdentityLeak } = require('./campaign_helpers');

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

function formatReadableCount(count, total) {
  const denominator = Number.isFinite(Number(total)) && Number(total) > 0 ? Number(total) : 0;
  return `${count}/${denominator}`;
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
const diagnosticFiles = walk(evidenceRoot, 'diagnostic_summary.txt');
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

function parseDiagnosticSummary(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (match) out[match[1]] = match[2];
  }
  return out;
}

const diagnosticRows = diagnosticFiles.map((file) => ({
  file,
  values: parseDiagnosticSummary(fs.readFileSync(file, 'utf8'))
}));
const watchEvidenceRows = evidenceRows.filter((row) => (row.probeId || row.probeName) === 'Health.PlayerState.Sample');
const identityEvidenceRows = evidenceRows.filter((row) => /^Identity\./.test(row.probeId || row.probeName || ''));
const resourceVisibilityEvidenceRows = evidenceRows.filter((row) => /^ResourceVisibility\./.test(row.probeId || row.probeName || ''));
const latestWatchDiagnostic = diagnosticRows
  .filter((row) => row.values.health_playerstate_watch_sample_count)
  .sort((a, b) => a.file.localeCompare(b.file))
  .pop();

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
index += `- Diagnostic summaries: ${diagnosticFiles.length}\n`;
index += `- Evidence rows: ${evidenceRows.length}\n`;
index += `- Health playerstate watch samples: ${watchEvidenceRows.length}\n`;
index += `- Identity/roster samples: ${identityEvidenceRows.length}\n`;
index += `- Resource visibility samples: ${resourceVisibilityEvidenceRows.length}\n`;
index += `- Objectdump symbols discovered: ${objectdumpSymbols.size}\n\n`;
index += `- Probe candidates doc present: ${probeCandidatesText ? 'yes' : 'no'}\n\n`;
index += 'Objectdump discovery means a symbol exists in static dump data. It does not mean runtime access is safe.\n';
index += '\n## Health Source Scope Notes\n\n';
index += '- `CrabPS` health rows are player-state-scoped because the probe path starts from `CrabPC -> PlayerState -> CrabPS`.\n';
index += '- `CrabPC -> PlayerState -> CrabPS -> HealthInfo` is the only currently confirmed safe player health read path.\n';
index += '- `FindFirstOf.CrabHC` is unscoped and ambiguous as a player-health source. Session `20260505T002614Z` observed `BP_Destructible_ChaoticBarrel10.HC`, so unscoped `CrabHC` must not be used as the CrabInvSync v2 player health source.\n';
index += '- `CrabHC` read success proves only that the observed component can be read. It does not prove player ownership unless a later discovery phase establishes that relationship.\n';
index += '- `health-playerstate-watch` is a read-only time-series diagnostic for vanilla local PlayerState health visibility.\n';
index += '- RuntimeProbe documents what vanilla exposes. CrabInvSync may later build pooled/shared behavior from reported local state, but pooled/shared health is not vanilla RuntimeProbe evidence.\n';
if (latestWatchDiagnostic) {
  const v = latestWatchDiagnostic.values;
  const terminalZeroObserved = v.health_playerstate_watch_currentHealth_last === '0' && v.health_playerstate_watch_currentMaxHealth_last === '0';
  index += '\n## Latest Health PlayerState Watch Summary\n\n';
  index += `- Samples: ${v.health_playerstate_watch_sample_count || 'not found'}\n`;
  index += `- PlayerState watch probe ran: ${v.playerstate_health_watch_probe_ran || 'not found'}\n`;
  index += `- CrabHC touched: ${v.crab_hc_touched || 'not found'}\n`;
  index += `- Ambiguous CrabHC detected: ${v.ambiguous_crabhc_detected || 'not found'}\n`;
  index += `- Unsafe gates: HUD=${v.allowHudTickHook || 'not found'}, deepArrays=${v.allowDeepArrayProbes || 'not found'}, InventoryInfo=${v.allowInventoryInfoProbes || 'not found'}, writes=${v.allowWriteProbes || 'not found'}, RPCs=${v.allowRpcProbes || 'not found'}, unknownRole=${v.allowUnknownRoleProbes || 'not found'}, joinedClientDeep=${v.allowJoinedClientDeepProbes || 'not found'}\n`;
  index += `- currentHealth first/last/min/max: ${v.health_playerstate_watch_currentHealth_first || 'not found'} / ${v.health_playerstate_watch_currentHealth_last || 'not found'} / ${v.health_playerstate_watch_currentHealth_min || 'not found'} / ${v.health_playerstate_watch_currentHealth_max || 'not found'}\n`;
  index += `- currentMaxHealth first/last/min/max: ${v.health_playerstate_watch_currentMaxHealth_first || 'not found'} / ${v.health_playerstate_watch_currentMaxHealth_last || 'not found'} / ${v.health_playerstate_watch_currentMaxHealth_min || 'not found'} / ${v.health_playerstate_watch_currentMaxHealth_max || 'not found'}\n`;
  index += `- baseMaxHealth first/last/min/max: ${v.health_playerstate_watch_baseMaxHealth_first || 'not found'} / ${v.health_playerstate_watch_baseMaxHealth_last || 'not found'} / ${v.health_playerstate_watch_baseMaxHealth_min || 'not found'} / ${v.health_playerstate_watch_baseMaxHealth_max || 'not found'}\n`;
  index += `- maxHealthMultiplier first/last/min/max: ${v.health_playerstate_watch_maxHealthMultiplier_first || 'not found'} / ${v.health_playerstate_watch_maxHealthMultiplier_last || 'not found'} / ${v.health_playerstate_watch_maxHealthMultiplier_min || 'not found'} / ${v.health_playerstate_watch_maxHealthMultiplier_max || 'not found'}\n`;
  index += `- Possible base health model: ${v.possible_base_health_model || 'not found'}\n`;
  index += '- Vanilla local PlayerState health visibility: 250/250 observed during valid samples; BaseMaxHealth stayed 250 and MaxHealthMultiplier stayed 1 in the latest watch evidence.\n';
  index += terminalZeroObserved
    ? '- Terminal 0/0 was observed; treat it as a likely lifecycle, quit, transition, or despawn artifact unless separately proven.\n'
    : '- Terminal 0/0 was not observed in the latest watch summary.\n';
}
if (identityEvidenceRows.length > 0) {
  const localVisible = identityEvidenceRows.some((row) => row.localPlayerPresent === true);
  const visibleCounts = identityEvidenceRows.map((row) => Number(row.visiblePlayerCount)).filter((n) => Number.isFinite(n));
  const maxVisible = visibleCounts.length > 0 ? Math.max(...visibleCounts) : 0;
  const rawIdentityEvidence = hasRawIdentityLeak(identityEvidenceRows, false);
  const rosterResolved = hasConfirmedVisibleRosterEvidence(identityEvidenceRows);
  const sourcePaths = Array.from(new Set(identityEvidenceRows.map((row) => row.sourcePath).filter(Boolean))).sort();
  const candidateRows = identityEvidenceRows.filter((row) => {
    const id = row.probeId || row.probeName || row.event || '';
    return /SourceCandidate$/.test(id) ||
      id === 'Identity.PlayerArray.Shape' ||
      id === 'Identity.FindAll.PlayerStateCandidates' ||
      id === 'Identity.PlayerControllerCandidates';
  });
  const candidateNames = Array.from(new Set(candidateRows.map((row) => row.probeId || row.probeName || row.event).filter(Boolean))).sort();
  const playerArrayNil = identityEvidenceRows.some((row) =>
    /PlayerArray/.test(row.sourcePath || '') &&
    (row.result === 'nil' || row.playerArrayValueKind === 'nil' || (row.localNotes || '').includes('not exposed as a Lua table'))
  );
  index += '\n## Latest Identity Roster Summary\n\n';
  index += `- Local player identity visible: ${localVisible ? 'yes' : 'not proven'}\n`;
  index += `- Max visible player count observed: ${maxVisible}\n`;
  index += `- Any candidate exposed more than one player: ${maxVisible > 1 ? 'yes' : 'no'}\n`;
  index += `- Source paths observed: ${sourcePaths.length > 0 ? sourcePaths.join(', ') : 'not found'}\n`;
  index += `- Roster source candidates attempted: ${candidateNames.length > 0 ? candidateNames.join(', ') : 'none'}\n`;
  index += `- Raw IDs/names emitted: ${rawIdentityEvidence ? 'yes' : 'no; redacted/fingerprinted by default'}\n`;
  index += `- Visible roster source resolved: ${rosterResolved ? 'yes' : 'no'}\n`;
  index += '- PlayerState identity reads are safe and redacted; PlayerName and UniqueId can be fingerprinted without emitting raw values.\n';
  index += '- Runtime context `solo-or-host` means local-player-present in the current detector; it is not proof of solo and cannot distinguish true solo from multiplayer host-like local context.\n';
  if (rosterResolved) {
    index += '- Visible player roster source is confirmed; auto-room grouping still requires matched host and joined-client runs.\n';
  } else {
    index += playerArrayNil
      ? '- GameStateBase.PlayerArray returned nil / was not exposed as a Lua table in the latest roster run.\n'
      : '- GameStateBase.PlayerArray has not yet produced a resolved visible roster in imported evidence.\n';
    index += '- Visible player roster is still unresolved; auto-room grouping is not ready yet.\n';
  }
}
const resourceVisibility = classifyResourceVisibilityEvidence(evidenceRows);
index += '\n## Multiplayer Resource Visibility Summary\n\n';
if (!resourceVisibility.resourceVisibilityEvidenceFound) {
  index += '- Summary: unresolved; no `multiplayer-resource-visibility-read` evidence has been imported yet.\n';
  index += '- Player count sampled: 0\n';
} else {
  index += `- Summary: ${resourceVisibility.classification}\n`;
  index += `- Resource visibility class: ${resourceVisibility.status}\n`;
  index += `- Player count sampled: ${resourceVisibility.sampledPlayerStateCount}\n`;
  index += `- Fields visible across more than one PlayerState: ${resourceVisibility.fieldsVisibleAcrossMultiple.length ? resourceVisibility.fieldsVisibleAcrossMultiple.join(', ') : 'none'}\n`;
  index += `- Fields only visible on local PlayerState: ${resourceVisibility.fieldsOnlyVisibleOnLocal.length ? resourceVisibility.fieldsOnlyVisibleOnLocal.join(', ') : 'none'}\n`;
  index += `- Fields returning nil/errors: ${resourceVisibility.fieldsNilOrErrors.length ? resourceVisibility.fieldsNilOrErrors.join(', ') : 'none'}\n`;
  index += `- Readable categories by candidate: crystals=${formatReadableCount(resourceVisibility.readableCrystals, resourceVisibility.sampledPlayerStateCount)}, slots=${formatReadableCount(resourceVisibility.readableSlots, resourceVisibility.sampledPlayerStateCount)}, equipment=${formatReadableCount(resourceVisibility.readableEquipment, resourceVisibility.sampledPlayerStateCount)}, inventory array counts=${formatReadableCount(resourceVisibility.readableInventoryArrayCounts, resourceVisibility.sampledPlayerStateCount)}, health=${formatReadableCount(resourceVisibility.readableHealth, resourceVisibility.sampledPlayerStateCount)}\n`;
  index += `- Supports future P2P resource merge design: ${resourceVisibility.supportsP2PResourceMerge}\n`;
  index += '- CrabInvSync v2 implication: P2P-style merge is plausible for crystals, slots, equipment, and possibly health inputs.\n';
  index += '- Inventory item sync still needs separate research; current shallow count-only inventory array visibility is unresolved and does not expose item metadata.\n';
  index += '- An external relay/server may still be needed for inventory until array/item metadata visibility or another safe carrier is proven.\n';
}
index += '- Raw identity values are not emitted by this summary; PlayerName and UniqueId evidence remains fingerprint-only.\n';
index += '- No writes/RPCs/HUD hooks/deep array element reads/InventoryInfo/Enhancements are part of this phase.\n';
const localInventoryFacts = {
  text: [
    ...evidenceRows.map((row) => JSON.stringify(row)),
    ...diagnosticRows.map((row) => Object.entries(row.values).map(([key, value]) => `${key}=${value}`).join('\n'))
  ].join('\n')
};
const latestLocalInventorySessionId = evidenceRows
  .filter((row) => {
    const id = row.probeId || row.probeName || row.event || '';
    return /^Inventory\.Local(Arrays|Slots)\./.test(id) &&
      id !== 'Inventory.LocalArrays.ShapeConfirm' &&
      id !== 'Inventory.LocalArrays.UserdataIntrospection';
  })
  .map((row) => row.sessionId)
  .filter(Boolean)
  .sort()
  .pop();
const localInventory = classifyLocalInventoryArrayEvidence(evidenceRows, {
  crashSuspect: hasCrashSuspectEvidenceForSession(localInventoryFacts, latestLocalInventorySessionId)
});
const latestLocalInventoryShapeConfirmSessionId = evidenceRows
  .filter((row) => (row.probeId || row.probeName || row.event || '') === 'Inventory.LocalArrays.ShapeConfirm')
  .map((row) => row.sessionId)
  .filter(Boolean)
  .sort()
  .pop();
const localInventoryShapeConfirm = classifyLocalInventoryArrayShapeConfirmEvidence(evidenceRows, {
  crashSuspect: hasCrashSuspectEvidenceForSession(localInventoryFacts, latestLocalInventoryShapeConfirmSessionId)
});
const latestLocalInventoryUserdataIntrospectionSessionId = evidenceRows
  .filter((row) => (row.probeId || row.probeName || row.event || '') === 'Inventory.LocalArrays.UserdataIntrospection')
  .map((row) => row.sessionId)
  .filter(Boolean)
  .sort()
  .pop();
const localInventoryUserdataIntrospection = classifyLocalInventoryUserdataIntrospectionEvidence(evidenceRows, {
  crashSuspect: hasCrashSuspectEvidenceForSession(localInventoryFacts, latestLocalInventoryUserdataIntrospectionSessionId)
});
const latestCrystalsReadSessionId = evidenceRows
  .filter((row) => (row.probeId || row.probeName || row.event || '') === 'Resource.Crystals.Read')
  .map((row) => row.sessionId)
  .filter(Boolean)
  .sort()
  .pop();
const crystalsRead = classifyCrystalsReadEvidence(evidenceRows, {
  crashSuspect: hasCrashSuspectEvidenceForSession(localInventoryFacts, latestCrystalsReadSessionId)
});
const latestSlotsReadSessionId = evidenceRows
  .filter((row) => (row.probeId || row.probeName || row.event || '') === 'Resource.Slots.Read')
  .map((row) => row.sessionId)
  .filter(Boolean)
  .sort()
  .pop();
const slotsRead = classifySlotsReadEvidence(evidenceRows, {
  crashSuspect: hasCrashSuspectEvidenceForSession(localInventoryFacts, latestSlotsReadSessionId)
});
const latestSafeScalarWatchSessionId = evidenceRows
  .filter((row) => ['SafeWatch.Scalar.Sample', 'Runtime.SafeScalarWatch.Sample'].includes(row.probeId || row.probeName || row.event || ''))
  .map((row) => row.sessionId)
  .filter(Boolean)
  .sort()
  .pop();
const safeScalarWatch = classifySafeScalarWatchEvidence(evidenceRows, {
  crashSuspect: hasCrashSuspectEvidenceForSession(localInventoryFacts, latestSafeScalarWatchSessionId)
});
const latestPerkCatalogSessionId = evidenceRows
  .filter((row) => (row.probeId || row.probeName || row.event || '') === 'DataAsset.Perks.CatalogRead')
  .map((row) => row.sessionId)
  .filter(Boolean)
  .sort()
  .pop();
const perkCatalog = classifyPerkDataAssetCatalogEvidence(evidenceRows, {
  crashSuspect: hasCrashSuspectEvidenceForSession(localInventoryFacts, latestPerkCatalogSessionId)
});
index += '\n## Local Inventory Array Shallow/Count Visibility Summary\n\n';
if (!localInventory.localInventoryArrayEvidenceFound) {
  index += '- Summary: unresolved; no `local-inventory-array-shallow-read` evidence has been imported yet.\n';
  index += '- Local PlayerState present: not proven\n';
} else {
  index += `- Summary: ${localInventory.classification}\n`;
  index += `- Local inventory array status: ${localInventory.status}\n`;
  index += `- Local PlayerState present: ${localInventory.localPlayerStatePresent ? 'yes' : 'not proven'}\n`;
  index += `- Fields readable by shallow shape/count: ${localInventory.fieldsReadable.length ? localInventory.fieldsReadable.join(', ') : 'none'}\n`;
  index += `- Fields nil or unsupported: ${localInventory.fieldsNilOrUnsupported.length ? localInventory.fieldsNilOrUnsupported.join(', ') : 'none'}\n`;
  index += `- Array value kinds: ${Object.keys(localInventory.arrayValueKinds).length ? Object.entries(localInventory.arrayValueKinds).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Array counts available: ${localInventory.countableLuaTableFields.length ? `yes, Lua table counts for ${localInventory.countableLuaTableFields.join(', ')}` : 'no; current helper only counts Lua tables and these values were userdata shapes'}\n`;
  index += `- Slot scalar values: ${Object.keys(localInventory.slotScalarValues).length ? Object.entries(localInventory.slotScalarValues).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Array elements dereferenced: ${localInventory.noElementDereference ? 'no' : 'yes'}\n`;
  index += localInventory.crashSuspect
    ? '- A crash dump exists after this run, so this path remains crash-suspect pending another safer confirmation pass.\n'
    : '- No crash dump is associated with the imported local inventory evidence.\n';
}
index += '- Local inventory array visibility is separate from remote PlayerState inventory array visibility.\n';
index += '- InventoryInfo and Enhancements were not read; writes/RPCs/HUD hooks/deep arrays were disabled.\n';
index += '- Remote inventory array visibility remains unresolved separately.\n';
index += '\n## Local Inventory Array Shape Confirm Summary\n\n';
if (!localInventoryShapeConfirm.localInventoryShapeConfirmEvidenceFound) {
  index += '- Summary: unresolved; no `local-inventory-array-shape-confirm` evidence has been imported yet.\n';
  index += '- Shape confirm repeats only local CrabPC -> PlayerState slot scalar and inventory array property shape reads.\n';
  index += '- It does not count arrays, traverse arrays, dereference userdata, read InventoryInfo, or read Enhancements.\n';
} else {
  index += `- Summary: ${localInventoryShapeConfirm.classification}\n`;
  index += `- Local inventory shape confirm status: ${localInventoryShapeConfirm.status}\n`;
  index += `- Local PlayerState present: ${localInventoryShapeConfirm.localPlayerStatePresent ? 'yes' : 'not proven'}\n`;
  index += `- Fields readable by property shape confirm: ${localInventoryShapeConfirm.fieldsReadable.length ? localInventoryShapeConfirm.fieldsReadable.join(', ') : 'none'}\n`;
  index += `- Fields nil or unsupported: ${localInventoryShapeConfirm.fieldsNilOrUnsupported.length ? localInventoryShapeConfirm.fieldsNilOrUnsupported.join(', ') : 'none'}\n`;
  index += `- Property present map: ${Object.keys(localInventoryShapeConfirm.arrayPropertiesPresent).length ? Object.entries(localInventoryShapeConfirm.arrayPropertiesPresent).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Array value kinds: ${Object.keys(localInventoryShapeConfirm.arrayValueKinds).length ? Object.entries(localInventoryShapeConfirm.arrayValueKinds).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Safe tostring kinds: ${Object.keys(localInventoryShapeConfirm.arrayTostringKinds).length ? Object.entries(localInventoryShapeConfirm.arrayTostringKinds).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Slot scalar values: ${Object.keys(localInventoryShapeConfirm.slotScalarValues).length ? Object.entries(localInventoryShapeConfirm.slotScalarValues).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Array counts attempted: ${localInventoryShapeConfirm.noArrayCount ? 'no' : 'yes'}\n`;
  index += `- Array traversal attempted: ${localInventoryShapeConfirm.noArrayTraversal ? 'no' : 'yes'}\n`;
  index += `- Array elements dereferenced: ${localInventoryShapeConfirm.noElementDereference ? 'no' : 'yes'}\n`;
  index += `- InventoryInfo read: ${localInventoryShapeConfirm.noInventoryInfo ? 'no' : 'yes'}\n`;
  index += `- Enhancements read: ${localInventoryShapeConfirm.noEnhancements ? 'no' : 'yes'}\n`;
  index += localInventoryShapeConfirm.crashSuspect
    ? '- A crash dump exists after this run, so this confirmation path remains crash-suspect pending another safer confirmation pass.\n'
    : '- No crash dump is associated with the imported shape-confirm evidence.\n';
  index += '- Shape confirm distinguishes userdata shape visibility from countable Lua table arrays; counts remain unavailable for userdata values.\n';
}
index += '\n## Local Inventory Userdata Introspection Summary\n\n';
if (!localInventoryUserdataIntrospection.localInventoryUserdataIntrospectionEvidenceFound) {
  index += '- Summary: unresolved; no `local-inventory-userdata-introspection` evidence has been imported yet.\n';
  index += '- Userdata introspection inspects wrapper metadata only after shape visibility is confirmed.\n';
  index += '- It does not traverse arrays, dereference elements, read InventoryInfo, read Enhancements, write, or call RPCs.\n';
} else {
  index += `- Summary: ${localInventoryUserdataIntrospection.classification}\n`;
  index += `- Local inventory userdata introspection status: ${localInventoryUserdataIntrospection.status}\n`;
  index += `- Local PlayerState present: ${localInventoryUserdataIntrospection.localPlayerStatePresent ? 'yes' : 'not proven'}\n`;
  index += `- Fields readable by userdata introspection: ${localInventoryUserdataIntrospection.fieldsReadable.length ? localInventoryUserdataIntrospection.fieldsReadable.join(', ') : 'none'}\n`;
  index += `- Value kinds: ${Object.keys(localInventoryUserdataIntrospection.valueKinds).length ? Object.entries(localInventoryUserdataIntrospection.valueKinds).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Safe tostring kinds: ${Object.keys(localInventoryUserdataIntrospection.tostringKinds).length ? Object.entries(localInventoryUserdataIntrospection.tostringKinds).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Metatable kinds: ${Object.keys(localInventoryUserdataIntrospection.metatableKinds).length ? Object.entries(localInventoryUserdataIntrospection.metatableKinds).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Length operator attempted: ${Object.keys(localInventoryUserdataIntrospection.lenOperatorAttempted).length ? Object.entries(localInventoryUserdataIntrospection.lenOperatorAttempted).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Length operator results: ${Object.keys(localInventoryUserdataIntrospection.lenOperatorResults).length ? Object.entries(localInventoryUserdataIntrospection.lenOperatorResults).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Length operator errors: ${Object.keys(localInventoryUserdataIntrospection.lenOperatorErrors).length ? Object.entries(localInventoryUserdataIntrospection.lenOperatorErrors).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Array traversal attempted: ${localInventoryUserdataIntrospection.noArrayTraversal ? 'no' : 'yes'}\n`;
  index += `- Array elements dereferenced: ${localInventoryUserdataIntrospection.noElementDereference ? 'no' : 'yes'}\n`;
  index += `- InventoryInfo read: ${localInventoryUserdataIntrospection.noInventoryInfo ? 'no' : 'yes'}\n`;
  index += `- Enhancements read: ${localInventoryUserdataIntrospection.noEnhancements ? 'no' : 'yes'}\n`;
  index += `- Writes/RPCs: ${localInventoryUserdataIntrospection.noWrites && localInventoryUserdataIntrospection.noRpcs ? 'no' : 'yes'}\n`;
  index += '- Length operator results, if present, are metadata-only and do not prove count traversal, element traversal, or item sync.\n';
}
index += '\n## Local Crystals Read Summary\n\n';
if (!crystalsRead.crystalsReadEvidenceFound) {
  index += '- Summary: unresolved; no `crystals-read` evidence has been imported yet.\n';
  index += '- Crystals-read will read only local `CrabPC -> PlayerState -> CrabPS -> Crystals`.\n';
  index += '- UInt32 range is documentation only; RuntimeProbe does not write or clamp values.\n';
} else {
  index += `- Summary: ${crystalsRead.classification}\n`;
  index += `- Crystals read status: ${crystalsRead.status}\n`;
  index += `- Local PlayerState present: ${crystalsRead.localPlayerStatePresent ? 'yes' : 'not proven'}\n`;
  index += `- Crystals read attempted: ${crystalsRead.crystalsReadAttempted ? 'yes' : 'no'}\n`;
  index += `- Crystals value present: ${crystalsRead.crystalsPresent ? 'yes' : 'no'}\n`;
  index += `- Crystals value integer-like when present: ${crystalsRead.valueIntegerLike ? 'yes' : 'no'}\n`;
  index += `- Writes/RPCs: ${crystalsRead.noWrites && crystalsRead.noRpcs ? 'no' : 'yes'}\n`;
  index += `- HUD/deep arrays: ${crystalsRead.noHud && crystalsRead.noDeepArrays ? 'no' : 'yes'}\n`;
  index += `- Inventory arrays/InventoryInfo/Enhancements: ${crystalsRead.noArrayTraversal && crystalsRead.noElementDereference && crystalsRead.noInventoryInfo && crystalsRead.noEnhancements ? 'no' : 'yes'}\n`;
  index += '- UInt32 range is documentation only for this read-only phase; RuntimeProbe does not write or clamp the value.\n';
}
index += '\n## Local Slots Read Summary\n\n';
if (!slotsRead.slotsReadEvidenceFound) {
  index += '- Summary: unresolved; no `slots-read` evidence has been imported yet.\n';
  index += '- Slots-read will read only local `CrabPC -> PlayerState -> CrabPS` scalar fields: `NumWeaponModSlots`, `NumAbilityModSlots`, `NumMeleeModSlots`, `NumPerkSlots`.\n';
  index += '- ByteProperty range 0..255 is documentation only; RuntimeProbe does not write or clamp values.\n';
  index += '- Locked slots remain unresolved; no separate locked/max/total slot-capacity field was found in the tracked objectdump-derived notes.\n';
} else {
  index += `- Summary: ${slotsRead.classification}\n`;
  index += `- Slots read status: ${slotsRead.status}\n`;
  index += `- Local PlayerState present: ${slotsRead.localPlayerStatePresent ? 'yes' : 'not proven'}\n`;
  index += `- Slot read attempted: ${slotsRead.slotsReadAttempted ? 'yes' : 'no'}\n`;
  index += `- Present slot values: ${Object.keys(slotsRead.slotScalarValues).length ? Object.entries(slotsRead.slotScalarValues).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Present slot values integer-like: ${slotsRead.valuesIntegerLike ? 'yes' : 'no'}\n`;
  index += `- Present slot values within 0..255: ${slotsRead.valuesInByteRange ? 'yes' : 'no'}\n`;
  index += `- Writes/RPCs: ${slotsRead.noWrites && slotsRead.noRpcs ? 'no' : 'yes'}\n`;
  index += `- HUD/deep arrays: ${slotsRead.noHud && slotsRead.noDeepArrays ? 'no' : 'yes'}\n`;
  index += `- Inventory arrays/InventoryInfo/Enhancements: ${slotsRead.noArrayCount && slotsRead.noArrayTraversal && slotsRead.noElementDereference && slotsRead.noInventoryInfo && slotsRead.noEnhancements ? 'no' : 'yes'}\n`;
  index += '- These are observed scalar slot counters / candidate unlocked slot counters only; they are not proven total capacity or locked-slot state.\n';
}
index += '\n## Safe Scalar Watch Summary\n\n';
if (!safeScalarWatch.safeScalarWatchEvidenceFound) {
  index += '- Summary: unresolved; no `safe-scalar-watch` evidence has been imported yet.\n';
  index += '- Safe scalar watch will sample only proven-safe local scalar/property paths about every 5 seconds, with first/changed rows and 60-second heartbeats.\n';
} else {
  index += `- Summary: ${safeScalarWatch.classification}\n`;
  index += `- Safe scalar watch status: ${safeScalarWatch.status}\n`;
  index += `- Sample count: ${safeScalarWatch.sampleCount}\n`;
  index += `- First values: ${Object.keys(safeScalarWatch.firstValues).length ? Object.entries(safeScalarWatch.firstValues).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Latest values: ${Object.keys(safeScalarWatch.latestValues).length ? Object.entries(safeScalarWatch.latestValues).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- Min/max numeric values: ${Object.keys(safeScalarWatch.minValues).length ? Object.keys(safeScalarWatch.minValues).sort().map((key) => `${key}=${safeScalarWatch.minValues[key]}/${safeScalarWatch.maxValues[key]}`).join(', ') : 'none'}\n`;
  index += `- Changed fields: ${safeScalarWatch.changedFields.length ? safeScalarWatch.changedFields.join(', ') : 'none'}\n`;
  index += `- Change counts: ${Object.keys(safeScalarWatch.changeCounts).length ? Object.entries(safeScalarWatch.changeCounts).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
  index += `- First/last context: ${safeScalarWatch.firstContext || 'not found'} / ${safeScalarWatch.lastContext || 'not found'}\n`;
  index += `- First/last role: ${safeScalarWatch.firstRole || 'not found'} / ${safeScalarWatch.lastRole || 'not found'}\n`;
  index += `- Slot model status: ${safeScalarWatch.slotModelStatus}\n`;
  index += `- No writes/RPCs/HUD/deep arrays/inventory traversal/InventoryInfo/Enhancements: ${safeScalarWatch.noWrites && safeScalarWatch.noRpcs && safeScalarWatch.noHud && safeScalarWatch.noDeepArrays && safeScalarWatch.noArrayCount && safeScalarWatch.noArrayTraversal && safeScalarWatch.noElementDereference && safeScalarWatch.noInventoryInfo && safeScalarWatch.noEnhancements ? 'yes' : 'no'}\n`;
}
index += '\n## Perk DataAsset Catalog Summary\n\n';
if (!perkCatalog.perkDataAssetCatalogEvidenceFound) {
  index += '- Summary: unresolved; no `perk-da-catalog-read` evidence has been imported yet.\n';
  index += '- Perk catalog evidence will be read-only and is not permission to mutate DataAssets.\n';
  index += '- RuntimeProbe will prove read paths only; future CrabModFramework / CrabTastyMod write/edit APIs must be designed separately.\n';
  index += '- TastyOrange is not special-cased by RuntimeProbe. It will be cataloged as a normal perk if found.\n';
  index += '- Collector is not special-cased by RuntimeProbe. It will be cataloged as a normal perk if found.\n';
} else {
  index += `- Summary: ${perkCatalog.classification}\n`;
  index += `- Perk DataAsset catalog status: ${perkCatalog.status}\n`;
  index += `- Catalog entries: ${perkCatalog.catalogEntryCount}\n`;
  index += `- Candidate count/cap: ${perkCatalog.catalogCandidateCount}/${perkCatalog.catalogCandidateCap || 'unknown'}\n`;
  index += `- No writes/RPCs/HUD/deep arrays/live inventory arrays/counts/InventoryInfo/Enhancements/DataAsset mutation/function calls: ${perkCatalog.noWrites && perkCatalog.noRpcs && perkCatalog.noHud && perkCatalog.noDeepArrays && perkCatalog.noInventoryArrays && perkCatalog.noArrayCount && perkCatalog.noArrayTraversal && perkCatalog.noElementDereference && perkCatalog.noInventoryInfo && perkCatalog.noEnhancements && perkCatalog.noDataAssetMutation && perkCatalog.noFunctionCalls ? 'yes' : 'no'}\n`;
  index += '- RuntimeProbe proves read paths only. Future CrabModFramework / CrabTastyMod work must build controlled write/edit APIs separately.\n';
  index += '- TastyOrange is not special-cased by RuntimeProbe. It is cataloged as a normal perk if found.\n';
  index += '- Collector is not special-cased by RuntimeProbe. It is cataloged as a normal perk if found.\n';
}
index += '\n## Confirmed SAFE Access Rows\n\n';
const safeRows = rows.filter((row) => bestStatus(row.statuses) === 'SAFE');
if (safeRows.length === 0) {
  index += '- None yet.\n';
} else {
  index += matrixTable(safeRows);
}

let matrix = '# Safe Access Matrix\n\n';
matrix += 'SAFE status is scoped to the contexts, roles, lifecycle states, and access method shown in the evidence. DirectField and GetPropertyValue are separate access paths.\n\n';
matrix += 'Health source scope matters: `CrabPC -> PlayerState -> CrabPS -> HealthInfo` is the only currently confirmed safe player health read path. Unscoped `FindFirstOf.CrabHC` is ambiguous and has already found `BP_Destructible_ChaoticBarrel10.HC`, so it is not player-health proof. `health-playerstate-watch` is read-only local PlayerState time-series evidence for vanilla visibility; pooled/shared health is a CrabInvSync design concept, not vanilla RuntimeProbe evidence. Identity context `solo-or-host` means local-player-present, not confirmed solo.\n\n';
matrix += 'DataAsset catalog evidence is read-only definition evidence for future CrabModFramework APIs. It is not permission to mutate DataAssets or call DataAsset functions.\n\n';
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
unsafe += '- Do not use unscoped `CrabHC` discovery, item arrays, `InventoryInfo`, writes, RPCs, or HUD hooks for `health-playerstate-watch`.\n';
unsafe += '- Do not publish raw platform/Steam identity values from roster evidence; keep `allowRawIdentityEvidence = false` unless private evidence capture is explicitly requested.\n';
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
  ['CrabPS.HealthInfo.*', 'joined-client', 'UNTESTED', 'Joined-client local PlayerState health visibility has not been separately imported.'],
  ['CrabPS.HealthInfo.*', 'multiplayer watch', 'UNTESTED', 'Vanilla multiplayer evidence is local PlayerState health visibility only; it does not define shared/pooled health behavior.'],
  ['CrabHC.HealthInfo.*', 'multiplayer', 'UNTESTED', 'Player-owned CrabHC discovery in multiplayer is untested; do not use it to infer vanilla or CrabInvSync health behavior.'],
  ['GameState.PlayerArray', 'identity roster', 'UNTESTED', 'Roster reads require the explicit multiplayer-roster-read phase and must remain capped/redacted; latest evidence returned nil instead of a Lua table.'],
  ['CrabGS', 'identity source candidate', 'UNTESTED', 'CrabGS availability is checked only in multiplayer-roster-read and must not recurse through arbitrary fields.'],
  ['FindAllOf(PlayerState,CrabPS)', 'identity roster candidates', 'UNTESTED', 'Capped PlayerState-like discovery is gated by allowIdentityProbes and emits only redacted/fingerprinted identity values.'],
  ['FindAllOf(PlayerController,CrabPC).PlayerState', 'identity controller candidates', 'UNTESTED', 'Capped controller discovery reads only PlayerState from valid controllers.'],
  ['FindAllOf(PlayerState,CrabPS)', 'resource visibility candidates', 'UNTESTED', 'Capped resource visibility discovery is gated by allowResourceVisibilityProbes and reads only explicitly named PlayerState fields.'],
  ['CrabPS.Crystals', 'GetPropertyValue', 'UNTESTED', 'Local crystals-read evidence has not been imported yet; remote resource visibility remains separate.'],
  ['CrabPS.NumWeaponModSlots', 'GetPropertyValue', 'UNTESTED', 'Local slots-read evidence has not been imported yet; these scalars are candidate unlocked slot counters only.'],
  ['CrabPS.WeaponMods', 'RemotePlayerStateCountOnly', 'UNTESTED', 'Remote inventory arrays are count-only in resource visibility and remain unresolved until evidence proves visibility.'],
  ['CrabPS.WeaponMods', 'GetPropertyValueCountOnly', 'UNTESTED', 'Local inventory arrays require local-inventory-array-shallow-read; no element dereference.'],
  ['CrabPS.WeaponMods', 'GetPropertyValueShapeConfirm', 'UNTESTED', 'Local inventory shape confirm reads property presence/value kind only; no count, traversal, element dereference, InventoryInfo, or Enhancements.'],
  ['CrabPS.WeaponMods', 'GetPropertyValueUserdataMetadata', 'UNTESTED', 'Local inventory userdata introspection reads wrapper metadata only; length operator results are metadata-only and not element traversal proof.'],
  ['CrabPerkDA', 'FindAllOfCappedCuratedClasses', 'UNTESTED', 'Perk DataAsset catalog reads are gated by allowPerkDataAssetCatalogProbes and are read-only evidence, not permission to mutate DataAssets.'],
  ['PlayerState.UniqueId', 'identity', 'UNTESTED', 'Stable IDs must be fingerprinted unless allowRawIdentityEvidence is explicitly enabled.'],
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
