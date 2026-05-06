#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { extractFullNameFromSummary, parseIdentityFromFullName } = require('./identity_helpers');

const SNAPSHOT_PROBE_NAME = 'MaxSafePlay.PerkDataAsset.CatalogSnapshot';
const DEFAULT_JSON_OUTPUT = path.join('docs', 'data', 'perk_dataasset_catalog.latest.json');
const DEFAULT_CSV_OUTPUT = path.join('docs', 'data', 'perk_dataasset_catalog.latest.csv');
const DEFAULT_MARKDOWN_OUTPUT = path.join('docs', 'PERK_DATAASSET_CATALOG.md');

const REQUIRED_SAFETY_MARKERS = [
  'noWrites',
  'noRpcs',
  'noHud',
  'noDeepArrays',
  'noInventoryArrays',
  'noArrayCount',
  'noArrayTraversal',
  'noElementDereference',
  'noInventoryInfo',
  'noEnhancements',
  'noDataAssetMutation',
  'noFunctionCalls',
  'passiveOnly'
];

const LIKELY_UI_FIELDS = new Set([
  'Name',
  'DisplayName',
  'Title',
  'Description',
  'DescriptionText',
  'ShortDescription',
  'FlavorText',
  'Tags',
  'GameplayTag',
  'Icon',
  'Texture',
  'Material',
  'Color'
]);

const LIKELY_BEHAVIOR_FIELDS = new Set([
  'Rarity',
  'PerkRarity',
  'Tier',
  'PerkTier',
  'Type',
  'PerkType',
  'Category',
  'MaxStacks',
  'StackLimit',
  'BaseValue',
  'Value',
  'Multiplier',
  'Cooldown',
  'Duration',
  'Weight',
  'bEnabled',
  'bCanStack',
  'bHidden',
  'bUnlockedByDefault'
]);

function arg(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : null;
}

function hasFlag(name) {
  return process.argv.includes(name);
}

function ensureDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function writeIfChanged(filePath, text) {
  ensureDir(filePath);
  if (fs.existsSync(filePath) && fs.readFileSync(filePath, 'utf8') === text) {
    return false;
  }
  fs.writeFileSync(filePath, text);
  return true;
}

function toPosixPath(value) {
  return String(value || '').replace(/\\/g, '/');
}

function relativeRepoPath(repoRoot, filePath) {
  return toPosixPath(path.relative(repoRoot, filePath));
}

