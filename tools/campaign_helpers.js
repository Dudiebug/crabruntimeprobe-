const fs = require('fs');
const path = require('path');

const CAMPAIGN = 'crabruntimeprobe-read-map';
const PLAN_PATH = path.join('campaign', 'campaign_plan.crabruntimeprobe-read-map.json');
const STATE_PATH = path.join('evidence', 'campaign_state.json');
const DOC_PATH = path.join('docs', 'CAMPAIGN_STATUS.md');

const ALL_GATES = [
  'allowHudTickHook',
  'allowUnknownRoleProbes',
  'allowJoinedClientDeepProbes',
  'allowDeepArrayProbes',
  'allowInventoryInfoProbes',
  'allowHealthProbes',
  'allowIdentityProbes',
  'allowRawIdentityEvidence',
  'allowResourceVisibilityProbes',
  'allowInventoryArrayShallowProbes',
  'allowWriteProbes',
  'allowRpcProbes'
];

const ALWAYS_FORBIDDEN = [
  'allowHudTickHook',
  'allowWriteProbes',
  'allowRpcProbes'
];

function nowIso() {
  return new Date().toISOString();
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function readJsonIfExists(file) {
  if (!fs.existsSync(file)) return null;
  return readJson(file);
}

function writeJson(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
}

function walk(dir, filter) {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full, filter));
    else if (!filter || filter(entry.name, full)) out.push(full);
  }
  return out;
}

function readTextIfExists(file) {
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
}

