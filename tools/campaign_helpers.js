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
  'allowCrystalsReadProbes',
  'allowSlotsReadProbes',
  'allowSafeScalarWatchProbes',
  'allowPerkDataAssetCatalogProbes',
  'allowInventoryArrayShallowProbes',
  'allowInventoryArrayShapeConfirmProbes',
  'allowInventoryUserdataIntrospectionProbes',
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

function isCrystalsReadRow(row) {
  return (row.probeName || row.probeId || row.event || '') === 'Resource.Crystals.Read';
}

function isFiniteIntegerLike(value) {
  if (value === null || value === undefined || value === '') return false;
  const numberValue = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(numberValue) && Math.floor(numberValue) === numberValue;
}

function classifyCrystalsReadEvidence(rows, options = {}) {
  const crystalRows = rows.filter(isCrystalsReadRow);
  const localPlayerStatePresent = crystalRows.some((row) => row.localPlayerStatePresent === true);
  const crystalsReadAttempted = crystalRows.some((row) => row.crystalsReadAttempted === true);
  const crystalsPresent = crystalRows.some((row) => row.crystalsPresent === true || row.crystalsValue !== undefined);
  const valueRows = crystalRows.filter((row) => row.crystalsPresent === true || row.crystalsValue !== undefined);
  const valueIntegerLike = valueRows.length === 0 || valueRows.every((row) =>
    row.crystalsIntegerLike === true || isFiniteIntegerLike(row.crystalsValue)
  );
  const latestValue = valueRows.length ? valueRows[valueRows.length - 1].crystalsValue : undefined;
  const forbiddenGateNames = [
    'allowHudTickHook',
    'allowUnknownRoleProbes',
    'allowJoinedClientDeepProbes',
    'allowDeepArrayProbes',
    'allowInventoryInfoProbes',
    'allowHealthProbes',
    'allowIdentityProbes',
    'allowRawIdentityEvidence',
    'allowResourceVisibilityProbes',
    'allowSlotsReadProbes',
    'allowSafeScalarWatchProbes',
    'allowPerkDataAssetCatalogProbes',
    'allowInventoryArrayShallowProbes',
    'allowInventoryArrayShapeConfirmProbes',
    'allowInventoryUserdataIntrospectionProbes',
    'allowWriteProbes',
    'allowRpcProbes'
  ];
  const safetyViolation = crystalRows.some((row) => {
    const gates = row && row.safetyGates ? row.safetyGates : {};
    return forbiddenGateNames.some((gate) => gates[gate] === true) ||
      row.noElementDereference !== true ||
      row.noArrayTraversal !== true ||
      row.noInventoryInfo !== true ||
      row.noEnhancements !== true ||
      row.noWrites !== true ||
      row.noRpcs !== true ||
      row.noHud !== true ||
      row.noDeepArrays !== true;
  });
  let status = 'no_evidence';
  let classification = 'unresolved';
  if (safetyViolation || !valueIntegerLike) {
    status = 'failed';
  } else if (crystalRows.length > 0 && localPlayerStatePresent && crystalsReadAttempted) {
    status = options.crashSuspect ? 'crash_suspect_crystals_read' : 'crystals_read_confirmed';
    classification = options.crashSuspect ? 'crystals_read_crash_suspect' : 'crystals_read_confirmed';
  }
  return {
    crystalsReadEvidenceFound: crystalRows.length > 0,
    localPlayerStatePresent,
    crystalsReadAttempted,
    crystalsPresent,
    crystalsValue: latestValue,
    valueIntegerLike,
    noElementDereference: crystalRows.length > 0 && crystalRows.every((row) => row.noElementDereference === true),
    noArrayTraversal: crystalRows.length > 0 && crystalRows.every((row) => row.noArrayTraversal === true),
    noInventoryInfo: crystalRows.length > 0 && crystalRows.every((row) => row.noInventoryInfo === true),
    noEnhancements: crystalRows.length > 0 && crystalRows.every((row) => row.noEnhancements === true),
    noWrites: crystalRows.length > 0 && crystalRows.every((row) => row.noWrites === true),
    noRpcs: crystalRows.length > 0 && crystalRows.every((row) => row.noRpcs === true),
    noHud: crystalRows.length > 0 && crystalRows.every((row) => row.noHud === true),
    noDeepArrays: crystalRows.length > 0 && crystalRows.every((row) => row.noDeepArrays === true),
    safetyViolation,
    crashSuspect: options.crashSuspect === true,
    classification,
    status
  };
}

function isSlotsReadRow(row) {
  return (row.probeName || row.probeId || row.event || '') === 'Resource.Slots.Read';
}

function objectValues(obj) {
  if (!obj || typeof obj !== 'object') return [];
  return Object.values(obj);
}

function valueInByteRange(value) {
  if (!isFiniteIntegerLike(value)) return false;
  const numberValue = typeof value === 'number' ? value : Number(value);
  return numberValue >= 0 && numberValue <= 255;
}

function classifySlotsReadEvidence(rows, options = {}) {
  const slotRows = rows.filter(isSlotsReadRow);
  const localPlayerStatePresent = slotRows.some((row) => row.localPlayerStatePresent === true);
  const slotsReadAttempted = slotRows.some((row) => row.slotsReadAttempted === true);
  const slotScalarValues = {};
  for (const row of slotRows) {
    if (row.slotScalarValues && typeof row.slotScalarValues === 'object') {
      for (const [name, value] of Object.entries(row.slotScalarValues)) {
        slotScalarValues[name] = value;
      }
    }
  }
  const presentValues = Object.values(slotScalarValues);
  const valuesIntegerLike = presentValues.every(isFiniteIntegerLike);
  const valuesInByteRange = presentValues.every(valueInByteRange);
  const forbiddenGateNames = [
    'allowHudTickHook',
    'allowUnknownRoleProbes',
    'allowJoinedClientDeepProbes',
    'allowDeepArrayProbes',
    'allowInventoryInfoProbes',
    'allowHealthProbes',
    'allowIdentityProbes',
    'allowRawIdentityEvidence',
    'allowResourceVisibilityProbes',
    'allowCrystalsReadProbes',
    'allowSafeScalarWatchProbes',
    'allowPerkDataAssetCatalogProbes',
    'allowInventoryArrayShallowProbes',
    'allowInventoryArrayShapeConfirmProbes',
    'allowInventoryUserdataIntrospectionProbes',
    'allowWriteProbes',
    'allowRpcProbes'
  ];
  const safetyViolation = slotRows.some((row) => {
    const gates = row && row.safetyGates ? row.safetyGates : {};
    return forbiddenGateNames.some((gate) => gates[gate] === true) ||
      row.noElementDereference !== true ||
      row.noArrayCount !== true ||
      row.noArrayTraversal !== true ||
      row.noInventoryInfo !== true ||
      row.noEnhancements !== true ||
      row.noWrites !== true ||
      row.noRpcs !== true ||
      row.noHud !== true ||
      row.noDeepArrays !== true;
  });
  const explicitIntegerViolation = slotRows.some((row) =>
    objectValues(row.slotIntegerLike).some((value) => value !== true)
  );
  const explicitRangeViolation = slotRows.some((row) =>
    objectValues(row.slotValuesInByteRange).some((value) => value !== true)
  );
  let status = 'no_evidence';
  let classification = 'unresolved';
  if (safetyViolation || !valuesIntegerLike || !valuesInByteRange || explicitIntegerViolation || explicitRangeViolation) {
    status = 'failed';
  } else if (slotRows.length > 0 && localPlayerStatePresent && slotsReadAttempted) {
    status = options.crashSuspect ? 'crash_suspect_slots_read' : 'slots_read_confirmed';
    classification = options.crashSuspect ? 'slots_read_crash_suspect' : 'slots_read_confirmed';
  }
  return {
    slotsReadEvidenceFound: slotRows.length > 0,
    localPlayerStatePresent,
    slotsReadAttempted,
    slotScalarValues,
    presentSlotFieldCount: presentValues.length,
    valuesIntegerLike,
    valuesInByteRange,
    lockedSlotModel: 'unresolved',
    noElementDereference: slotRows.length > 0 && slotRows.every((row) => row.noElementDereference === true),
    noArrayCount: slotRows.length > 0 && slotRows.every((row) => row.noArrayCount === true),
    noArrayTraversal: slotRows.length > 0 && slotRows.every((row) => row.noArrayTraversal === true),
    noInventoryInfo: slotRows.length > 0 && slotRows.every((row) => row.noInventoryInfo === true),
    noEnhancements: slotRows.length > 0 && slotRows.every((row) => row.noEnhancements === true),
    noWrites: slotRows.length > 0 && slotRows.every((row) => row.noWrites === true),
    noRpcs: slotRows.length > 0 && slotRows.every((row) => row.noRpcs === true),
    noHud: slotRows.length > 0 && slotRows.every((row) => row.noHud === true),
    noDeepArrays: slotRows.length > 0 && slotRows.every((row) => row.noDeepArrays === true),
    safetyViolation,
    crashSuspect: options.crashSuspect === true,
    classification,
    status
  };
}