function readJsonFile(filePath) {
  if (!fs.existsSync(filePath)) return null;
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function readJsonl(filePath) {
  if (!fs.existsSync(filePath)) return [];
  return fs.readFileSync(filePath, 'utf8')
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line, index) => {
      try {
        const row = JSON.parse(line);
        row.__sourceFile = filePath;
        row.__sourceLine = index + 1;
        return row;
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

function numberValue(value, fallback = 0) {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : fallback;
}

function stringValue(value) {
  return value === null || value === undefined ? '' : String(value);
}

function isTruthy(value) {
  return value === true;
}

function uniquePreserveOrder(values) {
  const seen = new Set();
  const out = [];
  for (const value of values) {
    const key = JSON.stringify(value);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(value);
  }
  return out;
}

function summarizeFieldUsage(fieldName) {
  if (LIKELY_UI_FIELDS.has(fieldName)) return 'ui-likely';
  if (LIKELY_BEHAVIOR_FIELDS.has(fieldName)) return 'behavior-likely';
  return 'uncategorized';
}

function isPointerSummary(summary) {
  return /^\s*UObject:\s+/i.test(stringValue(summary));
}

function isNumericSummary(summary) {
  return /^\s*-?\d+(?:\.\d+)?\s*$/.test(stringValue(summary));
}

function parsePrimitiveSummary(summary) {
  const text = stringValue(summary).trim();
  if (text === '') return null;
  if (/^(true|false)$/i.test(text)) {
    return /^true$/i.test(text);
  }
  if (isNumericSummary(text)) {
    const numeric = Number(text);
    return Number.isFinite(numeric) ? numeric : text;
  }
  return text;
}

function parseObjectRefSummary(summary) {
  const text = stringValue(summary).trim();
  if (!text) return null;
  const existsMatch = text.match(/\bexists=(true|false)\b/i);
  const validMatch = text.match(/\bvalid=(true|false)\b/i);
  const fullName = extractFullNameFromSummary(text);
  const identity = parseIdentityFromFullName(fullName);
  let className = '';
  const classMatch = text.match(/\bclass=(.*?)(?:\s+fullName=|\s+name=|\s+shortName=|$)/);
  if (classMatch) className = classMatch[1].trim();
  if (!className && identity.objectClass) className = identity.objectClass;
  return {
    exists: existsMatch ? /^true$/i.test(existsMatch[1]) : null,
    valid: validMatch ? /^true$/i.test(validMatch[1]) : null,
    className,
    fullName,
    shortName: identity.shortName || ''
  };
}

function normalizeField(field) {
  const fieldName = stringValue(field && field.fieldName);
  const status = stringValue(field && field.status) || 'unknown';
  const valueKind = stringValue(field && field.valueKind) || 'unknown';
  const valueSummary = stringValue(field && field.valueSummary);
  const normalized = {
    fieldName,
    status,
    valueKind,
    valueSummary,
    decoded: false,
    unresolved: false,
    decodeNeeded: false,
    decodeStatus: 'unknown',
    decodedValue: null,
    objectRefSummary: null,
    likelyUsage: summarizeFieldUsage(fieldName)
  };

  if (status !== 'read') {
    normalized.unresolved = true;
    normalized.decodeStatus = 'not-read';
    return normalized;
  }

  if (valueKind === 'scalar') {
    normalized.decodedValue = parsePrimitiveSummary(valueSummary);
    normalized.decoded = true;
    normalized.decodeStatus = 'decoded-scalar';
    return normalized;
  }

  if (valueKind === 'enum') {
    if (isPointerSummary(valueSummary)) {
      normalized.decodeNeeded = true;
      normalized.unresolved = true;
      normalized.decodeStatus = 'decode-needed-enum-object';
      return normalized;
    }
    normalized.decodedValue = parsePrimitiveSummary(valueSummary);
    normalized.decoded = true;
    normalized.decodeStatus = 'decoded-enum';
    return normalized;
  }

  if (valueKind === 'object_ref') {
    normalized.objectRefSummary = parseObjectRefSummary(valueSummary);
    normalized.decodeNeeded = true;
    normalized.unresolved = true;
    normalized.decodeStatus = 'decode-needed-object-ref';
    return normalized;
  }

  normalized.unresolved = true;
  normalized.decodeNeeded = true;
  normalized.decodeStatus = 'decode-needed-unknown';
  return normalized;
}

function computeFieldOrder(snapshotRow) {
  const fieldNames = Array.isArray(snapshotRow.catalogFieldNames)
    ? snapshotRow.catalogFieldNames.map((value) => stringValue(value)).filter(Boolean)
    : [];
  if (fieldNames.length > 0) return fieldNames;
  const firstEntry = Array.isArray(snapshotRow.catalogEntries) ? snapshotRow.catalogEntries[0] : null;
  const fields = Array.isArray(firstEntry && firstEntry.fields) ? firstEntry.fields : [];
  return fields.map((field) => stringValue(field.fieldName)).filter(Boolean);
}

function normalizeEntry(entry, fieldOrder) {
  const parsedFullName = parseIdentityFromFullName(entry.sourceFullName || entry.fullName || '');
  const shortName = stringValue(entry.shortName) || stringValue(entry.sourceShortName) || parsedFullName.shortName;
  const fullName = stringValue(entry.fullName) || stringValue(entry.sourceFullName);
  const sourceFullName = stringValue(entry.sourceFullName) || fullName;
  const sourceShortName = stringValue(entry.sourceShortName) || shortName;
  const sourceClass = stringValue(entry.sourceClass) || stringValue(entry.className) || parsedFullName.objectClass;
  const fieldMap = new Map(
    (Array.isArray(entry.fields) ? entry.fields : [])
      .map((field) => [stringValue(field.fieldName), normalizeField(field)])
  );
  const normalizedFields = fieldOrder.map((fieldName) => {
    if (fieldMap.has(fieldName)) return fieldMap.get(fieldName);
    return {
      fieldName,
      status: 'not-captured',
      valueKind: 'unknown',
      valueSummary: '',
      decoded: false,
      unresolved: true,
      decodeNeeded: false,
      decodeStatus: 'not-captured',
      decodedValue: null,
      objectRefSummary: null,
      likelyUsage: summarizeFieldUsage(fieldName)
    };
  });

  const scalarFields = {};
  const enumFields = {};
  const objectRefFields = {};
  const unresolvedFields = [];
  const decodeNeededFields = [];
  let readableFieldCount = 0;
  let objectRefFieldCount = 0;
  let decodeNeededFieldCount = 0;

  for (const field of normalizedFields) {
    if (field.status === 'read') readableFieldCount += 1;
    if (field.valueKind === 'scalar') scalarFields[field.fieldName] = field;
    if (field.valueKind === 'enum') enumFields[field.fieldName] = field;
    if (field.valueKind === 'object_ref') {
      objectRefFields[field.fieldName] = field;
      objectRefFieldCount += 1;
    }
    if (field.unresolved) unresolvedFields.push(field.fieldName);
    if (field.decodeNeeded) {
      decodeNeededFields.push(field.fieldName);
      decodeNeededFieldCount += 1;
    }
  }

  const fieldResults = entry.fieldResults && typeof entry.fieldResults === 'object'
    ? {
        attempted: numberValue(entry.fieldResults.attempted),
        read: numberValue(entry.fieldResults.read),
        nilCount: numberValue(entry.fieldResults.nilCount),
        errorCount: numberValue(entry.fieldResults.errorCount),
        unsupportedValueTypeCount: numberValue(entry.fieldResults.unsupportedValueTypeCount)
      }
    : {
        attempted: fieldOrder.length,
        read: readableFieldCount,
        nilCount: 0,
        errorCount: 0,
        unsupportedValueTypeCount: 0
      };

  return {
    catalogIndex: numberValue(entry.catalogIndex),
    shortName,
    fullName,
    sourceClass,
    isValid: entry.isValid === true,
    readStatus: stringValue(entry.readStatus),
    sourceFullName,
    sourceShortName,
    fieldResults,
    fields: normalizedFields,
    scalarFields,
    enumFields,
    objectRefFields,
    unresolvedFields,
    decodeNeededFields,
    readableFieldCount,
    objectRefFieldCount,
    decodeNeededFieldCount
  };
}

function computeReadStatusCounts(entries) {
  const counts = {};
  for (const entry of entries) {
    const key = stringValue(entry.readStatus) || 'unknown';
    counts[key] = numberValue(counts[key]) + 1;
  }
  return counts;
}

function buildFieldCoverage(entries, fieldOrder) {
  return fieldOrder.map((fieldName) => {
    const matching = entries
      .map((entry) => entry.fields.find((field) => field.fieldName === fieldName))
      .filter(Boolean);
    const readCount = matching.filter((field) => field.status === 'read').length;
    const valueKindsObserved = uniquePreserveOrder(matching.map((field) => field.valueKind).filter(Boolean));
    const decodeStatuses = uniquePreserveOrder(matching.map((field) => field.decodeStatus).filter(Boolean));
    const exampleSummaries = uniquePreserveOrder(
      matching
        .map((field) => field.valueSummary)
        .filter((value) => value && value.trim() !== '')
    ).slice(0, 3);
    let decodeStatus = 'mixed';
    if (decodeStatuses.length === 1) decodeStatus = decodeStatuses[0];
    return {
      fieldName,
      readCount,
      valueKindsObserved,
      exampleSummaries,
      decodeStatus,
      likelyUsage: summarizeFieldUsage(fieldName)
    };
  });
}

function allSafetyMarkersTrue(row) {
  return REQUIRED_SAFETY_MARKERS.every((key) => row && row[key] === true);
}

function hasAllowedGateProfile(row) {
  const gates = row && row.safetyGates && typeof row.safetyGates === 'object' ? row.safetyGates : {};
  if (gates.allowMaxSafePlayRecorderProbes === true) return true;
  if (gates.allowPerkDataAssetCatalogProbes === true) return true;
  return false;
}

function isCoherentSnapshot(row) {
  const entriesLength = Array.isArray(row.catalogEntries) ? row.catalogEntries.length : 0;
  const entryCount = numberValue(row.catalogEntryCount);
  const candidateCount = numberValue(row.catalogCandidateCount);
  const rejectedCount = Math.max(
    numberValue(row.catalogRejectedCandidateCount),
    numberValue(row.maxSafePlayCatalogRejectedCount)
  );
  const knownEntryCount = Math.max(
    numberValue(row.maxSafePlayCatalogKnownEntryCount),
    numberValue(row.catalogKnownEntryCount)
  );
  return entryCount === entriesLength &&
    candidateCount >= entryCount &&
    candidateCount >= entryCount + rejectedCount &&
    knownEntryCount >= entryCount;
}

function listPerkCatalogSnapshots(repoRoot) {
  const evidenceRoot = path.join(repoRoot, 'evidence', 'runtime');
  if (!fs.existsSync(evidenceRoot)) return [];
  const sessionDirs = fs.readdirSync(evidenceRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();
  const snapshots = [];
  for (const sessionId of sessionDirs) {
    const sessionRoot = path.join(evidenceRoot, sessionId);
    const accessPath = path.join(sessionRoot, 'access_evidence.jsonl');
    if (!fs.existsSync(accessPath)) continue;
    const manifestPath = path.join(sessionRoot, 'session_manifest.json');
    const probeResultsPath = path.join(sessionRoot, 'probe_results.jsonl');
    const diagnosticPath = path.join(sessionRoot, 'diagnostic_summary.txt');
    const manifest = readJsonFile(manifestPath);
    const sourceFiles = [accessPath, probeResultsPath, manifestPath, diagnosticPath].filter((filePath) => fs.existsSync(filePath));
    for (const row of readJsonl(accessPath)) {
      const probeName = row.probeName || row.probeId || row.event || '';
      if (probeName !== SNAPSHOT_PROBE_NAME) continue;
      snapshots.push({
        sessionId,
        sessionRoot,
        accessPath,
        manifestPath,
        probeResultsPath,
        diagnosticPath,
        sourceFiles,
        manifest,
        row
      });
    }
  }
  return snapshots;
}

function compareSnapshots(left, right) {
  const leftRow = left.row;
  const rightRow = right.row;
  const rank = (candidate) => ([
    allSafetyMarkersTrue(candidate.row) && hasAllowedGateProfile(candidate.row) ? 1 : 0,
    numberValue(candidate.row.catalogEntryCount),
    isCoherentSnapshot(candidate.row) ? 1 : 0,
    Math.max(
      numberValue(candidate.row.maxSafePlayCatalogKnownEntryCount),
      numberValue(candidate.row.catalogKnownEntryCount)
    ),
    numberValue(candidate.row.catalogCandidateCount),
    -Math.max(
      numberValue(candidate.row.catalogRejectedCandidateCount),
      numberValue(candidate.row.maxSafePlayCatalogRejectedCount)
    ),
    stringValue(candidate.row.timestamp),
    stringValue(candidate.sessionId),
    numberValue(candidate.row.__sourceLine)
  ]);
  const leftRank = rank(left);
  const rightRank = rank(right);
  for (let index = 0; index < leftRank.length; index += 1) {
    if (leftRank[index] < rightRank[index]) return -1;
    if (leftRank[index] > rightRank[index]) return 1;
  }
  return 0;
}

function selectBestPerkCatalogSnapshot(snapshots) {
  if (!snapshots.length) return null;
  return snapshots.slice().sort((left, right) => compareSnapshots(right, left))[0];
}

function buildCatalogSummary(repoRoot, snapshots, selected, entries, fieldOrder) {
  if (!selected) {
    return {
      entryCount: 0,
      candidateCount: 0,
      rejectedCount: 0,
      knownEntryCount: 0,
      fieldCountAttemptedPerEntry: 0,
      foundPatterns: [],
      topRejectionReasons: 'none',
      tastyOrangeFound: false,
      collectorFound: false,
      readStatusCounts: {},
      fieldNames: [],
      fieldCoverage: [],
      safetyMarkers: Object.fromEntries(REQUIRED_SAFETY_MARKERS.map((key) => [key, false])),
      safetyGates: {},
      sourceSessionsConsidered: [],
      selectionReason: 'No imported MaxSafePlay perk catalog snapshot was found under evidence/runtime/.',
      readOnlyNotice: 'RuntimeProbe catalog evidence is read-only and is not permission to mutate DataAssets.'
    };
  }

  const row = selected.row;
  const manifest = selected.manifest || {};
  const sourceSessionsConsidered = snapshots
    .map((candidate) => ({
      sessionId: candidate.sessionId,
      timestamp: stringValue(candidate.row.timestamp),
      entryCount: numberValue(candidate.row.catalogEntryCount),
      candidateCount: numberValue(candidate.row.catalogCandidateCount),
      rejectedCount: Math.max(
        numberValue(candidate.row.catalogRejectedCandidateCount),
        numberValue(candidate.row.maxSafePlayCatalogRejectedCount)
      ),
      knownEntryCount: Math.max(
        numberValue(candidate.row.maxSafePlayCatalogKnownEntryCount),
        numberValue(candidate.row.catalogKnownEntryCount)
      ),
      coherentAccounting: isCoherentSnapshot(candidate.row),
      safeMarkersIntact: allSafetyMarkersTrue(candidate.row) && hasAllowedGateProfile(candidate.row)
    }))
    .sort((left, right) =>
      left.sessionId.localeCompare(right.sessionId)
    );

  return {
    entryCount: numberValue(row.catalogEntryCount),
    candidateCount: numberValue(row.catalogCandidateCount),
    rejectedCount: Math.max(
      numberValue(row.catalogRejectedCandidateCount),
      numberValue(row.maxSafePlayCatalogRejectedCount)
    ),
    knownEntryCount: Math.max(
      numberValue(row.maxSafePlayCatalogKnownEntryCount),
      numberValue(row.catalogKnownEntryCount)
    ),
    fieldCountAttemptedPerEntry: numberValue(row.catalogFieldCap || (entries[0] && entries[0].fieldResults.attempted) || 0),
    foundPatterns: Array.isArray(row.catalogFoundPatterns) ? row.catalogFoundPatterns : [],
    topRejectionReasons: stringValue(row.catalogTopRejectionReasons || row.maxSafePlayCatalogTopRejectionReasons || 'none'),
    tastyOrangeFound: row.tastyOrangeFound === true,
    collectorFound: row.collectorFound === true,
    readStatusCounts: computeReadStatusCounts(entries),
    fieldNames: fieldOrder,
    fieldReadStatuses: row.catalogReadStatuses || {},
    fieldValueKinds: row.catalogValueKinds || {},
    fieldCoverage: buildFieldCoverage(entries, fieldOrder),
    rejectionReasons: row.catalogRejectionReasons || {},
    rejectionDiagnostics: row.catalogRejectionDiagnostics || [],
    safetyMarkers: Object.fromEntries(REQUIRED_SAFETY_MARKERS.map((key) => [key, row[key] === true])),
    safetyGates: row.safetyGates || manifest.safetyGates || {},
    sourceSessionsConsidered,
    selectedSnapshotFile: relativeRepoPath(repoRoot, row.__sourceFile),
    selectedSnapshotLine: numberValue(row.__sourceLine),
    sourceProbeSet: stringValue(row.probeSet || manifest.probeSet),
    sourceBranch: stringValue(manifest.buildInfo && manifest.buildInfo.git_branch),
    sourceStartedAt: stringValue(manifest.startedAt),
    sourceTimestamp: stringValue(row.timestamp),
    selectionReason: 'Selected the imported max-safe-play snapshot with the largest accepted entry count, intact safety markers, and coherent accounting.',
    readOnlyNotice: 'RuntimeProbe catalog evidence is read-only and is not permission to mutate DataAssets.'
  };
}

function normalizeSelectedSnapshot(repoRoot, snapshots, selected) {
  if (!selected) {
    return {
      generatedAt: '',
      sourceSessionId: '',
      sourceCommit: '',
      sourceFiles: [],
      catalogSummary: buildCatalogSummary(repoRoot, snapshots, null, [], []),
      entries: []
    };
  }

  const row = selected.row;
  const manifest = selected.manifest || {};
  const fieldOrder = computeFieldOrder(row);
  const entries = (Array.isArray(row.catalogEntries) ? row.catalogEntries : [])
    .map((entry) => normalizeEntry(entry, fieldOrder))
    .sort((left, right) => left.catalogIndex - right.catalogIndex || left.shortName.localeCompare(right.shortName));
  return {
    generatedAt: stringValue(row.timestamp || manifest.startedAt),
    sourceSessionId: selected.sessionId,
    sourceCommit: stringValue(manifest.buildInfo && manifest.buildInfo.git_commit),
    sourceFiles: selected.sourceFiles.map((filePath) => relativeRepoPath(repoRoot, filePath)),
    catalogSummary: buildCatalogSummary(repoRoot, snapshots, selected, entries, fieldOrder),
    entries
  };
}

function csvEscape(value) {
  const text = value === null || value === undefined ? '' : String(value);
  if (!/[",\r\n]/.test(text)) return text;
  return `"${text.replace(/"/g, '""')}"`;
}

function markdownCell(value) {
  return stringValue(value).replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
}

function shorten(value, maxLength = 80) {
  const text = stringValue(value).trim();
  if (text.length <= maxLength) return text;
  return `${text.slice(0, Math.max(0, maxLength - 3))}...`;
}

function fieldLookup(entry, fieldName) {
  return entry.fields.find((field) => field.fieldName === fieldName) || null;
}

function fieldDisplayValue(entry, fieldName) {
  const field = fieldLookup(entry, fieldName);
  if (!field) return '';
  if (field.decoded) {
    return field.decodedValue === null ? field.valueSummary : field.decodedValue;
  }
  if (field.objectRefSummary && field.objectRefSummary.shortName) {
    return field.objectRefSummary.shortName;
  }
  if (field.objectRefSummary && field.objectRefSummary.fullName) {
    return field.objectRefSummary.fullName;
  }
  return field.valueSummary;
}

function renderCsv(model) {
  const columns = [
    'catalogIndex',
    'shortName',
    'fullName',
    'sourceClass',
    'PerkType',
    'Rarity',
    'PerkRarity',
    'Tier',
    'PerkTier',
    'Type',
    'Category',
    'Cooldown',
    'Icon',
    'readStatus',
    'readableFieldCount',
    'objectRefFieldCount',
    'decodeNeededFieldCount'
  ];
  const lines = [columns.join(',')];
  for (const entry of model.entries) {
    const row = [
      entry.catalogIndex,
      entry.shortName,
      entry.fullName,
      entry.sourceClass,
      fieldDisplayValue(entry, 'PerkType'),
      fieldDisplayValue(entry, 'Rarity'),
      fieldDisplayValue(entry, 'PerkRarity'),
      fieldDisplayValue(entry, 'Tier'),
      fieldDisplayValue(entry, 'PerkTier'),
      fieldDisplayValue(entry, 'Type'),
      fieldDisplayValue(entry, 'Category'),
      fieldDisplayValue(entry, 'Cooldown'),
      fieldDisplayValue(entry, 'Icon'),
      entry.readStatus,
      entry.readableFieldCount,
      entry.objectRefFieldCount,
      entry.decodeNeededFieldCount
    ].map(csvEscape);
    lines.push(row.join(','));
  }
  return `${lines.join('\n')}\n`;
}

function renderFieldCoverageTable(model) {
  const lines = [
    '| Field | Count Read | Value Kinds Observed | Example Value Summaries | Decode Status | Likely Usage |',
    '|---|---:|---|---|---|---|'
  ];
  for (const item of model.catalogSummary.fieldCoverage) {
    lines.push(
      `| ${markdownCell(item.fieldName)} | ${item.readCount} | ${markdownCell(item.valueKindsObserved.join(', '))} | ${markdownCell(item.exampleSummaries.map((value) => shorten(value, 72)).join('; '))} | ${markdownCell(item.decodeStatus)} | ${markdownCell(item.likelyUsage)} |`
    );
  }
  return lines.join('\n');
}

function renderPerkIndexTable(model) {
  const lines = [
    '| Index | Short Name | PerkType | Rarity | Tier | Type | Category | Cooldown | Icon Summary |',
    '|---:|---|---|---|---|---|---|---|---|'
  ];
  for (const entry of model.entries) {
    lines.push(
      `| ${entry.catalogIndex} | ${markdownCell(entry.shortName)} | ${markdownCell(fieldDisplayValue(entry, 'PerkType'))} | ${markdownCell(fieldDisplayValue(entry, 'Rarity'))} | ${markdownCell(shorten(fieldDisplayValue(entry, 'Tier'), 28))} | ${markdownCell(shorten(fieldDisplayValue(entry, 'Type'), 28))} | ${markdownCell(shorten(fieldDisplayValue(entry, 'Category'), 28))} | ${markdownCell(fieldDisplayValue(entry, 'Cooldown'))} | ${markdownCell(shorten(fieldDisplayValue(entry, 'Icon'), 40))} |`
    );
  }
  return lines.join('\n');
}

function renderFieldList(fields) {
  if (!fields.length) return '- None.\n';
  return fields.map((fieldName) => `- \`${fieldName}\`\n`).join('');
}

function renderTastyOrangeSection(model) {
  const tastyOrange = model.entries.find((entry) => /TastyOrange/i.test(`${entry.shortName} ${entry.fullName}`));
  if (!tastyOrange) {
    return '## TastyOrange Spotlight\n\nTastyOrange was not present in the selected imported catalog snapshot.\n';
  }

  const decodedFields = tastyOrange.fields.filter((field) => field.decoded).map((field) => field.fieldName);
  const decodeNeededFields = tastyOrange.fields.filter((field) => field.decodeNeeded).map((field) => field.fieldName);
  const lines = [
    '## TastyOrange Spotlight',
    '',
    `- Short name: \`${tastyOrange.shortName}\``,
    `- Full name: \`${tastyOrange.fullName}\``,
    `- Source class: \`${tastyOrange.sourceClass}\``,
    `- PerkType: \`${fieldDisplayValue(tastyOrange, 'PerkType')}\``,
    `- Rarity: \`${fieldDisplayValue(tastyOrange, 'Rarity')}\``,
    `- Cooldown: \`${fieldDisplayValue(tastyOrange, 'Cooldown')}\``,
    `- Icon summary: \`${fieldDisplayValue(tastyOrange, 'Icon')}\``,
    '',
    'Decoded fields:',
    renderFieldList(decodedFields).trimEnd(),
    '',
    'Fields still marked decode-needed:',
    renderFieldList(decodeNeededFields).trimEnd(),
    '',
    '| Field | Status | Value Kind | Value Summary | Decode Status |',
    '|---|---|---|---|---|'
  ];
  for (const field of tastyOrange.fields) {
    lines.push(
      `| ${markdownCell(field.fieldName)} | ${markdownCell(field.status)} | ${markdownCell(field.valueKind)} | ${markdownCell(shorten(field.valueSummary, 88))} | ${markdownCell(field.decodeStatus)} |`
    );
  }
  lines.push('');
  return `${lines.join('\n')}\n`;
}

function renderFieldInterpretationNotes(model) {
  const decodedFields = model.catalogSummary.fieldCoverage
    .filter((field) => /^decoded-/.test(field.decodeStatus))
    .map((field) => field.fieldName);
  const decodeNeededFields = model.catalogSummary.fieldCoverage
    .filter((field) => /^decode-needed-/.test(field.decodeStatus))
    .map((field) => field.fieldName);
  return [
    '## Field Interpretation Notes',
    '',
    'Likely UI-facing fields:',
    renderFieldList(model.catalogSummary.fieldNames.filter((fieldName) => LIKELY_UI_FIELDS.has(fieldName))).trimEnd(),
    '',
    'Likely behavior/tuning fields:',
    renderFieldList(model.catalogSummary.fieldNames.filter((fieldName) => LIKELY_BEHAVIOR_FIELDS.has(fieldName))).trimEnd(),
    '',
    'Currently decoded scalar/enum fields:',
    renderFieldList(decodedFields).trimEnd(),
    '',
    'Currently unresolved or decoder-needed fields:',
    renderFieldList(decodeNeededFields).trimEnd(),
    ''
  ].join('\n');
}

function renderMarkdown(model) {
  const summary = model.catalogSummary;
  const sourceFiles = model.sourceFiles.length > 0
    ? model.sourceFiles.map((filePath) => `- \`${filePath}\``).join('\n')
    : '- none';
  if (model.entries.length === 0) {
    return [
      '# Perk DataAsset Catalog',
      '',
      '> Generated by `tools/extract_perk_dataasset_catalog.js`. Do not edit by hand.',
      '',
      'RuntimeProbe catalog evidence is read-only and is not permission to mutate DataAssets.',
      '',
      'No imported `MaxSafePlay.PerkDataAsset.CatalogSnapshot` row was found under `evidence/runtime/`.',
      '',
      'Source files considered:',
      sourceFiles,
      ''
    ].join('\n');
  }

  const lines = [
    '# Perk DataAsset Catalog',
    '',
    '> Generated by `tools/extract_perk_dataasset_catalog.js`. Do not edit by hand.',
    '',
    'RuntimeProbe catalog evidence is read-only and is not permission to mutate DataAssets.',
    '',
    '## Source Session',
    '',
    `- Source session ID: \`${model.sourceSessionId}\``,
    `- Source commit: \`${model.sourceCommit || 'unknown'}\``,
    `- Source branch: \`${summary.sourceBranch || 'unknown'}\``,
    `- Selected snapshot row: \`${summary.selectedSnapshotFile}:${summary.selectedSnapshotLine}\``,
    `- Snapshot timestamp: \`${summary.sourceTimestamp || 'unknown'}\``,
    `- Selection reason: ${summary.selectionReason}`,
    'Source files:',
    sourceFiles,
    '',
    '## Summary',
    '',
    `- Total candidates: ${summary.candidateCount}`,
    `- Accepted entries: ${summary.entryCount}`,
    `- Rejected entries: ${summary.rejectedCount}`,
    `- Known entry count: ${summary.knownEntryCount}`,
    `- TastyOrange found: ${summary.tastyOrangeFound ? 'yes' : 'no'}`,
    `- Collector found: ${summary.collectorFound ? 'yes' : 'no'}`,
    `- Fields attempted per entry: ${summary.fieldCountAttemptedPerEntry}`,
    `- Found patterns: ${summary.foundPatterns.length ? summary.foundPatterns.join(', ') : 'none'}`,
    `- Top rejection reasons: ${summary.topRejectionReasons || 'none'}`,
    '',
    '## Safety Markers',
    '',
    ...REQUIRED_SAFETY_MARKERS.map((key) => `- \`${key}\`: ${summary.safetyMarkers[key] ? 'true' : 'false'}`),
    '',
    '## Field Coverage Matrix',
    '',
    renderFieldCoverageTable(model),
    '',
    '## Perk Index Table',
    '',
    renderPerkIndexTable(model),
    '',
    renderTastyOrangeSection(model).trimEnd(),
    '',
    '## Unresolved Object Reference Notes',
    '',
    '- `Name`, `DisplayName`, `Title`, `Description`, `DescriptionText`, `ShortDescription`, and `FlavorText` currently surface as `object_ref` summaries rather than decoded text/name payloads.',
    '- `Icon` is a useful object reference summary because it exposes a texture asset full name, but it is still not a decoded scalar/enum field.',
    '- `MaxStacks`, `StackLimit`, `BaseValue`, `Value`, `Multiplier`, `Duration`, `Weight`, and the `b*` flags are currently unresolved `object_ref` summaries and must stay marked decode-needed.',
    '- `PerkRarity`, `Tier`, `PerkTier`, `Type`, and `Category` are tagged as enums by the probe, but their current values are opaque `UObject:` pointer summaries and still need a future decoder.',
    '',
    renderFieldInterpretationNotes(model).trimEnd(),
    '',
    '## CrabModFramework Implications',
    '',
    '- The canonical read model for future CrabModFramework work is the exported JSON/CSV in `docs/data/`, not ad hoc parsing of raw JSONL.',
    '- TastyOrange should be treated as a normal catalog row. RuntimeProbe does not special-case it, and CrabModFramework should not special-case it at catalog-ingest time either.',
    '- Future write/edit APIs need separate design, capability gates, and review. This RuntimeProbe evidence only proves read visibility for a capped field set.',
    '',
    'RuntimeProbe catalog evidence is not permission to mutate DataAssets.',
    ''
  ];
  return lines.join('\n');
}

function generatePerkDataAssetCatalogOutputs(options = {}) {
  const repoRoot = path.resolve(options.repoRoot || process.cwd());
  const jsonOut = path.resolve(options.jsonOut || path.join(repoRoot, DEFAULT_JSON_OUTPUT));
  const csvOut = path.resolve(options.csvOut || path.join(repoRoot, DEFAULT_CSV_OUTPUT));
  const markdownOut = path.resolve(options.markdownOut || path.join(repoRoot, DEFAULT_MARKDOWN_OUTPUT));
  const quiet = options.quiet === true;

  const snapshots = listPerkCatalogSnapshots(repoRoot);
  const selected = selectBestPerkCatalogSnapshot(snapshots);
  const model = normalizeSelectedSnapshot(repoRoot, snapshots, selected);

  const jsonText = `${JSON.stringify(model, null, 2)}\n`;
  const csvText = renderCsv(model);
  const markdownText = renderMarkdown(model);

  writeIfChanged(jsonOut, jsonText);
  writeIfChanged(csvOut, csvText);
  writeIfChanged(markdownOut, markdownText);

  const result = {
    model,
    selected,
    outputs: {
      json: jsonOut,
      csv: csvOut,
      markdown: markdownOut
    }
  };

  if (!quiet) {
    console.log(`perk catalog source session = ${model.sourceSessionId || 'none'}`);
    console.log(`perk catalog entries = ${model.catalogSummary.entryCount}`);
    console.log(`generated perk catalog json = ${path.relative(repoRoot, jsonOut)}`);
    console.log(`generated perk catalog csv = ${path.relative(repoRoot, csvOut)}`);
    console.log(`generated perk catalog markdown = ${path.relative(repoRoot, markdownOut)}`);
  }

  return result;
}

module.exports = {
  DEFAULT_CSV_OUTPUT,
  DEFAULT_JSON_OUTPUT,
  DEFAULT_MARKDOWN_OUTPUT,
  buildFieldCoverage,
  generatePerkDataAssetCatalogOutputs,
  listPerkCatalogSnapshots,
  normalizeSelectedSnapshot,
  renderCsv,
  renderMarkdown,
  selectBestPerkCatalogSnapshot
};

if (require.main === module) {
  generatePerkDataAssetCatalogOutputs({
    repoRoot: arg('--repo-root'),
    jsonOut: arg('--json-out'),
    csvOut: arg('--csv-out'),
    markdownOut: arg('--markdown-out'),
    quiet: hasFlag('--quiet')
  });
}