function readJsonl(file) {
  return readTextIfExists(file)
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

function isIdentityRow(row) {
  return /^Identity\./.test(row.probeName || row.probeId || row.event || '');
}

function hasNonEmptyRawIdentityValue(value) {
  if (value === null || value === undefined) return false;
  if (typeof value === 'string') return value.trim().length > 0;
  if (Array.isArray(value)) return value.some(hasNonEmptyRawIdentityValue);
  if (typeof value === 'object') return Object.values(value).some(hasNonEmptyRawIdentityValue);
  return false;
}

function rowAllowsRawIdentityEvidence(row) {
  const gates = row && row.safetyGates ? row.safetyGates : {};
  return row.allowRawIdentityEvidence === true || gates.allowRawIdentityEvidence === true;
}

function hasRawIdentityLeak(rows, allowRawIdentityEvidence = false) {
  return rows.some((row) => {
    if (!isIdentityRow(row)) return false;
    if (allowRawIdentityEvidence || rowAllowsRawIdentityEvidence(row)) return false;
    return row.rawIdentityEvidence === true ||
      hasNonEmptyRawIdentityValue(row.rawDisplayNames) ||
      hasNonEmptyRawIdentityValue(row.rawStableIds);
  });
}

function hasLocalIdentityEvidence(rows) {
  return rows.some((row) => {
    if (!isIdentityRow(row)) return false;
    const id = row.probeName || row.probeId || row.event || '';
    return (
      (id === 'Identity.LocalPlayer.Sample' || id === 'Identity.PlayerState.Sample') &&
      (row.result === 'ok' || row.localPlayerPresent === true) &&
      (
        row.localPlayerPresent === true ||
        hasNonEmptyRawIdentityValue(row.displayNameFingerprints) ||
        hasNonEmptyRawIdentityValue(row.stableIdFingerprints)
      )
    );
  });
}

function hasConfirmedVisibleRosterEvidence(rows) {
  return rows.some((row) => {
    if (!isIdentityRow(row)) return false;
    const visibleCount = Number(row.visiblePlayerCount);
    if (Number.isFinite(visibleCount) && visibleCount > 1) return true;
    if (row.rosterSourceResolved === true) return true;
    const id = row.probeName || row.probeId || row.event || '';
    return (
      id === 'Identity.VisiblePlayers.Sample' &&
      row.result === 'ok' &&
      row.sourceScope === 'runtime_roster' &&
      row.playerArrayValueKind === 'table' &&
      (Number.isFinite(visibleCount) ? visibleCount > 1 : false)
    );
  });
}

function classifyRosterEvidence(rows, allowRawIdentityEvidence = false) {
  const identityRows = rows.filter(isIdentityRow);
  const rawIdentityLeak = hasRawIdentityLeak(identityRows, allowRawIdentityEvidence);
  const localIdentityConfirmed = hasLocalIdentityEvidence(identityRows);
  const visibleRosterConfirmed = hasConfirmedVisibleRosterEvidence(identityRows);
  return {
    identityEvidenceFound: identityRows.length > 0,
    rawIdentityLeak,
    localIdentityConfirmed,
    visibleRosterConfirmed,
    status: rawIdentityLeak
      ? 'failed'
      : (visibleRosterConfirmed ? 'passed' : (localIdentityConfirmed ? 'local_identity_confirmed' : 'no_evidence'))
  };
}

function isResourceVisibilityRow(row) {
  return /^ResourceVisibility\./.test(row.probeName || row.probeId || row.event || '');
}

function rowNumber(row, name) {
  const value = Number(row && row[name]);
  return Number.isFinite(value) ? value : 0;
}

function flattenStringList(value) {
  if (!value) return [];
  if (Array.isArray(value)) return value.map(String).filter(Boolean);
  if (typeof value === 'string') return value.split(/\s*,\s*/).filter(Boolean);
  return [];
}

function classifyResourceVisibilityEvidence(rows) {
  const resourceRows = rows.filter(isResourceVisibilityRow);
  const sampled = Math.max(0, ...resourceRows.map((row) => rowNumber(row, 'sampledPlayerStateCount')));
  const visible = Math.max(0, ...resourceRows.map((row) => rowNumber(row, 'visiblePlayerCount')));
  const readableCrystals = Math.max(0, ...resourceRows.map((row) => rowNumber(row, 'readableCrystalsCount')));
  const readableSlots = Math.max(0, ...resourceRows.map((row) => rowNumber(row, 'readableSlotsCount')));
  const readableEquipment = Math.max(0, ...resourceRows.map((row) => rowNumber(row, 'readableEquipmentCount')));
  const readableInventoryArrayCounts = Math.max(0, ...resourceRows.map((row) => rowNumber(row, 'readableInventoryArrayCount')));
  const readableHealth = Math.max(0, ...resourceRows.map((row) => rowNumber(row, 'readableHealthCount')));
  const fieldsVisibleAcrossMultiple = Array.from(new Set(resourceRows.flatMap((row) => flattenStringList(row.fieldsVisibleAcrossMultiple)))).sort();
  const fieldsOnlyVisibleOnLocal = Array.from(new Set(resourceRows.flatMap((row) => flattenStringList(row.fieldsOnlyVisibleOnLocal)))).sort();
  const fieldsNilOrErrors = Array.from(new Set(resourceRows.flatMap((row) => flattenStringList(row.fieldsNilOrErrors)))).sort();
  const nonIdentityResourceCategoryEvaluated = resourceRows.some((row) => row.nonIdentityResourceCategoryEvaluated === true) ||
    readableCrystals > 0 || readableSlots > 0 || readableEquipment > 0 || readableInventoryArrayCounts > 0 || readableHealth > 0;
  const rawIdentityLeak = resourceRows.some((row) => {
    if (rowAllowsRawIdentityEvidence(row)) return false;
    return row.rawIdentityEvidence === true ||
      hasNonEmptyRawIdentityValue(row.rawDisplayNames) ||
      hasNonEmptyRawIdentityValue(row.rawStableIds);
  });
  const remoteResourceVisible = sampled >= 2 && (
    readableCrystals > 1 ||
    readableSlots > 1 ||
    readableEquipment > 1 ||
    readableInventoryArrayCounts > 1 ||
    fieldsVisibleAcrossMultiple.length > 0
  );
  const completeRemoteVisible = sampled >= 2 &&
    readableCrystals > 1 &&
    readableSlots > 1 &&
    readableEquipment > 1 &&
    readableInventoryArrayCounts > 1;
  let status = 'no_evidence';
  let classification = 'unresolved';
  if (rawIdentityLeak) {
    status = 'failed';
    classification = 'unresolved';
  } else if (sampled < 2 && resourceRows.length > 0) {
    status = nonIdentityResourceCategoryEvaluated ? 'local_only_evidence' : 'needs_multiplayer';
    classification = nonIdentityResourceCategoryEvaluated ? 'local-only' : 'unresolved';
  } else if (sampled >= 2 && completeRemoteVisible) {
    status = 'passed';
    classification = 'remote-visible';
  } else if (sampled >= 2 && remoteResourceVisible) {
    status = 'remote_resources_partial';
    classification = 'partial';
  } else if (sampled >= 2) {
    status = 'remote_resources_unresolved';
    classification = 'unresolved';
  }
  return {
    resourceVisibilityEvidenceFound: resourceRows.length > 0,
    rawIdentityLeak,
    visiblePlayerCount: visible,
    sampledPlayerStateCount: sampled,
    readableCrystals,
    readableSlots,
    readableEquipment,
    readableInventoryArrayCounts,
    readableHealth,
    fieldsVisibleAcrossMultiple,
    fieldsOnlyVisibleOnLocal,
    fieldsNilOrErrors,
    nonIdentityResourceCategoryEvaluated,
    remoteResourceVisible,
    completeRemoteVisible,
    classification,
    supportsP2PResourceMerge: completeRemoteVisible ? 'yes' : (remoteResourceVisible ? 'partial' : 'no'),
    status
  };
}

function isLocalInventoryArrayRow(row) {
  return /^Inventory\.Local(Arrays|Slots)\./.test(row.probeName || row.probeId || row.event || '');
}

function classifyLocalInventoryArrayEvidence(rows, options = {}) {
  const inventoryRows = rows.filter(isLocalInventoryArrayRow);
  const fieldsReadable = Array.from(new Set(inventoryRows.flatMap((row) => flattenStringList(row.fieldsReadable)))).sort();
  const fieldsNilOrUnsupported = Array.from(new Set(inventoryRows.flatMap((row) => flattenStringList(row.fieldsNilOrUnsupported)))).sort();
  const localPlayerStatePresent = inventoryRows.some((row) => row.localPlayerStatePresent === true);
  const noElementDereference = inventoryRows.length > 0 && inventoryRows.every((row) => row.noElementDereference !== false);
  const arrayValueKinds = {};
  const slotScalarValues = {};
  for (const row of inventoryRows) {
    if (row.arrayValueKinds && typeof row.arrayValueKinds === 'object') {
      for (const [name, value] of Object.entries(row.arrayValueKinds)) arrayValueKinds[name] = String(value);
    }
    if (row.slotScalarValues && typeof row.slotScalarValues === 'object') {
      for (const [name, value] of Object.entries(row.slotScalarValues)) slotScalarValues[name] = value;
    }
  }
  const hasCount = inventoryRows.some((row) => {
    if (Number.isFinite(Number(row.arrayCount))) return true;
    const counts = row.arrayCounts;
    return counts && typeof counts === 'object' && Object.values(counts).some((value) => Number.isFinite(Number(value)));
  });
  const countableLuaTableFields = Array.from(new Set(inventoryRows.flatMap((row) => {
    const counts = row.arrayCounts;
    if (!counts || typeof counts !== 'object') return [];
    return Object.entries(counts)
      .filter(([, value]) => Number.isFinite(Number(value)))
      .map(([name]) => name);
  }))).sort();
  const hasValidShape = fieldsReadable.length > 0 || inventoryRows.some((row) => {
    const kinds = row.arrayValueKinds;
    if (kinds && typeof kinds === 'object') {
      return Object.values(kinds).some((value) => value === 'table' || value === 'userdata');
    }
    return row.arrayValueKind === 'table' || row.arrayValueKind === 'userdata';
  });
  const safetyViolation = inventoryRows.some((row) => {
    const gates = row && row.safetyGates ? row.safetyGates : {};
    return gates.allowDeepArrayProbes === true ||
      gates.allowInventoryInfoProbes === true ||
      gates.allowWriteProbes === true ||
      gates.allowRpcProbes === true ||
      gates.allowHudTickHook === true ||
      gates.allowRawIdentityEvidence === true ||
      row.noElementDereference === false;
  });
  let status = 'no_evidence';
  let classification = 'unresolved';
  if (safetyViolation) {
    status = 'failed';
  } else if (inventoryRows.length > 0 && (hasCount || hasValidShape)) {
    status = options.crashSuspect ? 'crash_suspect_local_inventory_shape_visible' : 'passed';
    classification = options.crashSuspect ? 'local_inventory_shape_visible_crash_suspect' : 'local_inventory_visible';
  } else if (inventoryRows.length > 0) {
    status = 'local_inventory_unresolved';
    classification = 'unresolved';
  }
  return {
    localInventoryArrayEvidenceFound: inventoryRows.length > 0,
    localPlayerStatePresent,
    fieldsReadable,
    fieldsNilOrUnsupported,
    noElementDereference,
    hasCount,
    hasValidShape,
    arrayValueKinds,
    slotScalarValues,
    countableLuaTableFields,
    safetyViolation,
    crashSuspect: options.crashSuspect === true,
    classification,
    status
  };
}

function hasCrashSuspectEvidenceForSession(facts, sessionId) {
  const text = facts && facts.text ? facts.text : '';
  if (!text) return false;
  const escapedSessionId = sessionId ? String(sessionId).replace(/[.*+?^${}()|[\]\\]/g, '\\$&') : '';
  if (/crash_after_prepare\s*=\s*True|crash_dump_uploaded\s*=|crash_2026_05_05_07_24_18\.dmp/i.test(text)) {
    return true;
  }
  if (!escapedSessionId) return false;
  return new RegExp(`${escapedSessionId}[\\s\\S]{0,2000}(?:crash|\\.dmp|\\.mdmp)|(?:crash|\\.dmp|\\.mdmp)[\\s\\S]{0,2000}${escapedSessionId}`, 'i').test(text);
}

function formatReadableCount(count, total) {
  const denominator = Number.isFinite(Number(total)) && Number(total) > 0 ? Number(total) : 0;
  return `${count}/${denominator}`;
}

function parseKeyValueText(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (match) out[match[1]] = match[2];
  }
  return out;
}