function isSafeScalarWatchRow(row) {
  const id = row.probeName || row.probeId || row.event || '';
  return id === 'SafeWatch.Scalar.Sample' || id === 'Runtime.SafeScalarWatch.Sample';
}

function arrayFromValue(value) {
  if (Array.isArray(value)) return value;
  if (value === null || value === undefined) return [];
  return [value];
}

function classifySafeScalarWatchEvidence(rows, options = {}) {
  const watchRows = rows.filter(isSafeScalarWatchRow);
  const latest = watchRows.length ? watchRows[watchRows.length - 1] : {};
  const sampleCount = Number(latest.safeWatchSampleCount || watchRows.length || 0);
  const loggedCount = Number(latest.safeWatchLoggedCount || watchRows.length || 0);
  const usableSampleCount = watchRows.filter((row) => row.playerStatePresent === true || row.localPlayerStatePresent === true).length;
  const changedFields = arrayFromValue(latest.safeWatchChangedFields).filter((item) => String(item || '').trim() !== '');
  const forbiddenGateNames = [
    'allowHudTickHook',
    'allowUnknownRoleProbes',
    'allowJoinedClientDeepProbes',
    'allowDeepArrayProbes',
    'allowInventoryInfoProbes',
    'allowHealthProbes',
    'allowIdentityProbes',
    'allowRawIdentityEvidence',
    'allowResourceVisibilityProbes',
    'allowCrystalsReadProbes',
    'allowSlotsReadProbes',
    'allowPerkDataAssetCatalogProbes',
    'allowInventoryArrayShallowProbes',
    'allowInventoryArrayShapeConfirmProbes',
    'allowInventoryUserdataIntrospectionProbes',
    'allowWriteProbes',
    'allowRpcProbes'
  ];
  const safetyViolation = watchRows.some((row) => {
    const gates = row && row.safetyGates ? row.safetyGates : {};
    return forbiddenGateNames.some((gate) => gates[gate] === true) ||
      row.noElementDereference !== true ||
      row.noArrayCount !== true ||
      row.noArrayTraversal !== true ||
      row.noInventoryInfo !== true ||
      row.noEnhancements !== true ||
      row.noWrites !== true ||
      row.noRpcs !== true ||
      row.noHud !== true ||
      row.noDeepArrays !== true;
  });
  let status = 'no_evidence';
  let classification = 'unresolved';
  if (safetyViolation) {
    status = 'failed';
    classification = 'failed';
  } else if (watchRows.length > 0 && usableSampleCount > 0 && options.crashSuspect) {
    status = 'crash_suspect_safe_scalar_watch';
    classification = 'crash-suspect';
  } else if (watchRows.length > 0 && usableSampleCount > 0 && changedFields.length > 0) {
    status = 'safe_scalar_watch_observed_change';
    classification = 'safe_scalar_watch_observed_change';
  } else if (watchRows.length > 0 && usableSampleCount > 0 && sampleCount > 1) {
    status = 'safe_scalar_watch_confirmed_no_change';
    classification = 'safe_scalar_watch_confirmed_no_change';
  }
  return {
    safeScalarWatchEvidenceFound: watchRows.length > 0,
    sampleCount,
    loggedCount,
    usableSampleCount,
    firstValues: latest.safeWatchFirstValues || {},
    latestValues: latest.safeWatchLatestValues || {},
    minValues: latest.safeWatchMinValues || {},
    maxValues: latest.safeWatchMaxValues || {},
    changedFields,
    changeCounts: latest.safeWatchChangeCounts || {},
    firstContext: latest.firstContext || '',
    lastContext: latest.lastContext || '',
    firstRole: latest.firstRole || '',
    lastRole: latest.lastRole || '',
    slotModelStatus: 'observed scalar slot counters / candidate unlocked or usable slot counters; locked/max/total slot model unresolved',
    noElementDereference: watchRows.length > 0 && watchRows.every((row) => row.noElementDereference === true),
    noArrayCount: watchRows.length > 0 && watchRows.every((row) => row.noArrayCount === true),
    noArrayTraversal: watchRows.length > 0 && watchRows.every((row) => row.noArrayTraversal === true),
    noInventoryInfo: watchRows.length > 0 && watchRows.every((row) => row.noInventoryInfo === true),
    noEnhancements: watchRows.length > 0 && watchRows.every((row) => row.noEnhancements === true),
    noWrites: watchRows.length > 0 && watchRows.every((row) => row.noWrites === true),
    noRpcs: watchRows.length > 0 && watchRows.every((row) => row.noRpcs === true),
    noHud: watchRows.length > 0 && watchRows.every((row) => row.noHud === true),
    noDeepArrays: watchRows.length > 0 && watchRows.every((row) => row.noDeepArrays === true),
    safetyViolation,
    crashSuspect: options.crashSuspect === true,
    classification,
    status
  };
}

function isPerkDataAssetCatalogRow(row) {
  const id = row.probeName || row.probeId || row.event || '';
  return id === 'DataAsset.Perks.CatalogRead';
}

function classifyPerkDataAssetCatalogEvidence(rows, options = {}) {
  const catalogRows = rows.filter(isPerkDataAssetCatalogRow);
  const latest = catalogRows.length ? catalogRows[catalogRows.length - 1] : {};
  const catalogEntryCount = Math.max(0, ...catalogRows.map((row) => rowNumber(row, 'catalogEntryCount')));
  const catalogCandidateCount = Math.max(0, ...catalogRows.map((row) => rowNumber(row, 'catalogCandidateCount')));
  const discoveryAttempted = catalogRows.some((row) => row.discoveryAttempted === true);
  const catalogFound = catalogRows.some((row) => row.catalogFound === true || rowNumber(row, 'catalogEntryCount') > 0);
  const forbiddenGateNames = [
    'allowHudTickHook',
    'allowUnknownRoleProbes',
    'allowJoinedClientDeepProbes',
    'allowDeepArrayProbes',
    'allowInventoryInfoProbes',
    'allowHealthProbes',
    'allowIdentityProbes',
    'allowRawIdentityEvidence',
    'allowResourceVisibilityProbes',
    'allowCrystalsReadProbes',
    'allowSlotsReadProbes',
    'allowSafeScalarWatchProbes',
    'allowInventoryArrayShallowProbes',
    'allowInventoryArrayShapeConfirmProbes',
    'allowInventoryUserdataIntrospectionProbes',
    'allowWriteProbes',
    'allowRpcProbes'
  ];
  const safetyViolation = catalogRows.some((row) => {
    const gates = row && row.safetyGates ? row.safetyGates : {};
    return forbiddenGateNames.some((gate) => gates[gate] === true) ||
      gates.allowPerkDataAssetCatalogProbes !== true ||
      row.noWrites !== true ||
      row.noRpcs !== true ||
      row.noHud !== true ||
      row.noDeepArrays !== true ||
      row.noInventoryArrays !== true ||
      row.noArrayCount !== true ||
      row.noArrayTraversal !== true ||
      row.noElementDereference !== true ||
      row.noInventoryInfo !== true ||
      row.noEnhancements !== true ||
      row.noDataAssetMutation !== true ||
      row.noFunctionCalls !== true;
  });
  let status = 'no_evidence';
  let classification = 'unresolved';
  if (safetyViolation) {
    status = 'failed';
    classification = 'failed';
  } else if (catalogRows.length > 0 && discoveryAttempted && options.crashSuspect) {
    status = 'crash_suspect_perk_da_catalog_read';
    classification = 'perk_da_catalog_crash_suspect';
  } else if (catalogRows.length > 0 && discoveryAttempted && catalogFound) {
    status = 'perk_da_catalog_confirmed';
    classification = 'perk_da_catalog_confirmed';
  } else if (catalogRows.length > 0 && discoveryAttempted) {
    status = 'perk_da_catalog_not_found';
    classification = 'perk_da_catalog_not_found';
  }
  return {
    perkDataAssetCatalogEvidenceFound: catalogRows.length > 0,
    discoveryAttempted,
    catalogFound,
    catalogEntryCount,
    catalogCandidateCount,
    catalogCandidateCap: latest.catalogCandidateCap || 0,
    catalogFieldCap: latest.catalogFieldCap || 0,
    catalogEntries: latest.catalogEntries || [],
    catalogFieldNames: latest.catalogFieldNames || [],
    catalogReadStatuses: latest.catalogReadStatuses || {},
    catalogValueKinds: latest.catalogValueKinds || {},
    noWrites: catalogRows.length > 0 && catalogRows.every((row) => row.noWrites === true),
    noRpcs: catalogRows.length > 0 && catalogRows.every((row) => row.noRpcs === true),
    noHud: catalogRows.length > 0 && catalogRows.every((row) => row.noHud === true),
    noDeepArrays: catalogRows.length > 0 && catalogRows.every((row) => row.noDeepArrays === true),
    noInventoryArrays: catalogRows.length > 0 && catalogRows.every((row) => row.noInventoryArrays === true),
    noArrayCount: catalogRows.length > 0 && catalogRows.every((row) => row.noArrayCount === true),
    noArrayTraversal: catalogRows.length > 0 && catalogRows.every((row) => row.noArrayTraversal === true),
    noElementDereference: catalogRows.length > 0 && catalogRows.every((row) => row.noElementDereference === true),
    noInventoryInfo: catalogRows.length > 0 && catalogRows.every((row) => row.noInventoryInfo === true),
    noEnhancements: catalogRows.length > 0 && catalogRows.every((row) => row.noEnhancements === true),
    noDataAssetMutation: catalogRows.length > 0 && catalogRows.every((row) => row.noDataAssetMutation === true),
    noFunctionCalls: catalogRows.length > 0 && catalogRows.every((row) => row.noFunctionCalls === true),
    safetyViolation,
    crashSuspect: options.crashSuspect === true,
    classification,
    status
  };
}

function isLocalInventoryArrayRow(row) {
  const id = row.probeName || row.probeId || row.event || '';
  return /^Inventory\.Local(Arrays|Slots)\./.test(id) &&
    id !== 'Inventory.LocalArrays.ShapeConfirm' &&
    id !== 'Inventory.LocalArrays.UserdataIntrospection';
}

function isLocalInventoryArrayShapeConfirmRow(row) {
  return (row.probeName || row.probeId || row.event || '') === 'Inventory.LocalArrays.ShapeConfirm';
}

function isLocalInventoryUserdataIntrospectionRow(row) {
  return (row.probeName || row.probeId || row.event || '') === 'Inventory.LocalArrays.UserdataIntrospection';
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
      gates.allowCrystalsReadProbes === true ||
      gates.allowSlotsReadProbes === true ||
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

function classifyLocalInventoryArrayShapeConfirmEvidence(rows, options = {}) {
  const confirmRows = rows.filter(isLocalInventoryArrayShapeConfirmRow);
  const fieldsReadable = Array.from(new Set(confirmRows.flatMap((row) => flattenStringList(row.fieldsReadable)))).sort();
  const fieldsNilOrUnsupported = Array.from(new Set(confirmRows.flatMap((row) => flattenStringList(row.fieldsNilOrUnsupported)))).sort();
  const localPlayerStatePresent = confirmRows.some((row) => row.localPlayerStatePresent === true);
  const arrayValueKinds = {};
  const arrayPropertiesPresent = {};
  const arrayTostringKinds = {};
  const slotScalarValues = {};
  const fieldResults = {};
  for (const row of confirmRows) {
    if (row.arrayValueKinds && typeof row.arrayValueKinds === 'object') {
      for (const [name, value] of Object.entries(row.arrayValueKinds)) arrayValueKinds[name] = String(value);
    }
    if (row.arrayPropertiesPresent && typeof row.arrayPropertiesPresent === 'object') {
      for (const [name, value] of Object.entries(row.arrayPropertiesPresent)) arrayPropertiesPresent[name] = value === true;
    }
    if (row.arrayTostringKinds && typeof row.arrayTostringKinds === 'object') {
      for (const [name, value] of Object.entries(row.arrayTostringKinds)) arrayTostringKinds[name] = String(value);
    }
    if (row.slotScalarValues && typeof row.slotScalarValues === 'object') {
      for (const [name, value] of Object.entries(row.slotScalarValues)) slotScalarValues[name] = value;
    }
    if (row.fieldResults && typeof row.fieldResults === 'object') {
      for (const [name, value] of Object.entries(row.fieldResults)) fieldResults[name] = String(value);
    }
  }
  const forbiddenGateNames = [
    'allowInventoryArrayShallowProbes',
    'allowDeepArrayProbes',
    'allowInventoryInfoProbes',
    'allowWriteProbes',
    'allowRpcProbes',
    'allowHudTickHook',
    'allowRawIdentityEvidence',
    'allowHealthProbes',
    'allowIdentityProbes',
    'allowResourceVisibilityProbes',
    'allowCrystalsReadProbes',
    'allowSlotsReadProbes',
    'allowPerkDataAssetCatalogProbes',
    'allowUnknownRoleProbes',
    'allowJoinedClientDeepProbes',
    'allowInventoryUserdataIntrospectionProbes'
  ];
  const safetyViolation = confirmRows.some((row) => {
    const gates = row && row.safetyGates ? row.safetyGates : {};
    return forbiddenGateNames.some((gate) => gates[gate] === true) ||
      row.noElementDereference !== true ||
      row.noArrayCount !== true ||
      row.noArrayTraversal !== true ||
      row.noInventoryInfo !== true ||
      row.noEnhancements !== true;
  });
  const hasShapeEvidence = confirmRows.length > 0 && (
    fieldsReadable.length > 0 ||
    Object.keys(arrayValueKinds).length > 0 ||
    Object.keys(arrayPropertiesPresent).length > 0 ||
    localPlayerStatePresent
  );
  let status = 'no_evidence';
  let classification = 'unresolved';
  if (safetyViolation) {
    status = 'failed';
  } else if (hasShapeEvidence) {
    status = options.crashSuspect ? 'crash_suspect_local_inventory_shape_confirmed' : 'local_inventory_shape_confirmed';
    classification = options.crashSuspect ? 'local_inventory_shape_confirmed_crash_suspect' : 'local_inventory_shape_confirmed';
  }
  return {
    localInventoryShapeConfirmEvidenceFound: confirmRows.length > 0,
    localPlayerStatePresent,
    fieldsReadable,
    fieldsNilOrUnsupported,
    arrayValueKinds,
    arrayPropertiesPresent,
    arrayTostringKinds,
    slotScalarValues,
    fieldResults,
    noElementDereference: confirmRows.length > 0 && confirmRows.every((row) => row.noElementDereference === true),
    noArrayCount: confirmRows.length > 0 && confirmRows.every((row) => row.noArrayCount === true),
    noArrayTraversal: confirmRows.length > 0 && confirmRows.every((row) => row.noArrayTraversal === true),
    noInventoryInfo: confirmRows.length > 0 && confirmRows.every((row) => row.noInventoryInfo === true),
    noEnhancements: confirmRows.length > 0 && confirmRows.every((row) => row.noEnhancements === true),
    safetyViolation,
    crashSuspect: options.crashSuspect === true,
    classification,
    status
  };
}

function classifyLocalInventoryUserdataIntrospectionEvidence(rows, options = {}) {
  const introspectionRows = rows.filter(isLocalInventoryUserdataIntrospectionRow);
  const fieldsReadable = Array.from(new Set(introspectionRows.flatMap((row) => flattenStringList(row.fieldsReadable)))).sort();
  const fieldsNilOrUnsupported = Array.from(new Set(introspectionRows.flatMap((row) => flattenStringList(row.fieldsNilOrUnsupported)))).sort();
  const localPlayerStatePresent = introspectionRows.some((row) => row.localPlayerStatePresent === true);
  const valueKinds = {};
  const tostringKinds = {};
  const tostringPrefixes = {};
  const metatableKinds = {};
  const metatableKeys = {};
  const lenOperatorAttempted = {};
  const lenOperatorResults = {};
  const lenOperatorErrors = {};
  const fieldResults = {};
  for (const row of introspectionRows) {
    for (const [target, source] of [
      [valueKinds, row.valueKinds],
      [tostringKinds, row.tostringKinds],
      [tostringPrefixes, row.tostringPrefixes],
      [metatableKinds, row.metatableKinds],
      [lenOperatorResults, row.lenOperatorResults],
      [lenOperatorErrors, row.lenOperatorErrors],
      [fieldResults, row.fieldResults]
    ]) {
      if (source && typeof source === 'object') {
        for (const [name, value] of Object.entries(source)) target[name] = String(value);
      }
    }
    if (row.metatableKeys && typeof row.metatableKeys === 'object') {
      for (const [name, value] of Object.entries(row.metatableKeys)) metatableKeys[name] = flattenStringList(value).slice(0, 16);
    }
    if (row.lenOperatorAttempted && typeof row.lenOperatorAttempted === 'object') {
      for (const [name, value] of Object.entries(row.lenOperatorAttempted)) lenOperatorAttempted[name] = value === true;
    }
  }
  const forbiddenGateNames = [
    'allowInventoryArrayShapeConfirmProbes',
    'allowInventoryArrayShallowProbes',
    'allowDeepArrayProbes',
    'allowInventoryInfoProbes',
    'allowWriteProbes',
    'allowRpcProbes',
    'allowHudTickHook',
    'allowRawIdentityEvidence',
    'allowHealthProbes',
    'allowIdentityProbes',
    'allowResourceVisibilityProbes',
    'allowCrystalsReadProbes',
    'allowSlotsReadProbes',
    'allowPerkDataAssetCatalogProbes',
    'allowUnknownRoleProbes',
    'allowJoinedClientDeepProbes'
  ];
  const safetyViolation = introspectionRows.some((row) => {
    const gates = row && row.safetyGates ? row.safetyGates : {};
    return forbiddenGateNames.some((gate) => gates[gate] === true) ||
      row.noElementDereference !== true ||
      row.noArrayTraversal !== true ||
      row.noInventoryInfo !== true ||
      row.noEnhancements !== true ||
      row.noWrites !== true ||
      row.noRpcs !== true ||
      row.noHud !== true ||
      row.noDeepArrays !== true;
  });
  const hasMetadataEvidence = introspectionRows.length > 0 && (
    fieldsReadable.length > 0 ||
    Object.keys(valueKinds).length > 0 ||
    Object.keys(tostringKinds).length > 0 ||
    Object.keys(metatableKinds).length > 0 ||
    Object.keys(lenOperatorAttempted).length > 0 ||
    localPlayerStatePresent
  );
  let status = 'no_evidence';
  let classification = 'unresolved';
  if (safetyViolation) {
    status = 'failed';
  } else if (hasMetadataEvidence) {
    status = options.crashSuspect ? 'crash_suspect_local_inventory_userdata_introspection' : 'local_inventory_userdata_introspection_confirmed';
    classification = options.crashSuspect ? 'local_inventory_userdata_introspection_crash_suspect' : 'local_inventory_userdata_introspection_confirmed';
  }
  return {
    localInventoryUserdataIntrospectionEvidenceFound: introspectionRows.length > 0,
    localPlayerStatePresent,
    fieldsReadable,
    fieldsNilOrUnsupported,
    valueKinds,
    tostringKinds,
    tostringPrefixes,
    metatableKinds,
    metatableKeys,
    lenOperatorAttempted,
    lenOperatorResults,
    lenOperatorErrors,
    fieldResults,
    noElementDereference: introspectionRows.length > 0 && introspectionRows.every((row) => row.noElementDereference === true),
    noArrayTraversal: introspectionRows.length > 0 && introspectionRows.every((row) => row.noArrayTraversal === true),
    noInventoryInfo: introspectionRows.length > 0 && introspectionRows.every((row) => row.noInventoryInfo === true),
    noEnhancements: introspectionRows.length > 0 && introspectionRows.every((row) => row.noEnhancements === true),
    noWrites: introspectionRows.length > 0 && introspectionRows.every((row) => row.noWrites === true),
    noRpcs: introspectionRows.length > 0 && introspectionRows.every((row) => row.noRpcs === true),
    noHud: introspectionRows.length > 0 && introspectionRows.every((row) => row.noHud === true),
    noDeepArrays: introspectionRows.length > 0 && introspectionRows.every((row) => row.noDeepArrays === true),
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
  const crashEvidencePattern = '(?:crash_after_prepare\\s*=\\s*True|crash_suspect\\s*=\\s*True|crash_dump_uploaded\\s*=|crash_\\d{4}_\\d{2}_\\d{2}_[^\\s"]*\\.dmp|\\.mdmp)';
  if (escapedSessionId) {
    const sessionMentioned = new RegExp(escapedSessionId, 'i').test(text);
    const sessionCrashPattern = new RegExp(`${escapedSessionId}[\\s\\S]{0,5000}${crashEvidencePattern}`, 'i');
    if (sessionMentioned) return sessionCrashPattern.test(text);
  }
  return new RegExp(crashEvidencePattern, 'i').test(text);
}

function latestSessionIdForRows(rows, predicate) {
  return rows
    .filter(predicate)
    .map((row) => row.sessionId)
    .filter(Boolean)
    .sort()
    .pop() || null;
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
  if (gates.allowCrystalsReadProbes && phase.phaseId !== 'crystals-read') {
    throw new Error(`${phase.phaseId} may not enable allowCrystalsReadProbes.`);
  }
  if (gates.allowSlotsReadProbes && phase.phaseId !== 'slots-read') {
    throw new Error(`${phase.phaseId} may not enable allowSlotsReadProbes.`);
  }
  if (gates.allowSafeScalarWatchProbes && phase.phaseId !== 'safe-scalar-watch') {
    throw new Error(`${phase.phaseId} may not enable allowSafeScalarWatchProbes.`);
  }
  if (gates.allowPerkDataAssetCatalogProbes && phase.phaseId !== 'perk-da-catalog-read') {
    throw new Error(`${phase.phaseId} may not enable allowPerkDataAssetCatalogProbes.`);
  }
  if (gates.allowInventoryArrayShallowProbes && phase.phaseId !== 'local-inventory-array-shallow-read') {
    throw new Error(`${phase.phaseId} may not enable allowInventoryArrayShallowProbes.`);
  }
  if (gates.allowInventoryArrayShapeConfirmProbes && phase.phaseId !== 'local-inventory-array-shape-confirm') {
    throw new Error(`${phase.phaseId} may not enable allowInventoryArrayShapeConfirmProbes.`);
  }
  if (gates.allowInventoryUserdataIntrospectionProbes && phase.phaseId !== 'local-inventory-userdata-introspection') {
    throw new Error(`${phase.phaseId} may not enable allowInventoryUserdataIntrospectionProbes.`);
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
  const localInventorySessionId = latestSessionIdForRows(facts.rows, isLocalInventoryArrayRow);
  const localInventory = classifyLocalInventoryArrayEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, localInventorySessionId)
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
      latestSessionId: localInventorySessionId || facts.latestSessionId || '',
      latestCommit: facts.latestCommit || '',
      latestSummaryPath: facts.latestSummaryPath || ''
    });
  }
  const localInventoryShapeConfirmSessionId = latestSessionIdForRows(facts.rows, isLocalInventoryArrayShapeConfirmRow);
  const localInventoryShapeConfirm = classifyLocalInventoryArrayShapeConfirmEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, localInventoryShapeConfirmSessionId)
  });
  if (localInventoryShapeConfirm.status === 'local_inventory_shape_confirmed') {
    add('local-inventory-array-shape-confirm', 'Imported evidence contains local PlayerState inventory array property shape confirmation with no count, traversal, or element dereference.');
  } else if (localInventoryShapeConfirm.localInventoryShapeConfirmEvidenceFound && localInventoryShapeConfirm.status !== 'failed') {
    partial.push({
      phaseId: 'local-inventory-array-shape-confirm',
      status: localInventoryShapeConfirm.status,
      updatedAt: nowIso(),
      source: 'imported-evidence',
      reason: localInventoryShapeConfirm.status === 'crash_suspect_local_inventory_shape_confirmed'
        ? 'Local inventory array fields were confirmed as property shapes with no count, traversal, or element dereference, but a crash dump exists after this run; keep the phase crash-suspect pending another safer confirmation.'
        : 'Local inventory array shape confirmation did not produce usable evidence.',
      latestSessionId: localInventoryShapeConfirmSessionId || facts.latestSessionId || '',
      latestCommit: facts.latestCommit || '',
      latestSummaryPath: facts.latestSummaryPath || ''
    });
  }
  const localInventoryUserdataIntrospectionSessionId = latestSessionIdForRows(facts.rows, isLocalInventoryUserdataIntrospectionRow);
  const localInventoryUserdataIntrospection = classifyLocalInventoryUserdataIntrospectionEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, localInventoryUserdataIntrospectionSessionId)
  });
  if (localInventoryUserdataIntrospection.status === 'local_inventory_userdata_introspection_confirmed') {
    add('local-inventory-userdata-introspection', 'Imported evidence contains local PlayerState inventory userdata wrapper metadata with no traversal or element dereference.');
  } else if (localInventoryUserdataIntrospection.localInventoryUserdataIntrospectionEvidenceFound && localInventoryUserdataIntrospection.status !== 'failed') {
    partial.push({
      phaseId: 'local-inventory-userdata-introspection',
      status: localInventoryUserdataIntrospection.status,
      updatedAt: nowIso(),
      source: 'imported-evidence',
      reason: localInventoryUserdataIntrospection.status === 'crash_suspect_local_inventory_userdata_introspection'
        ? 'Local inventory userdata wrapper metadata was collected without traversal or element dereference, but a crash dump exists after this run.'
        : 'Local inventory userdata introspection did not produce usable metadata evidence.',
      latestSessionId: localInventoryUserdataIntrospectionSessionId || facts.latestSessionId || '',
      latestCommit: facts.latestCommit || '',
      latestSummaryPath: facts.latestSummaryPath || ''
    });
  }
  const crystalsReadSessionId = latestSessionIdForRows(facts.rows, isCrystalsReadRow);
  const crystalsRead = classifyCrystalsReadEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, crystalsReadSessionId)
  });
  if (crystalsRead.status === 'crystals_read_confirmed') {
    add('crystals-read', 'Imported evidence contains local PlayerState Crystals scalar read with no writes, RPCs, HUD, inventory arrays, InventoryInfo, Enhancements, or deep arrays.');
  } else if (crystalsRead.crystalsReadEvidenceFound && crystalsRead.status !== 'failed') {
    partial.push({
      phaseId: 'crystals-read',
      status: crystalsRead.status,
      updatedAt: nowIso(),
      source: 'imported-evidence',
      reason: crystalsRead.status === 'crash_suspect_crystals_read'
        ? 'Local PlayerState Crystals scalar was read safely, but a crash dump exists after this run.'
        : 'Crystals read did not produce usable evidence.',
      latestSessionId: crystalsReadSessionId || facts.latestSessionId || '',
      latestCommit: facts.latestCommit || '',
      latestSummaryPath: facts.latestSummaryPath || ''
    });
  }
  const slotsReadSessionId = latestSessionIdForRows(facts.rows, isSlotsReadRow);
  const slotsRead = classifySlotsReadEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, slotsReadSessionId)
  });
  if (slotsRead.status === 'slots_read_confirmed') {
    add('slots-read', 'Imported evidence contains local PlayerState candidate slot scalar reads with no writes, RPCs, HUD, inventory arrays, InventoryInfo, Enhancements, or deep arrays.');
  } else if (slotsRead.slotsReadEvidenceFound && slotsRead.status !== 'failed') {
    partial.push({
      phaseId: 'slots-read',
      status: slotsRead.status,
      updatedAt: nowIso(),
      source: 'imported-evidence',
      reason: slotsRead.status === 'crash_suspect_slots_read'
        ? 'Local PlayerState slot scalars were read safely, but a crash dump exists after this run.'
        : 'Slots read did not produce usable evidence.',
      latestSessionId: slotsReadSessionId || facts.latestSessionId || '',
      latestCommit: facts.latestCommit || '',
      latestSummaryPath: facts.latestSummaryPath || ''
    });
  }
  const safeScalarWatchSessionId = latestSessionIdForRows(facts.rows, isSafeScalarWatchRow);
  const safeScalarWatch = classifySafeScalarWatchEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, safeScalarWatchSessionId)
  });
  if (safeScalarWatch.status === 'safe_scalar_watch_confirmed_no_change' || safeScalarWatch.status === 'safe_scalar_watch_observed_change') {
    add('safe-scalar-watch', 'Imported evidence contains safe scalar watch samples over already proven local scalar/property paths with no writes, RPCs, HUD, inventory arrays, InventoryInfo, Enhancements, or deep arrays.');
  } else if (safeScalarWatch.safeScalarWatchEvidenceFound && safeScalarWatch.status !== 'failed') {
    partial.push({
      phaseId: 'safe-scalar-watch',
      status: safeScalarWatch.status,
      updatedAt: nowIso(),
      source: 'imported-evidence',
      reason: safeScalarWatch.status === 'crash_suspect_safe_scalar_watch'
        ? 'Safe scalar watch collected samples, but a crash dump exists after this run.'
        : 'Safe scalar watch did not produce usable multi-sample or changed-value evidence.',
      latestSessionId: safeScalarWatchSessionId || facts.latestSessionId || '',
      latestCommit: facts.latestCommit || '',
      latestSummaryPath: facts.latestSummaryPath || ''
    });
  }
  const perkCatalogSessionId = latestSessionIdForRows(facts.rows, isPerkDataAssetCatalogRow);
  const perkCatalog = classifyPerkDataAssetCatalogEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, perkCatalogSessionId)
  });
  if (perkCatalog.status === 'perk_da_catalog_confirmed') {
    add('perk-da-catalog-read', 'Imported evidence contains read-only perk DataAsset catalog entries with no writes, RPCs, HUD, inventory arrays, InventoryInfo, Enhancements, DataAsset mutation, or nested object walking.');
  } else if (perkCatalog.perkDataAssetCatalogEvidenceFound && perkCatalog.status !== 'failed') {
    partial.push({
      phaseId: 'perk-da-catalog-read',
      status: perkCatalog.status,
      updatedAt: nowIso(),
      source: 'imported-evidence',
      reason: perkCatalog.status === 'crash_suspect_perk_da_catalog_read'
        ? 'Perk DataAsset catalog discovery ran, but a crash dump exists after this run.'
        : 'Perk DataAsset catalog discovery ran safely but found no perk DataAssets.',
      latestSessionId: perkCatalogSessionId || facts.latestSessionId || '',
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
    .filter((entry) => entry.status === 'remote_resources_partial' || entry.status === 'crash_suspect_local_inventory_shape_visible' || entry.status === 'perk_da_catalog_not_found')
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

function findNextRecommendedPhase(plan, state) {
  const completed = completedPhaseIds(state);
  const failed = failedPhaseIds(state);
  const advanceablePartial = advanceablePartialPhaseIds(state);
  for (const phase of plan.phases) {
    if (completed.has(phase.phaseId) || failed.has(phase.phaseId) || advanceablePartial.has(phase.phaseId)) continue;
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
    const phase = plan.phases.find((item) => item.phaseId === phaseId);
    if (phaseId && (!phase || phase.implemented !== true)) {
      blockedById.set(phaseId, typeof entry === 'string' ? { phaseId, status: 'blocked' } : entry);
    }
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

  const next = findNextRecommendedPhase(plan, out) || findNextRunnablePhase(plan, out);
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
  } else if (phaseId === 'local-inventory-array-shape-confirm' && result.status === 'local_inventory_shape_confirmed') {
    out.completedPhases.push({
      phaseId,
      status: 'complete',
      completedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || 'Local inventory array property shapes were confirmed with no count, traversal, or element dereference.',
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'local-inventory-userdata-introspection' && result.status === 'local_inventory_userdata_introspection_confirmed') {
    out.completedPhases.push({
      phaseId,
      status: 'complete',
      completedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || 'Local inventory userdata wrapper metadata was collected with no traversal or element dereference.',
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'crystals-read' && result.status === 'crystals_read_confirmed') {
    out.completedPhases.push({
      phaseId,
      status: 'complete',
      completedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || 'Local PlayerState Crystals scalar was read with no writes, RPCs, HUD, inventory arrays, InventoryInfo, Enhancements, or deep arrays.',
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'slots-read' && result.status === 'slots_read_confirmed') {
    out.completedPhases.push({
      phaseId,
      status: 'complete',
      completedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || 'Local PlayerState candidate slot scalars were read with no writes, RPCs, HUD, inventory arrays, InventoryInfo, Enhancements, or deep arrays.',
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'safe-scalar-watch' && (result.status === 'safe_scalar_watch_confirmed_no_change' || result.status === 'safe_scalar_watch_observed_change')) {
    out.completedPhases.push({
      phaseId,
      status: 'complete',
      completedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || 'Safe scalar watch sampled already proven local scalar/property paths with no writes, RPCs, HUD, inventory arrays, InventoryInfo, Enhancements, or deep arrays.',
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'perk-da-catalog-read' && result.status === 'perk_da_catalog_confirmed') {
    out.completedPhases.push({
      phaseId,
      status: 'complete',
      completedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || 'Perk DataAsset catalog entries were read through capped curated discovery with no writes, RPCs, HUD, inventory arrays, InventoryInfo, Enhancements, DataAsset mutation, or nested object walking.',
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
  } else if (phaseId === 'local-inventory-array-shape-confirm' && (
    result.status === 'crash_suspect_local_inventory_shape_confirmed' ||
    result.status === 'no_evidence'
  )) {
    out.partialPhases.push({
      phaseId,
      status: result.status,
      updatedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || (result.status === 'crash_suspect_local_inventory_shape_confirmed'
        ? 'Local inventory array fields were confirmed as property shapes with no count, traversal, or element dereference, but crash evidence exists after this run.'
        : 'No local inventory shape-confirm evidence was found.'),
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'local-inventory-userdata-introspection' && (
    result.status === 'crash_suspect_local_inventory_userdata_introspection' ||
    result.status === 'no_evidence'
  )) {
    out.partialPhases.push({
      phaseId,
      status: result.status,
      updatedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || (result.status === 'crash_suspect_local_inventory_userdata_introspection'
        ? 'Local inventory userdata wrapper metadata was collected, but crash evidence exists after this run.'
        : 'No local inventory userdata introspection evidence was found.'),
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'crystals-read' && (
    result.status === 'crash_suspect_crystals_read' ||
    result.status === 'no_evidence'
  )) {
    out.partialPhases.push({
      phaseId,
      status: result.status,
      updatedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || (result.status === 'crash_suspect_crystals_read'
        ? 'Local PlayerState Crystals scalar was read, but crash evidence exists after this run.'
        : 'No local PlayerState Crystals read evidence was found.'),
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'slots-read' && (
    result.status === 'crash_suspect_slots_read' ||
    result.status === 'no_evidence'
  )) {
    out.partialPhases.push({
      phaseId,
      status: result.status,
      updatedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || (result.status === 'crash_suspect_slots_read'
        ? 'Local PlayerState slot scalars were read, but crash evidence exists after this run.'
        : 'No local PlayerState slots read evidence was found.'),
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'safe-scalar-watch' && (
    result.status === 'crash_suspect_safe_scalar_watch' ||
    result.status === 'no_evidence'
  )) {
    out.partialPhases.push({
      phaseId,
      status: result.status,
      updatedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || (result.status === 'crash_suspect_safe_scalar_watch'
        ? 'Safe scalar watch collected samples, but crash evidence exists after this run.'
        : 'No usable safe scalar watch evidence was found.'),
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else if (phaseId === 'perk-da-catalog-read' && (
    result.status === 'perk_da_catalog_not_found' ||
    result.status === 'crash_suspect_perk_da_catalog_read' ||
    result.status === 'no_evidence'
  )) {
    out.partialPhases.push({
      phaseId,
      status: result.status,
      updatedAt: nowIso(),
      source: 'campaign-collect',
      reason: result.reason || (result.status === 'crash_suspect_perk_da_catalog_read'
        ? 'Perk DataAsset catalog discovery ran, but crash evidence exists after this run.'
        : 'Perk DataAsset catalog discovery ran safely but found no catalogable perk DataAssets.'),
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
  const partial = plan.phases.filter((phase) => /^partial$|^local_identity_confirmed$|^roster_source_unresolved$|^needs_multiplayer$|^local_only_evidence$|^remote_resources_unresolved$|^remote_resources_partial$|^local_inventory_unresolved$|^crash_suspect_local_inventory_shape_visible$|^crash_suspect_local_inventory_shape_confirmed$|^crash_suspect_crystals_read$|^crash_suspect_safe_scalar_watch$|^perk_da_catalog_not_found$|^crash_suspect_perk_da_catalog_read$|^no_evidence$/.test(phaseStatus(state, phase.phaseId)));
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
  const localInventorySessionId = latestSessionIdForRows(facts.rows, isLocalInventoryArrayRow);
  const localInventory = classifyLocalInventoryArrayEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, localInventorySessionId || state.latestSessionId || facts.latestSessionId)
  });
  if (localInventory.status === 'passed') safeSignals.push('local PlayerState inventory array shallow shape/count reads');
  const localInventoryShapeConfirmSessionId = latestSessionIdForRows(facts.rows, isLocalInventoryArrayShapeConfirmRow);
  const localInventoryShapeConfirm = classifyLocalInventoryArrayShapeConfirmEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, localInventoryShapeConfirmSessionId || state.latestSessionId || facts.latestSessionId)
  });
  if (localInventoryShapeConfirm.status === 'local_inventory_shape_confirmed') safeSignals.push('local PlayerState inventory array property shape confirmation without count, traversal, or element dereference');
  const localInventoryUserdataIntrospectionSessionId = latestSessionIdForRows(facts.rows, isLocalInventoryUserdataIntrospectionRow);
  const localInventoryUserdataIntrospection = classifyLocalInventoryUserdataIntrospectionEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, localInventoryUserdataIntrospectionSessionId || state.latestSessionId || facts.latestSessionId)
  });
  if (localInventoryUserdataIntrospection.status === 'local_inventory_userdata_introspection_confirmed') safeSignals.push('local PlayerState inventory userdata wrapper metadata without traversal or element dereference');
  const crystalsReadSessionId = latestSessionIdForRows(facts.rows, isCrystalsReadRow);
  const crystalsRead = classifyCrystalsReadEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, crystalsReadSessionId || state.latestSessionId || facts.latestSessionId)
  });
  if (crystalsRead.status === 'crystals_read_confirmed') safeSignals.push('local PlayerState Crystals scalar read through CrabPC -> PlayerState -> CrabPS');
  const slotsReadSessionId = latestSessionIdForRows(facts.rows, isSlotsReadRow);
  const slotsRead = classifySlotsReadEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, slotsReadSessionId || state.latestSessionId || facts.latestSessionId)
  });
  if (slotsRead.status === 'slots_read_confirmed') safeSignals.push('local PlayerState candidate slot scalar reads through CrabPC -> PlayerState -> CrabPS');
  const safeScalarWatchSessionId = latestSessionIdForRows(facts.rows, isSafeScalarWatchRow);
  const safeScalarWatch = classifySafeScalarWatchEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, safeScalarWatchSessionId || state.latestSessionId || facts.latestSessionId)
  });
  if (safeScalarWatch.status === 'safe_scalar_watch_confirmed_no_change' || safeScalarWatch.status === 'safe_scalar_watch_observed_change') safeSignals.push('safe scalar watch over proven local scalar/property paths');
  const perkCatalogSessionId = latestSessionIdForRows(facts.rows, isPerkDataAssetCatalogRow);
  const perkCatalog = classifyPerkDataAssetCatalogEvidence(facts.rows, {
    crashSuspect: hasCrashSuspectEvidenceForSession(facts, perkCatalogSessionId || state.latestSessionId || facts.latestSessionId)
  });
  if (perkCatalog.status === 'perk_da_catalog_confirmed') safeSignals.push('read-only perk DataAsset catalog discovery and curated field reads');
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

  out += '\n## Local Inventory Array Shallow/Count Visibility\n\n';
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

  out += '\n## Local Inventory Array Shape Confirm\n\n';
  if (!localInventoryShapeConfirm.localInventoryShapeConfirmEvidenceFound) {
    out += '- Summary: unresolved; no `local-inventory-array-shape-confirm` evidence has been imported yet.\n';
    out += '- Purpose: repeat only local CrabPC -> PlayerState slot scalar and inventory array property shape reads.\n';
    out += '- This confirmation phase does not count arrays, traverse arrays, dereference userdata, read InventoryInfo, or read Enhancements.\n';
  } else {
    out += `- Summary: ${localInventoryShapeConfirm.classification}\n`;
    out += `- Local inventory shape confirm status: ${localInventoryShapeConfirm.status}\n`;
    out += `- Local PlayerState present: ${localInventoryShapeConfirm.localPlayerStatePresent ? 'yes' : 'not proven'}\n`;
    out += `- Fields readable by property shape confirm: ${localInventoryShapeConfirm.fieldsReadable.length ? localInventoryShapeConfirm.fieldsReadable.join(', ') : 'none'}\n`;
    out += `- Fields nil or unsupported: ${localInventoryShapeConfirm.fieldsNilOrUnsupported.length ? localInventoryShapeConfirm.fieldsNilOrUnsupported.join(', ') : 'none'}\n`;
    out += `- Property present map: ${Object.keys(localInventoryShapeConfirm.arrayPropertiesPresent).length ? Object.entries(localInventoryShapeConfirm.arrayPropertiesPresent).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Array value kinds: ${Object.keys(localInventoryShapeConfirm.arrayValueKinds).length ? Object.entries(localInventoryShapeConfirm.arrayValueKinds).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Safe tostring kinds: ${Object.keys(localInventoryShapeConfirm.arrayTostringKinds).length ? Object.entries(localInventoryShapeConfirm.arrayTostringKinds).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Slot scalar values: ${Object.keys(localInventoryShapeConfirm.slotScalarValues).length ? Object.entries(localInventoryShapeConfirm.slotScalarValues).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Array counts attempted: ${localInventoryShapeConfirm.noArrayCount ? 'no' : 'yes'}\n`;
    out += `- Array traversal attempted: ${localInventoryShapeConfirm.noArrayTraversal ? 'no' : 'yes'}\n`;
    out += `- Array elements dereferenced: ${localInventoryShapeConfirm.noElementDereference ? 'no' : 'yes'}\n`;
    out += `- InventoryInfo read: ${localInventoryShapeConfirm.noInventoryInfo ? 'no' : 'yes'}\n`;
    out += `- Enhancements read: ${localInventoryShapeConfirm.noEnhancements ? 'no' : 'yes'}\n`;
    out += localInventoryShapeConfirm.crashSuspect
      ? '- A crash dump exists after this run, so this confirmation path remains crash-suspect pending another safer confirmation pass.\n'
      : '- No crash dump is associated with the imported shape-confirm evidence.\n';
    out += '- This phase distinguishes userdata shape visibility from countable Lua table arrays; counts remain unavailable for userdata values.\n';
  }

  out += '\n## Local Inventory Userdata Introspection\n\n';
  if (!localInventoryUserdataIntrospection.localInventoryUserdataIntrospectionEvidenceFound) {
    out += '- Summary: unresolved; no `local-inventory-userdata-introspection` evidence has been imported yet.\n';
    out += '- Purpose: inspect only local inventory userdata wrapper metadata after shape visibility is confirmed.\n';
    out += '- This phase may pcall the length operator as risky metadata, but it does not traverse arrays, dereference elements, read InventoryInfo, or read Enhancements.\n';
  } else {
    out += `- Summary: ${localInventoryUserdataIntrospection.classification}\n`;
    out += `- Local inventory userdata introspection status: ${localInventoryUserdataIntrospection.status}\n`;
    out += `- Local PlayerState present: ${localInventoryUserdataIntrospection.localPlayerStatePresent ? 'yes' : 'not proven'}\n`;
    out += `- Fields readable by userdata introspection: ${localInventoryUserdataIntrospection.fieldsReadable.length ? localInventoryUserdataIntrospection.fieldsReadable.join(', ') : 'none'}\n`;
    out += `- Fields nil or unsupported: ${localInventoryUserdataIntrospection.fieldsNilOrUnsupported.length ? localInventoryUserdataIntrospection.fieldsNilOrUnsupported.join(', ') : 'none'}\n`;
    out += `- Value kinds: ${Object.keys(localInventoryUserdataIntrospection.valueKinds).length ? Object.entries(localInventoryUserdataIntrospection.valueKinds).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Safe tostring kinds: ${Object.keys(localInventoryUserdataIntrospection.tostringKinds).length ? Object.entries(localInventoryUserdataIntrospection.tostringKinds).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Safe tostring prefixes: ${Object.keys(localInventoryUserdataIntrospection.tostringPrefixes).length ? Object.entries(localInventoryUserdataIntrospection.tostringPrefixes).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Metatable kinds: ${Object.keys(localInventoryUserdataIntrospection.metatableKinds).length ? Object.entries(localInventoryUserdataIntrospection.metatableKinds).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Length operator attempted: ${Object.keys(localInventoryUserdataIntrospection.lenOperatorAttempted).length ? Object.entries(localInventoryUserdataIntrospection.lenOperatorAttempted).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Length operator results: ${Object.keys(localInventoryUserdataIntrospection.lenOperatorResults).length ? Object.entries(localInventoryUserdataIntrospection.lenOperatorResults).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Length operator errors: ${Object.keys(localInventoryUserdataIntrospection.lenOperatorErrors).length ? Object.entries(localInventoryUserdataIntrospection.lenOperatorErrors).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Array traversal attempted: ${localInventoryUserdataIntrospection.noArrayTraversal ? 'no' : 'yes'}\n`;
    out += `- Array elements dereferenced: ${localInventoryUserdataIntrospection.noElementDereference ? 'no' : 'yes'}\n`;
    out += `- InventoryInfo read: ${localInventoryUserdataIntrospection.noInventoryInfo ? 'no' : 'yes'}\n`;
    out += `- Enhancements read: ${localInventoryUserdataIntrospection.noEnhancements ? 'no' : 'yes'}\n`;
    out += `- Writes/RPCs: ${localInventoryUserdataIntrospection.noWrites && localInventoryUserdataIntrospection.noRpcs ? 'no' : 'yes'}\n`;
    out += `- HUD/deep arrays: ${localInventoryUserdataIntrospection.noHud && localInventoryUserdataIntrospection.noDeepArrays ? 'no' : 'yes'}\n`;
    out += localInventoryUserdataIntrospection.crashSuspect
      ? '- A crash dump exists after this run, so this metadata path remains crash-suspect pending a repeat.\n'
      : '- No crash dump is associated with the imported userdata introspection evidence.\n';
    out += '- Any length operator result is metadata-only; it is not proof of count traversal or item synchronization.\n';
  }

  out += '\n## Local Crystals Read\n\n';
  if (!crystalsRead.crystalsReadEvidenceFound) {
    out += '- Summary: unresolved; no `crystals-read` evidence has been imported yet.\n';
    out += '- Purpose: read only local PlayerState `Crystals` through `CrabPC -> PlayerState -> CrabPS`.\n';
    out += '- `Crystals` is documented as UInt32-range for interpretation only; RuntimeProbe does not write, clamp, or mutate it.\n';
  } else {
    out += `- Summary: ${crystalsRead.classification}\n`;
    out += `- Crystals read status: ${crystalsRead.status}\n`;
    out += `- Local PlayerState present: ${crystalsRead.localPlayerStatePresent ? 'yes' : 'not proven'}\n`;
    out += `- Crystals read attempted: ${crystalsRead.crystalsReadAttempted ? 'yes' : 'no'}\n`;
    out += `- Crystals value present: ${crystalsRead.crystalsPresent ? 'yes' : 'no'}\n`;
    out += `- Crystals value integer-like when present: ${crystalsRead.valueIntegerLike ? 'yes' : 'no'}\n`;
    out += `- Writes/RPCs: ${crystalsRead.noWrites && crystalsRead.noRpcs ? 'no' : 'yes'}\n`;
    out += `- HUD/deep arrays: ${crystalsRead.noHud && crystalsRead.noDeepArrays ? 'no' : 'yes'}\n`;
    out += `- Inventory arrays/InventoryInfo/Enhancements: ${crystalsRead.noArrayTraversal && crystalsRead.noElementDereference && crystalsRead.noInventoryInfo && crystalsRead.noEnhancements ? 'no' : 'yes'}\n`;
    out += crystalsRead.crashSuspect
      ? '- A crash dump exists after this run, so this scalar path remains crash-suspect pending a repeat.\n'
      : '- No crash dump is associated with the imported crystals-read evidence.\n';
    out += '- UInt32 range is documentation only for this read-only phase; RuntimeProbe does not write or clamp the value.\n';
  }

  out += '\n## Local Slots Read\n\n';
  if (!slotsRead.slotsReadEvidenceFound) {
    out += '- Summary: unresolved; no `slots-read` evidence has been imported yet.\n';
    out += '- Purpose: read only local PlayerState candidate slot counters through `CrabPC -> PlayerState -> CrabPS`.\n';
    out += '- Fields: `NumWeaponModSlots`, `NumAbilityModSlots`, `NumMeleeModSlots`, `NumPerkSlots`; documented as ByteProperty-backed scalar counters in the expected range 0..255.\n';
    out += '- Locked slots remain unresolved; no separate locked/max/total slot field was found in the tracked objectdump-derived notes, and RuntimeProbe does not call `ServerIncrementNumInventorySlots`.\n';
  } else {
    out += `- Summary: ${slotsRead.classification}\n`;
    out += `- Slots read status: ${slotsRead.status}\n`;
    out += `- Local PlayerState present: ${slotsRead.localPlayerStatePresent ? 'yes' : 'not proven'}\n`;
    out += `- Slot read attempted: ${slotsRead.slotsReadAttempted ? 'yes' : 'no'}\n`;
    out += `- Present slot values: ${Object.keys(slotsRead.slotScalarValues).length ? Object.entries(slotsRead.slotScalarValues).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Present slot values integer-like: ${slotsRead.valuesIntegerLike ? 'yes' : 'no'}\n`;
    out += `- Present slot values within 0..255: ${slotsRead.valuesInByteRange ? 'yes' : 'no'}\n`;
    out += `- Writes/RPCs: ${slotsRead.noWrites && slotsRead.noRpcs ? 'no' : 'yes'}\n`;
    out += `- HUD/deep arrays: ${slotsRead.noHud && slotsRead.noDeepArrays ? 'no' : 'yes'}\n`;
    out += `- Inventory arrays/InventoryInfo/Enhancements: ${slotsRead.noArrayCount && slotsRead.noArrayTraversal && slotsRead.noElementDereference && slotsRead.noInventoryInfo && slotsRead.noEnhancements ? 'no' : 'yes'}\n`;
    out += slotsRead.crashSuspect
      ? '- A crash dump exists after this run, so this scalar path remains crash-suspect pending a repeat.\n'
      : '- No crash dump is associated with the imported slots-read evidence.\n';
    out += '- These are observed scalar slot counters / candidate unlocked slot counters only; they are not proven total capacity or locked-slot state.\n';
  }

  out += '\n## Safe Scalar Watch\n\n';
  if (!safeScalarWatch.safeScalarWatchEvidenceFound) {
    out += '- Summary: unresolved; no `safe-scalar-watch` evidence has been imported yet.\n';
    out += '- Purpose: recurring watch of already proven local scalar/property paths only: context/role/lifecycle, `WeaponDA`, `AbilityDA`, `MeleeDA`, `Crystals`, observed scalar slot counters, and PlayerState health fields.\n';
  } else {
    out += `- Summary: ${safeScalarWatch.classification}\n`;
    out += `- Safe scalar watch status: ${safeScalarWatch.status}\n`;
    out += `- Sample count: ${safeScalarWatch.sampleCount}\n`;
    out += `- Logged row count: ${safeScalarWatch.loggedCount}\n`;
    out += `- First values: ${Object.keys(safeScalarWatch.firstValues).length ? Object.entries(safeScalarWatch.firstValues).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Latest values: ${Object.keys(safeScalarWatch.latestValues).length ? Object.entries(safeScalarWatch.latestValues).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Min numeric values: ${Object.keys(safeScalarWatch.minValues).length ? Object.entries(safeScalarWatch.minValues).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Max numeric values: ${Object.keys(safeScalarWatch.maxValues).length ? Object.entries(safeScalarWatch.maxValues).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- Changed fields: ${safeScalarWatch.changedFields.length ? safeScalarWatch.changedFields.join(', ') : 'none'}\n`;
    out += `- Change counts: ${Object.keys(safeScalarWatch.changeCounts).length ? Object.entries(safeScalarWatch.changeCounts).sort().map(([key, value]) => `${key}=${value}`).join(', ') : 'none'}\n`;
    out += `- First/last context: ${safeScalarWatch.firstContext || 'not found'} / ${safeScalarWatch.lastContext || 'not found'}\n`;
    out += `- First/last role: ${safeScalarWatch.firstRole || 'not found'} / ${safeScalarWatch.lastRole || 'not found'}\n`;
    out += `- Slot model status: ${safeScalarWatch.slotModelStatus}\n`;
    out += `- Writes/RPCs/HUD/deep arrays: ${safeScalarWatch.noWrites && safeScalarWatch.noRpcs && safeScalarWatch.noHud && safeScalarWatch.noDeepArrays ? 'no' : 'yes'}\n`;
    out += `- Inventory arrays/count/traversal/elements, InventoryInfo, Enhancements: ${safeScalarWatch.noArrayCount && safeScalarWatch.noArrayTraversal && safeScalarWatch.noElementDereference && safeScalarWatch.noInventoryInfo && safeScalarWatch.noEnhancements ? 'no' : 'yes'}\n`;
    out += safeScalarWatch.crashSuspect
      ? '- A crash dump exists after this run, so this watch remains crash-suspect pending a repeat.\n'
      : '- No crash dump is associated with the imported safe-scalar-watch evidence.\n';
  }

  out += '\n## Perk DataAsset Catalog\n\n';
  if (!perkCatalog.perkDataAssetCatalogEvidenceFound) {
    out += '- Summary: unresolved; no `perk-da-catalog-read` evidence has been imported yet.\n';
    out += '- Purpose: read-only catalog of safely discoverable perk DataAssets through curated class/name discovery and curated field allowlists.\n';
    out += '- TastyOrange and Collector are not special-cased; if they are safely discoverable, they should appear as normal catalog entries.\n';
  } else {
    out += `- Summary: ${perkCatalog.classification}\n`;
    out += `- Perk DataAsset catalog status: ${perkCatalog.status}\n`;
    out += `- Discovery attempted: ${perkCatalog.discoveryAttempted ? 'yes' : 'no'}\n`;
    out += `- Catalog entries: ${perkCatalog.catalogEntryCount}\n`;
    out += `- Candidate count/cap: ${perkCatalog.catalogCandidateCount}/${perkCatalog.catalogCandidateCap || 'unknown'}\n`;
    out += `- Field cap: ${perkCatalog.catalogFieldCap || 'unknown'}\n`;
    out += `- Writes/RPCs/HUD/deep arrays: ${perkCatalog.noWrites && perkCatalog.noRpcs && perkCatalog.noHud && perkCatalog.noDeepArrays ? 'no' : 'yes'}\n`;
    out += `- Inventory arrays/count/traversal/elements, InventoryInfo, Enhancements: ${perkCatalog.noInventoryArrays && perkCatalog.noArrayCount && perkCatalog.noArrayTraversal && perkCatalog.noElementDereference && perkCatalog.noInventoryInfo && perkCatalog.noEnhancements ? 'no' : 'yes'}\n`;
    out += `- DataAsset mutation/function calls: ${perkCatalog.noDataAssetMutation && perkCatalog.noFunctionCalls ? 'no' : 'yes'}\n`;
    out += perkCatalog.crashSuspect
      ? '- A crash dump exists after this run, so this catalog evidence remains crash-suspect pending a repeat.\n'
      : '- No crash dump is associated with the imported perk catalog evidence.\n';
    out += '- Catalog evidence is read-path evidence only. It is not permission to mutate DataAssets.\n';
  }
  out += '- RuntimeProbe proves read paths only; future CrabModFramework / CrabTastyMod write or edit APIs must be designed and gated separately.\n';
  out += '- TastyOrange is not special-cased by RuntimeProbe. It is cataloged as a normal perk if found.\n';
  out += '- Collector is not special-cased by RuntimeProbe. It is cataloged as a normal perk if found.\n';

  out += '\n## Confirmed Unsafe Paths\n\n';
  out += '- HUD ReceiveDrawHUD tick hook remains blocked by default.\n';
  out += '- `FindFirstOf.CrabHC` is not confirmed as a player-health source; imported evidence has seen an unscoped destructible/barrel candidate.\n';
  out += '- Writes and RPCs are disabled and are outside this campaign version.\n';

  out += '\n## Untested Paths\n\n';
  out += '- Vanilla multiplayer local PlayerState health visibility is confirmed only after `multiplayer-health-playerstate-watch` evidence exists; pooled/shared health is a CrabInvSync design concept, not vanilla RuntimeProbe evidence.\n';
  out += '- Multiplayer roster identity is only complete after visible roster evidence exists; local PlayerState identity alone is partial evidence.\n';
  out += '- Roster candidate probes currently include GameState/GameStateBase source identity, CrabGS source identity, PlayerArray shape, capped FindAll PlayerState-like candidates, capped PlayerController/CrabPC candidates, and a capped visible players source candidate.\n';
  out += '- Local crystals are covered only by `crystals-read`; remote crystals remain covered separately by `multiplayer-resource-visibility-read` after imported resource visibility evidence exists.\n';
  out += '- Locked slots remain unresolved; no separate locked/max/total slot-capacity field is present in the tracked objectdump-derived notes, so locked slots may be UI-derived or stored elsewhere.\n';
  out += '- `NumWeaponModSlots`, `NumAbilityModSlots`, `NumMeleeModSlots`, and `NumPerkSlots` are only observed scalar slot counters / candidate unlocked slot counters. They are not proven total capacity or locked-slot state.\n';
  out += '- Local inventory array shallow/count visibility is covered by `local-inventory-array-shallow-read`; property-shape confirmation is covered by `local-inventory-array-shape-confirm`; userdata wrapper metadata is covered by `local-inventory-userdata-introspection`.\n';
  out += '- Item contents are still not proven; userdata metadata does not read item data asset fields or element contents.\n';
  out += '- Perk DataAsset catalog evidence, when present, proves only curated read paths for future CrabModFramework / CrabTastyMod design; controlled write/edit APIs must be built separately.\n';
  out += '- `InventoryInfo` and enhancements remain placeholders until explicit probe sets are implemented.\n';
  out += '- Deep arrays and InventoryInfo gates remain off until their explicit reviewed phases.\n';

  out += '\n## Safety Gate Summary\n\n';
  out += '- Default config remains `tickDriver = none`, `probeSet = shallow-core`, and all research gates false.\n';
  out += '- Campaign read phases never enable writes, RPCs, or HUD hooks.\n';
  out += '- `allowHealthProbes` is enabled only for explicit health phases and `multiplayer-resource-visibility-read` health scalar checks.\n';
  out += '- `allowIdentityProbes` is enabled only for the explicit multiplayer roster and resource visibility phases; `allowRawIdentityEvidence` remains false by default.\n';
  out += '- `allowResourceVisibilityProbes` is enabled only for `multiplayer-resource-visibility-read`.\n';
  out += '- `allowCrystalsReadProbes` is enabled only for `crystals-read`.\n';
  out += '- `allowSlotsReadProbes` is enabled only for `slots-read`.\n';
  out += '- `allowSafeScalarWatchProbes` is enabled only for `safe-scalar-watch`.\n';
  out += '- `allowPerkDataAssetCatalogProbes` is enabled only for `perk-da-catalog-read`.\n';
  out += '- `allowInventoryArrayShallowProbes` is enabled only for `local-inventory-array-shallow-read`.\n';
  out += '- `allowInventoryArrayShapeConfirmProbes` is enabled only for `local-inventory-array-shape-confirm`.\n';
  out += '- `allowInventoryUserdataIntrospectionProbes` is enabled only for `local-inventory-userdata-introspection`.\n';
  out += '- `allowDeepArrayProbes` and `allowInventoryInfoProbes` are not enabled by implemented phases.\n';
  return out;
}

module.exports = {
  ALL_GATES,
  CAMPAIGN,
  DOC_PATH,
  PLAN_PATH,
  STATE_PATH,
  classifyCrystalsReadEvidence,
  classifySafeScalarWatchEvidence,
  classifyPerkDataAssetCatalogEvidence,
  classifySlotsReadEvidence,
  classifyLocalInventoryArrayEvidence,
  classifyLocalInventoryArrayShapeConfirmEvidence,
  classifyLocalInventoryUserdataIntrospectionEvidence,
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
  latestSessionIdForRows,
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