function loadPlan(repoRoot = process.cwd()) {
  const plan = readJson(path.join(repoRoot, PLAN_PATH));
  if (plan.campaign !== CAMPAIGN) {
    throw new Error(`Unexpected campaign name: ${plan.campaign}`);
  }
  if (!Array.isArray(plan.phases) || plan.phases.length === 0) {
    throw new Error('Campaign plan has no phases.');
  }
  return plan;
}

function gateConfigForPhase(phase) {
  const gates = {};
  for (const gate of ALL_GATES) gates[gate] = false;
  for (const [gate, value] of Object.entries(phase.requiredGates || {})) {
    gates[gate] = value === true;
  }
  validatePhaseSafety(phase, gates);
  return gates;
}

function validatePhaseSafety(phase, gates = gateConfigForPhaseUnchecked(phase)) {
  for (const gate of ALWAYS_FORBIDDEN) {
    if (gates[gate] === true || (phase.requiredGates || {})[gate] === true) {
      throw new Error(`${phase.phaseId} may not enable ${gate}.`);
    }
  }
  if (gates.allowResourceVisibilityProbes && phase.phaseId !== 'multiplayer-resource-visibility-read') {
    throw new Error(`${phase.phaseId} may not enable allowResourceVisibilityProbes.`);
  }
  if (gates.allowInventoryArrayShallowProbes && phase.phaseId !== 'local-inventory-array-shallow-read') {
    throw new Error(`${phase.phaseId} may not enable allowInventoryArrayShallowProbes.`);
  }
  if (gates.allowHealthProbes && !/^health-|^multiplayer-health-/.test(phase.phaseId) && phase.phaseId !== 'multiplayer-resource-visibility-read') {
    throw new Error(`${phase.phaseId} may not enable allowHealthProbes.`);
  }
  if (gates.allowIdentityProbes && phase.phaseId !== 'multiplayer-roster-read' && phase.phaseId !== 'multiplayer-resource-visibility-read') {
    throw new Error(`${phase.phaseId} may not enable allowIdentityProbes.`);
  }
  if (gates.allowRawIdentityEvidence) {
    throw new Error(`${phase.phaseId} may not enable allowRawIdentityEvidence by default.`);
  }
  if (gates.allowInventoryInfoProbes && phase.phaseId !== 'inventoryinfo-scalar-read') {
    throw new Error(`${phase.phaseId} may not enable allowInventoryInfoProbes.`);
  }
  if (gates.allowDeepArrayProbes && !/deep|inventory-element-da-read/.test(phase.phaseId)) {
    throw new Error(`${phase.phaseId} may not enable allowDeepArrayProbes.`);
  }
  for (const gate of phase.forbiddenGates || []) {
    if (gates[gate] === true) {
      throw new Error(`${phase.phaseId} forbidden gate enabled: ${gate}.`);
    }
  }
  return true;
}

function gateConfigForPhaseUnchecked(phase) {
  const gates = {};
  for (const gate of ALL_GATES) gates[gate] = false;
  for (const [gate, value] of Object.entries(phase.requiredGates || {})) {
    gates[gate] = value === true;
  }
  return gates;
}

function evidenceFacts(repoRoot = process.cwd()) {
  const evidenceRoot = path.join(repoRoot, 'evidence', 'runtime');
  const probeFiles = walk(evidenceRoot, (name) => name === 'probe_results.jsonl');
  const accessFiles = walk(evidenceRoot, (name) => name === 'access_evidence.jsonl');
  const manifestFiles = walk(evidenceRoot, (name) => name === 'session_manifest.json');
  const summaryFiles = walk(evidenceRoot, (name) => name === 'diagnostic_summary.txt');
  const rows = [...probeFiles, ...accessFiles].flatMap(readJsonl);
  const manifests = manifestFiles.map((file) => ({ file, data: readJsonIfExists(file) })).filter((x) => x.data);
  const summaries = summaryFiles.map((file) => ({ file, values: parseKeyValueText(readTextIfExists(file)) }));
  const text = [
    ...rows.map((row) => JSON.stringify(row)),
    ...manifests.map((row) => JSON.stringify(row.data)),
    ...summaries.map((row) => Object.entries(row.values).map(([k, v]) => `${k}=${v}`).join('\n'))
  ].join('\n');
  const latestManifest = manifests
    .slice()
    .sort((a, b) => String(a.data.sessionId || '').localeCompare(String(b.data.sessionId || '')))
    .pop();
  const latestSummary = summaries
    .slice()
    .sort((a, b) => a.file.localeCompare(b.file))
    .pop();
  return {
    rows,
    manifests,
    summaries,
    text,
    latestSessionId: latestManifest ? latestManifest.data.sessionId || null : null,
    latestCommit: latestManifest && latestManifest.data.buildInfo ? latestManifest.data.buildInfo.git_commit || null : null,
    latestSummaryPath: latestSummary ? path.relative(repoRoot, latestSummary.file).replace(/\\/g, '/') : null
  };
}

function hasProbe(rows, names) {
  const wanted = new Set(names);
  return rows.some((row) => wanted.has(row.event) || wanted.has(row.probeName) || wanted.has(row.probeId));
}

function seedCompletionsFromEvidence(plan, repoRoot = process.cwd()) {
  const facts = evidenceFacts(repoRoot);
  const completed = [];
  const add = (phaseId, reason) => {
    if (plan.phases.some((phase) => phase.phaseId === phaseId)) {
      completed.push({
        phaseId,
        status: 'complete',
        completedAt: nowIso(),
        source: 'imported-evidence',
        reason,
        latestSessionId: facts.latestSessionId || '',
        latestCommit: facts.latestCommit || '',
        latestSummaryPath: facts.latestSummaryPath || ''
      });
    }
  };

  if (/Debug\.StartupSmoke|startup_smoke_appeared\s*=\s*True/i.test(facts.text)) {
    add('smoke-startup', 'Imported evidence contains startup smoke.');
  }
  if (/tickDriver["=:]\s*"?executeDelay|tick_source_registered\s*=\s*executeDelay/i.test(facts.text)) {
    add('executeDelay', 'Imported evidence contains executeDelay runtime proof.');
  }
  if (/Observe\.Context|observe_context_appeared\s*=\s*True|observe_context_count\s*=\s*[1-9]/i.test(facts.text)) {
    add('observe-context', 'Imported evidence contains Observe.Context rows.');
  }
  if (hasProbe(facts.rows, [
    'CrabPS.GetPropertyValue.WeaponDA',
    'CrabPS.GetPropertyValue.AbilityDA',
    'CrabPS.GetPropertyValue.MeleeDA'
  ])) {
    add('equipment-property-read', 'Imported evidence contains equipment property probes.');
  }
  if (hasProbe(facts.rows, [
    'CrabPS.GetPropertyValue.HealthInfo',
    'CrabPS.HealthInfo.CurrentHealth',
    'CrabPS.HealthInfo.CurrentMaxHealth',
    'CrabPS.GetPropertyValue.BaseMaxHealth',
    'CrabPS.GetPropertyValue.MaxHealthMultiplier'
  ])) {
    add('health-playerstate-read', 'Imported evidence contains PlayerState health scalar probes.');
  }
  if (hasProbe(facts.rows, ['Health.PlayerState.Sample']) || /health_playerstate_watch_sample_count\s*=\s*[1-9]/i.test(facts.text)) {
    add('health-playerstate-watch', 'Imported evidence contains PlayerState health watch samples.');
  }
  const roster = classifyRosterEvidence(facts.rows);
  if (roster.visibleRosterConfirmed) {
    add('multiplayer-roster-read', 'Imported evidence contains visible multiplayer roster identity samples.');
  }
  const resourceVisibility = classifyResourceVisibilityEvidence(facts.rows);
  if (resourceVisibility.status === 'passed') {
    add('multiplayer-resource-visibility-read', 'Imported evidence contains remote-visible multiplayer resource visibility samples.');
  }

  const partial = [];
  if (!roster.visibleRosterConfirmed && roster.localIdentityConfirmed && !roster.rawIdentityLeak) {
    const rosterCandidateRows = facts.rows.filter((row) => {
      const id = row.probeName || row.probeId || row.event || '';
      return /^Identity\./.test(id) && (
        /SourceCandidate$/.test(id) ||
        id === 'Identity.PlayerArray.Shape' ||
        id === 'Identity.FindAll.PlayerStateCandidates' ||
        id === 'Identity.PlayerControllerCandidates'
      );
    });
    partial.push({
      phaseId: 'multiplayer-roster-read',
      status: rosterCandidateRows.length > 0 ? 'roster_source_unresolved' : 'local_identity_confirmed',
      updatedAt: nowIso(),
      source: 'imported-evidence',
      reason: rosterCandidateRows.length > 0
        ? 'Local PlayerState identity read confirmed; roster source candidates were attempted but did not expose a visible multiplayer roster.'
        : 'Local PlayerState identity read confirmed; visible roster source remains unresolved.',
      latestSessionId: facts.latestSessionId || '',
      latestCommit: facts.latestCommit || '',
      latestSummaryPath: facts.latestSummaryPath || ''
    });
  }
  if (resourceVisibility.resourceVisibilityEvidenceFound && resourceVisibility.status !== 'passed' && resourceVisibility.status !== 'failed') {
    partial.push({
      phaseId: 'multiplayer-resource-visibility-read',
      status: resourceVisibility.status,
      updatedAt: nowIso(),
      source: 'imported-evidence',
      reason: resourceVisibility.status === 'local_only_evidence'
        ? 'Only one PlayerState candidate was sampled; resource fields were evaluated as local-only evidence.'
        : (resourceVisibility.status === 'remote_resources_partial'
          ? 'Multiple PlayerState candidates were sampled and some resource fields were visible remotely, but visibility was not complete.'
          : 'Multiple PlayerState candidates were sampled, but resource fields did not establish remote resource visibility.'),
      latestSessionId: facts.latestSessionId || '',
      latestCommit: facts.latestCommit || '',
      latestSummaryPath: facts.latestSummaryPath || ''
    });
  }
  const localInventory = classifyLocalInventoryArrayEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, facts.latestSessionId)
  });
  if (localInventory.status === 'passed') {
    add('local-inventory-array-shallow-read', 'Imported evidence contains local PlayerState inventory array shallow shape/count visibility.');
  } else if (localInventory.localInventoryArrayEvidenceFound && localInventory.status !== 'failed') {
    partial.push({
      phaseId: 'local-inventory-array-shallow-read',
      status: localInventory.status,
      updatedAt: nowIso(),
      source: 'imported-evidence',
      reason: localInventory.status === 'crash_suspect_local_inventory_shape_visible'
        ? 'Local inventory array fields were visible as shallow userdata shapes, but a crash dump exists after this run; keep the phase crash-suspect pending safer confirmation.'
        : 'Local PlayerState inventory array fields were nil or unsupported in shallow reads.',
      latestSessionId: facts.latestSessionId || '',
      latestCommit: facts.latestCommit || '',
      latestSummaryPath: facts.latestSummaryPath || ''
    });
  }

  return { completed, partial, facts };
}

function completedPhaseIds(state) {
  return new Set((state.completedPhases || []).map((entry) => entry.phaseId || entry));
}

function failedPhaseIds(state) {
  return new Set((state.failedPhases || []).map((entry) => entry.phaseId || entry));
}

function blockedPhaseIds(state) {
  return new Set((state.blockedPhases || []).map((entry) => entry.phaseId || entry));
}

function advanceablePartialPhaseIds(state) {
  return new Set((state.partialPhases || [])
    .filter((entry) => entry.status === 'remote_resources_partial')
    .map((entry) => entry.phaseId || entry));
}

function findNextRunnablePhase(plan, state) {
  const completed = completedPhaseIds(state);
  const failed = failedPhaseIds(state);
  const blocked = blockedPhaseIds(state);
  const advanceablePartial = advanceablePartialPhaseIds(state);
  for (const phase of plan.phases) {
    if (completed.has(phase.phaseId) || failed.has(phase.phaseId) || blocked.has(phase.phaseId) || advanceablePartial.has(phase.phaseId)) continue;
    if (phase.implemented !== true) continue;
    gateConfigForPhase(phase);
    return phase;
  }
  return null;
}

function reconcileState(plan, state = null, repoRoot = process.cwd()) {
  const existing = state || {};
  const seeded = state ? { completed: [], partial: [], facts: evidenceFacts(repoRoot) } : seedCompletionsFromEvidence(plan, repoRoot);
  const completedById = new Map();
  for (const entry of [...(seeded.completed || []), ...(existing.completedPhases || [])]) {
    const phaseId = entry.phaseId || entry;
    if (phaseId && !completedById.has(phaseId)) {
      completedById.set(phaseId, typeof entry === 'string' ? { phaseId, status: 'complete' } : entry);
    }
  }

  const partialById = new Map();
  for (const entry of [...(seeded.partial || []), ...(existing.partialPhases || [])]) {
    const phaseId = entry.phaseId || entry;
    if (phaseId && !completedById.has(phaseId) && !partialById.has(phaseId)) {
      partialById.set(phaseId, typeof entry === 'string' ? { phaseId, status: 'partial' } : entry);
    }
  }

  const blockedById = new Map();
  for (const phase of plan.phases) {
    if (phase.implemented !== true) {
      blockedById.set(phase.phaseId, {
        phaseId: phase.phaseId,
        status: 'blocked',
        reason: phase.blockedReason || 'Probe set is not implemented yet.'
      });
    }
  }
  for (const entry of existing.blockedPhases || []) {
    const phaseId = entry.phaseId || entry;
    if (phaseId) blockedById.set(phaseId, typeof entry === 'string' ? { phaseId, status: 'blocked' } : entry);
  }

  const out = {
    schemaVersion: 1,
    campaign: plan.campaign,
    planPath: PLAN_PATH.replace(/\\/g, '/'),
    createdAt: existing.createdAt || nowIso(),
    updatedAt: nowIso(),
    completedPhases: Array.from(completedById.values()),
    partialPhases: Array.from(partialById.values()),
    failedPhases: existing.failedPhases || [],
    blockedPhases: Array.from(blockedById.values()),
    currentPhase: existing.currentPhase || null,
    nextRecommendedPhase: null,
    latestSessionId: existing.latestSessionId || seeded.facts.latestSessionId || '',
    latestCommit: existing.latestCommit || seeded.facts.latestCommit || '',
    latestSummaryPath: existing.latestSummaryPath || seeded.facts.latestSummaryPath || '',
    phaseStatuses: {}
  };

  for (const phase of plan.phases) {
    out.phaseStatuses[phase.phaseId] = {
      status: 'pending',
      riskTier: phase.riskTier,
      probeSet: phase.probeSet,
      tickDriver: phase.tickDriver,
      mode: phase.mode
    };
  }
  for (const entry of out.completedPhases) out.phaseStatuses[entry.phaseId].status = 'complete';
  for (const entry of out.partialPhases) {
    if (out.phaseStatuses[entry.phaseId]) {
      out.phaseStatuses[entry.phaseId].status = entry.status || 'partial';
      out.phaseStatuses[entry.phaseId].reason = entry.reason || '';
    }
  }
  for (const entry of out.failedPhases) out.phaseStatuses[entry.phaseId].status = entry.status || 'failed';
  for (const entry of out.blockedPhases) {
    if (out.phaseStatuses[entry.phaseId]) {
      out.phaseStatuses[entry.phaseId].status = 'blocked';
      out.phaseStatuses[entry.phaseId].reason = entry.reason || '';
    }
  }
  if (out.currentPhase && out.phaseStatuses[out.currentPhase] && out.phaseStatuses[out.currentPhase].status === 'pending') {
    out.phaseStatuses[out.currentPhase].status = 'current';
  }

  const next = findNextRunnablePhase(plan, out);
  out.nextRecommendedPhase = next ? next.phaseId : null;
  return out;
}

function markPrepared(plan, state, phaseId, commit) {
  const phase = plan.phases.find((item) => item.phaseId === phaseId);
  if (!phase) throw new Error(`Unknown phase: ${phaseId}`);
  gateConfigForPhase(phase);
  const out = reconcileState(plan, state);
  out.currentPhase = phaseId;
  out.latestCommit = commit || out.latestCommit || '';
  out.updatedAt = nowIso();
  if (out.phaseStatuses[phaseId]) out.phaseStatuses[phaseId].status = 'current';
  return out;
}

function markCollected(plan, state, phaseId, result) {
  const out = reconcileState(plan, state);
  out.currentPhase = null;
  out.latestSessionId = result.latestSessionId || out.latestSessionId || '';
  out.latestCommit = result.latestCommit || out.latestCommit || '';
  out.latestSummaryPath = result.latestSummaryPath || out.latestSummaryPath || '';

  out.completedPhases = (out.completedPhases || []).filter((entry) => (entry.phaseId || entry) !== phaseId);
  out.partialPhases = (out.partialPhases || []).filter((entry) => (entry.phaseId || entry) !== phaseId);
  out.failedPhases = (out.failedPhases || []).filter((entry) => (entry.phaseId || entry) !== phaseId);

  if (result.status === 'passed') {
    out.completedPhases.push({
      phaseId,
      status: 'complete',
      completedAt: nowIso(),
      source: 'campaign-collect',
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'multiplayer-roster-read' && (result.status === 'local_identity_confirmed' || result.status === 'roster_source_unresolved')) {
    out.partialPhases.push({
      phaseId,
      status: result.status,
      updatedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || 'Local PlayerState identity read confirmed; visible roster source remains unresolved.',
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'multiplayer-resource-visibility-read' && (
    result.status === 'needs_multiplayer' ||
    result.status === 'local_only_evidence' ||
    result.status === 'remote_resources_unresolved' ||
    result.status === 'remote_resources_partial'
  )) {
    out.partialPhases.push({
      phaseId,
      status: result.status,
      updatedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || 'Resource visibility evidence is partial or unresolved.',
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'local-inventory-array-shallow-read' && (
    result.status === 'local_inventory_unresolved' ||
    result.status === 'crash_suspect_local_inventory_shape_visible'
  )) {
    out.partialPhases.push({
      phaseId,
      status: result.status,
      updatedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || (result.status === 'crash_suspect_local_inventory_shape_visible'
        ? 'Local inventory array fields were visible as shallow shapes, but a crash dump exists after this run; keep the phase crash-suspect pending safer confirmation.'
        : 'Local inventory arrays were nil or unsupported in shallow reads.'),
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else {
    out.failedPhases.push({
      phaseId,
      status: result.status || 'failed',
      failedAt: nowIso(),
      reason: result.reason || '',
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  }
  return reconcileState(plan, out);
}

function phaseStatus(state, phaseId) {
  if ((state.completedPhases || []).some((entry) => (entry.phaseId || entry) === phaseId)) return 'complete';
  const partial = (state.partialPhases || []).find((entry) => (entry.phaseId || entry) === phaseId);
  if (partial) return partial.status || 'partial';
  if ((state.failedPhases || []).some((entry) => (entry.phaseId || entry) === phaseId)) return 'failed';
  if ((state.blockedPhases || []).some((entry) => (entry.phaseId || entry) === phaseId)) return 'blocked';
  if (state.currentPhase === phaseId) return 'current';
  return 'pending';
}

function listByStatus(plan, state, status) {
  return plan.phases.filter((phase) => phaseStatus(state, phase.phaseId) === status);
}

function renderList(phases, fallback = 'None.') {
  if (!phases.length) return `- ${fallback}\n`;
  return phases.map((phase) => `- \`${phase.phaseId}\` - ${phase.label}\n`).join('');
}

function generateCampaignStatusMarkdown(plan, state, repoRoot = process.cwd()) {
  const facts = evidenceFacts(repoRoot);
  let out = '# Campaign Status\n\n';
  out += `- Campaign: \`${plan.campaign}\`\n`;
  out += `- Updated: ${state.updatedAt || nowIso()}\n`;
  out += `- Current phase: ${state.currentPhase ? `\`${state.currentPhase}\`` : 'none'}\n`;
  out += `- Next recommended phase: ${state.nextRecommendedPhase ? `\`${state.nextRecommendedPhase}\`` : 'none'}\n`;
  out += `- Latest session: ${state.latestSessionId || 'none'}\n`;
  out += `- Latest commit: ${state.latestCommit || 'none'}\n`;
  out += `- Latest summary: ${state.latestSummaryPath || 'none'}\n\n`;

  out += '## Completed Phases\n\n';
  out += renderList(listByStatus(plan, state, 'complete'));
  out += '\n## Partial Phases\n\n';
  const partial = plan.phases.filter((phase) => /^partial$|^local_identity_confirmed$|^roster_source_unresolved$|^needs_multiplayer$|^local_only_evidence$|^remote_resources_unresolved$|^remote_resources_partial$|^local_inventory_unresolved$|^crash_suspect_local_inventory_shape_visible$/.test(phaseStatus(state, phase.phaseId)));
  if (!partial.length) {
    out += '- None.\n';
  } else {
    for (const phase of partial) {
      const entry = (state.partialPhases || []).find((item) => item.phaseId === phase.phaseId) || {};
      out += `- \`${phase.phaseId}\` - ${phase.label}: ${entry.status || 'partial'}; ${entry.reason || 'partial evidence collected'}\n`;
    }
  }
  out += '\n## Failed Phases\n\n';
  out += renderList(listByStatus(plan, state, 'failed'));
  out += '\n## Blocked Phases\n\n';
  const blocked = listByStatus(plan, state, 'blocked');
  if (!blocked.length) {
    out += '- None.\n';
  } else {
    for (const phase of blocked) {
      const entry = (state.blockedPhases || []).find((item) => item.phaseId === phase.phaseId) || {};
      out += `- \`${phase.phaseId}\` - ${phase.label}: ${entry.reason || phase.blockedReason || 'blocked'}\n`;
    }
  }
  out += '\n## Pending Phases\n\n';
  out += renderList(listByStatus(plan, state, 'pending'));

  out += '\n## Confirmed Safe Paths\n\n';
  const safeSignals = [];
  if (/CrabPS\.GetPropertyValue\.WeaponDA/.test(facts.text)) safeSignals.push('`CrabPS.WeaponDA` via `GetPropertyValue`');
  if (/CrabPS\.GetPropertyValue\.AbilityDA/.test(facts.text)) safeSignals.push('`CrabPS.AbilityDA` via `GetPropertyValue`');
  if (/CrabPS\.GetPropertyValue\.MeleeDA/.test(facts.text)) safeSignals.push('`CrabPS.MeleeDA` via `GetPropertyValue`');
  if (/Health\.PlayerState\.Sample|CrabPS\.HealthInfo/.test(facts.text)) safeSignals.push('`CrabPC -> PlayerState -> CrabPS -> HealthInfo` read-only PlayerState health path');
  const roster = classifyRosterEvidence(facts.rows);
  if (roster.localIdentityConfirmed) safeSignals.push('`CrabPC -> PlayerState` local identity reads with redacted/fingerprinted identity values');
  if (roster.visibleRosterConfirmed) safeSignals.push('confirmed visible multiplayer roster reads');
  const resourceVisibility = classifyResourceVisibilityEvidence(facts.rows);
  if (resourceVisibility.status === 'passed') safeSignals.push('remote-visible multiplayer PlayerState resource reads');
  else if (resourceVisibility.remoteResourceVisible) safeSignals.push('partial remote multiplayer PlayerState resource reads for crystals, slots, equipment, and health scalars');
  const localInventory = classifyLocalInventoryArrayEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, state.latestSessionId || facts.latestSessionId)
  });
  if (localInventory.status === 'passed') safeSignals.push('local PlayerState inventory array shallow shape/count reads');
  if (!safeSignals.length) out += '- None imported yet.\n';
  else out += safeSignals.map((item) => `- ${item}\n`).join('');

  const identityRows = facts.rows.filter((row) => /^Identity\./.test(row.probeName || row.probeId || row.event || ''));
  out += '\n## Identity And Roster Notes\n\n';
  if (identityRows.length === 0) {
    out += '- No multiplayer roster identity evidence has been imported yet.\n';
    out += '- Future auto-room grouping is not ready; run `multiplayer-roster-read` before deriving grouping behavior.\n';
  } else {
    const localVisible = identityRows.some((row) => row.localPlayerPresent === true);
    const visibleCounts = identityRows.map((row) => Number(row.visiblePlayerCount)).filter((n) => Number.isFinite(n));
    const maxVisible = visibleCounts.length ? Math.max(...visibleCounts) : 0;
    const rawEnabled = hasRawIdentityLeak(identityRows, false);
    const rosterSourceResolved = hasConfirmedVisibleRosterEvidence(identityRows);
    const candidateRows = identityRows.filter((row) => {
      const id = row.probeName || row.probeId || row.event || '';
      return /SourceCandidate$/.test(id) ||
        id === 'Identity.PlayerArray.Shape' ||
        id === 'Identity.FindAll.PlayerStateCandidates' ||
        id === 'Identity.PlayerControllerCandidates';
    });
    const candidateNames = Array.from(new Set(candidateRows.map((row) => row.probeName || row.probeId || row.event).filter(Boolean))).sort();
    const playerArrayNil = identityRows.some((row) =>
      /PlayerArray/.test(row.sourcePath || '') &&
      (row.result === 'nil' || row.playerArrayValueKind === 'nil' || (row.localNotes || '').includes('not exposed as a Lua table'))
    );
    out += `- Local player identity visible: ${localVisible ? 'yes' : 'not proven'}\n`;
    out += `- Max visible player count observed: ${maxVisible}\n`;
    out += `- Any candidate exposed more than one player: ${maxVisible > 1 ? 'yes' : 'no'}\n`;
    out += `- Roster source candidates attempted: ${candidateNames.length ? candidateNames.join(', ') : 'none'}\n`;
    out += `- Visible roster source resolved: ${rosterSourceResolved ? 'yes' : 'no'}\n`;
    out += `- Raw IDs/names emitted: ${rawEnabled ? 'yes' : 'no, redacted/fingerprinted by default'}\n`;
    out += '- PlayerName and UniqueId can be fingerprinted from PlayerState identity reads without emitting raw values.\n';
    out += '- `solo-or-host` means local-player-present in the current detector; it is not proof that the run was solo and cannot distinguish true solo from multiplayer host-like local context.\n';
    if (rosterSourceResolved) {
      out += '- Visible player roster source is confirmed; future auto-room grouping still requires matched host and joined-client runs.\n';
    } else {
      out += playerArrayNil
        ? '- `GameStateBase.PlayerArray` returned nil / was not exposed as a Lua table in the latest roster evidence.\n'
        : '- `GameStateBase.PlayerArray` has not yet produced a resolved visible roster in imported evidence.\n';
      out += '- Newly attempted roster candidates should be treated as discovery evidence only until a source exposes more than one visible player or a resolved roster source.\n';
      out += '- Visible player roster remains unresolved, so future auto-room grouping is not ready.\n';
    }
  }

  out += '\n## Multiplayer Resource Visibility\n\n';
  if (!resourceVisibility.resourceVisibilityEvidenceFound) {
    out += '- Summary: unresolved; no `multiplayer-resource-visibility-read` evidence has been imported yet.\n';
    out += '- Player count sampled: 0\n';
    out += '- No raw identity values are emitted; writes, RPCs, HUD hooks, deep arrays, `InventoryInfo`, and Enhancements remain disabled.\n';
  } else {
    out += `- Summary: ${resourceVisibility.classification}\n`;
    out += `- Resource visibility class: ${resourceVisibility.status}\n`;
    out += `- Player count sampled: ${resourceVisibility.sampledPlayerStateCount}\n`;
    out += `- Fields visible across more than one PlayerState: ${resourceVisibility.fieldsVisibleAcrossMultiple.length ? resourceVisibility.fieldsVisibleAcrossMultiple.join(', ') : 'none'}\n`;
    out += `- Fields only visible on local PlayerState: ${resourceVisibility.fieldsOnlyVisibleOnLocal.length ? resourceVisibility.fieldsOnlyVisibleOnLocal.join(', ') : 'none'}\n`;
    out += `- Fields returning nil/errors: ${resourceVisibility.fieldsNilOrErrors.length ? resourceVisibility.fieldsNilOrErrors.join(', ') : 'none'}\n`;
    out += `- Readable categories by candidate: crystals=${formatReadableCount(resourceVisibility.readableCrystals, resourceVisibility.sampledPlayerStateCount)}, slots=${formatReadableCount(resourceVisibility.readableSlots, resourceVisibility.sampledPlayerStateCount)}, equipment=${formatReadableCount(resourceVisibility.readableEquipment, resourceVisibility.sampledPlayerStateCount)}, inventory array counts=${formatReadableCount(resourceVisibility.readableInventoryArrayCounts, resourceVisibility.sampledPlayerStateCount)}, health=${formatReadableCount(resourceVisibility.readableHealth, resourceVisibility.sampledPlayerStateCount)}\n`;
    out += `- Supports future P2P resource merge design: ${resourceVisibility.supportsP2PResourceMerge}\n`;
    out += '- CrabInvSync v2 implication: P2P-style merge is plausible for crystals, slots, equipment, and possibly health inputs.\n';
    out += '- Inventory item sync still needs separate research; current shallow count-only inventory array visibility is unresolved and does not expose item metadata.\n';
    out += '- An external relay/server may still be needed for inventory until array/item metadata visibility or another safe carrier is proven.\n';
    out += `- Raw IDs/names emitted: ${resourceVisibility.rawIdentityLeak ? 'yes' : 'no, redacted/fingerprinted by default'}\n`;
    out += '- No writes/RPCs/HUD hooks/deep array element reads/InventoryInfo/Enhancements are part of this phase.\n';
  }

  out += '\n## Local Inventory Array Visibility\n\n';
  if (!localInventory.localInventoryArrayEvidenceFound) {
    out += '- Summary: unresolved; no `local-inventory-array-shallow-read` evidence has been imported yet.\n';
    out += '- Local PlayerState present: not proven\n';
    out += '- Inventory item metadata remains untested; `InventoryInfo` and Enhancements remain disabled.\n';
  } else {
    out += `- Summary: ${localInventory.classification}\n`;
    out += `- Local inventory array status: ${localInventory.status}\n`;
    out += `- Local PlayerState present: ${localInventory.localPlayerStatePresent ? 'yes' : 'not proven'}\n`;
    out += `- Fields readable by shallow shape/count: ${localInventory.fieldsReadable.length ? localInventory.fieldsReadable.join(', ') : 'none'}\n`;
    out += `- Fields nil or unsupported: ${localInventory.fieldsNilOrUnsupported.length ? localInventory.fieldsNilOrUnsupported.join(', ') : 'none'}\n`;
    out += `- Array value kinds: ${Object.keys(localInventory.arrayValueKinds).length ? Object.entries(localInventory.arrayValueKinds).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Array counts available: ${localInventory.countableLuaTableFields.length ? `yes, Lua table counts for ${localInventory.countableLuaTableFields.join(', ')}` : 'no; current helper only counts Lua tables and these values were userdata shapes'}\n`;
    out += `- Slot scalar values: ${Object.keys(localInventory.slotScalarValues).length ? Object.entries(localInventory.slotScalarValues).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Array elements dereferenced: ${localInventory.noElementDereference ? 'no' : 'yes'}\n`;
    out += '- InventoryInfo and Enhancements were not read; writes/RPCs/HUD hooks/deep arrays were disabled.\n';
    out += localInventory.crashSuspect
      ? '- A crash dump exists after this run, so this path remains crash-suspect pending another safer confirmation pass.\n'
      : '- No crash dump is associated with the imported local inventory evidence.\n';
    out += '- Remote inventory array visibility remains unresolved separately.\n';
  }

  out += '\n## Confirmed Unsafe Paths\n\n';
  out += '- HUD ReceiveDrawHUD tick hook remains blocked by default.\n';
  out += '- `FindFirstOf.CrabHC` is not confirmed as a player-health source; imported evidence has seen an unscoped destructible/barrel candidate.\n';
  out += '- Writes and RPCs are disabled and are outside this campaign version.\n';

  out += '\n## Untested Paths\n\n';
  out += '- Vanilla multiplayer local PlayerState health visibility is confirmed only after `multiplayer-health-playerstate-watch` evidence exists; pooled/shared health is a CrabInvSync design concept, not vanilla RuntimeProbe evidence.\n';
  out += '- Multiplayer roster identity is only complete after visible roster evidence exists; local PlayerState identity alone is partial evidence.\n';
  out += '- Roster candidate probes currently include GameState/GameStateBase source identity, CrabGS source identity, PlayerArray shape, capped FindAll PlayerState-like candidates, capped PlayerController/CrabPC candidates, and a capped visible players source candidate.\n';
  out += '- Crystals, slots, equipment, and inventory array counts are only covered by `multiplayer-resource-visibility-read` after imported resource visibility evidence exists.\n';
  out += '- Local inventory array visibility is separate from remote PlayerState resource visibility and is covered only by `local-inventory-array-shallow-read` after imported evidence exists.\n';
  out += '- `InventoryInfo` and enhancements remain placeholders until explicit probe sets are implemented.\n';
  out += '- Deep arrays and InventoryInfo gates remain off until their explicit reviewed phases.\n';

  out += '\n## Safety Gate Summary\n\n';
  out += '- Default config remains `tickDriver = none`, `probeSet = shallow-core`, and all research gates false.\n';
  out += '- Campaign read phases never enable writes, RPCs, or HUD hooks.\n';
  out += '- `allowHealthProbes` is enabled only for explicit health phases and `multiplayer-resource-visibility-read` health scalar checks.\n';
  out += '- `allowIdentityProbes` is enabled only for the explicit multiplayer roster and resource visibility phases; `allowRawIdentityEvidence` remains false by default.\n';
  out += '- `allowResourceVisibilityProbes` is enabled only for `multiplayer-resource-visibility-read`.\n';
  out += '- `allowInventoryArrayShallowProbes` is enabled only for `local-inventory-array-shallow-read`.\n';
  out += '- `allowDeepArrayProbes` and `allowInventoryInfoProbes` are not enabled by implemented phases.\n';
  return out;
}

module.exports = {
  ALL_GATES,
  CAMPAIGN,
  DOC_PATH,
  PLAN_PATH,
  STATE_PATH,
  classifyLocalInventoryArrayEvidence,
  classifyResourceVisibilityEvidence,
  classifyRosterEvidence,
  completedPhaseIds,
  evidenceFacts,
  findNextRunnablePhase,
  gateConfigForPhase,
  generateCampaignStatusMarkdown,
  hasConfirmedVisibleRosterEvidence,
  hasCrashSuspectEvidenceForSession,
  hasLocalIdentityEvidence,
  hasNonEmptyRawIdentityValue,
  hasRawIdentityLeak,
  loadPlan,
  markCollected,
  markPrepared,
  nowIso,
  readJsonIfExists,
  reconcileState,
  seedCompletionsFromEvidence,
  validatePhaseSafety,
  writeJson
};
