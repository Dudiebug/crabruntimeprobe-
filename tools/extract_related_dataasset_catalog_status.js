#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const READ_ONLY_NOTICE = 'RuntimeProbe catalog evidence is read-only and is not permission to mutate DataAssets.';
const BLOCKED_REASON_FALLBACK = 'Future DataAsset catalog phase; implement after perk catalog evidence and safety review.';

const FAMILY_CONFIGS = [
  {
    familyId: 'weaponmod',
    title: 'Weapon Mod DataAsset Catalog',
    markdownFile: 'WEAPONMOD_DATAASSET_CATALOG.md',
    jsonFile: path.join('data', 'weaponmod_dataasset_catalog.latest.json'),
    csvFile: path.join('data', 'weaponmod_dataasset_catalog.latest.csv'),
    phaseId: 'weaponmod-da-catalog-read',
    phaseLabel: 'Weapon mod DataAsset catalog placeholder',
    playerStateArrayProperty: 'WeaponMods',
    wrapperClass: 'CrabWeaponMod',
    dataAssetProperty: 'WeaponModDA',
    slotScalarProperty: 'NumWeaponModSlots'
  },
  {
    familyId: 'abilitymod',
    title: 'Ability Mod DataAsset Catalog',
    markdownFile: 'ABILITYMOD_DATAASSET_CATALOG.md',
    jsonFile: path.join('data', 'abilitymod_dataasset_catalog.latest.json'),
    csvFile: path.join('data', 'abilitymod_dataasset_catalog.latest.csv'),
    phaseId: 'abilitymod-da-catalog-read',
    phaseLabel: 'Ability mod DataAsset catalog placeholder',
    playerStateArrayProperty: 'AbilityMods',
    wrapperClass: 'CrabAbilityMod',
    dataAssetProperty: 'AbilityModDA',
    slotScalarProperty: 'NumAbilityModSlots'
  },
  {
    familyId: 'meleemod',
    title: 'Melee Mod DataAsset Catalog',
    markdownFile: 'MELEEMOD_DATAASSET_CATALOG.md',
    jsonFile: path.join('data', 'meleemod_dataasset_catalog.latest.json'),
    csvFile: path.join('data', 'meleemod_dataasset_catalog.latest.csv'),
    phaseId: 'meleemod-da-catalog-read',
    phaseLabel: 'Melee mod DataAsset catalog placeholder',
    playerStateArrayProperty: 'MeleeMods',
    wrapperClass: 'CrabMeleeMod',
    dataAssetProperty: 'MeleeModDA',
    slotScalarProperty: 'NumMeleeModSlots'
  },
  {
    familyId: 'relic',
    title: 'Relic DataAsset Catalog',
    markdownFile: 'RELIC_DATAASSET_CATALOG.md',
    jsonFile: path.join('data', 'relic_dataasset_catalog.latest.json'),
    csvFile: path.join('data', 'relic_dataasset_catalog.latest.csv'),
    phaseId: 'relic-da-catalog-read',
    phaseLabel: 'Relic DataAsset catalog placeholder',
    playerStateArrayProperty: 'Relics',
    wrapperClass: 'CrabRelic',
    dataAssetProperty: 'RelicDA',
    slotScalarProperty: ''
  }
];

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

function toPosixPath(value) {
  return String(value || '').replace(/\\/g, '/');
}

function relativeRepoPath(repoRoot, filePath) {
  return toPosixPath(path.relative(repoRoot, filePath));
}

function stringValue(value) {
  return value === null || value === undefined ? '' : String(value);
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

function csvEscape(value) {
  const text = stringValue(value);
  if (/[",\r\n]/.test(text)) return `"${text.replace(/"/g, '""')}"`;
  return text;
}

function markdownCell(value) {
  return stringValue(value).replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
}

function shorten(value, maxLength) {
  const text = stringValue(value);
  if (!maxLength || text.length <= maxLength) return text;
  return `${text.slice(0, Math.max(0, maxLength - 3))}...`;
}

function listAccessEvidenceRows(repoRoot) {
  const evidenceRoot = path.join(repoRoot, 'evidence', 'runtime');
  if (!fs.existsSync(evidenceRoot)) return [];
  const sessionDirs = fs.readdirSync(evidenceRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();
  const rows = [];
  for (const sessionId of sessionDirs) {
    const accessPath = path.join(evidenceRoot, sessionId, 'access_evidence.jsonl');
    for (const row of readJsonl(accessPath)) {
      if (!row.sessionId) row.sessionId = sessionId;
      rows.push(row);
    }
  }
  return rows;
}

function loadCampaignPlan(repoRoot) {
  return readJsonFile(path.join(repoRoot, 'campaign', 'campaign_plan.crabruntimeprobe-read-map.json')) || { phases: [] };
}

function familyForId(familyId) {
  return FAMILY_CONFIGS.find((family) => family.familyId === familyId) || null;
}

function selectRelatedRows(rows, family) {
  const terms = [
    family.playerStateArrayProperty,
    family.wrapperClass,
    family.dataAssetProperty,
    family.slotScalarProperty
  ].filter(Boolean);
  return rows.filter((row) => {
    const text = JSON.stringify(row);
    return terms.some((term) => text.includes(term));
  });
}

function summarizeRelatedRows(repoRoot, rows) {
  const sourceFiles = uniquePreserveOrder(rows.map((row) => relativeRepoPath(repoRoot, row.__sourceFile)).filter(Boolean));
  const relatedSessions = uniquePreserveOrder(rows.map((row) => stringValue(row.sessionId)).filter(Boolean));
  const relatedProbeNames = uniquePreserveOrder(rows.map((row) => stringValue(row.probeName || row.probeId || row.event)).filter(Boolean));
  const latestByProbe = new Map();
  for (const row of rows) {
    const probeName = stringValue(row.probeName || row.probeId || row.event) || 'unknown';
    latestByProbe.set(probeName, row);
  }
  const relatedRuntimeEvidenceRows = Array.from(latestByProbe.values())
    .sort((left, right) =>
      stringValue(left.sessionId).localeCompare(stringValue(right.sessionId)) ||
      stringValue(left.probeName || left.probeId || left.event).localeCompare(stringValue(right.probeName || right.probeId || right.event)) ||
      Number(left.__sourceLine || 0) - Number(right.__sourceLine || 0)
    )
    .map((row) => ({
      sessionId: stringValue(row.sessionId),
      probeName: stringValue(row.probeName || row.probeId || row.event),
      result: stringValue(row.result),
      runtimeStatus: stringValue(row.runtimeStatus),
      valueSummary: stringValue(row.valueSummary || row.localNotes),
      sourceFile: relativeRepoPath(repoRoot, row.__sourceFile),
      sourceLine: Number(row.__sourceLine || 0)
    }));
  return {
    sourceFiles,
    relatedSessions,
    relatedProbeNames,
    relatedRuntimeEvidenceRows
  };
}

function buildModel(repoRoot, rows, plan, family) {
  const phase = Array.isArray(plan.phases)
    ? plan.phases.find((candidate) => candidate.phaseId === family.phaseId)
    : null;
  const relatedRows = selectRelatedRows(rows, family);
  const related = summarizeRelatedRows(repoRoot, relatedRows);
  const status = 'no-imported-catalog-snapshot';

  return {
    generatedAt: new Date().toISOString(),
    familyId: family.familyId,
    title: family.title,
    sourceSessionId: '',
    sourceCommit: '',
    sourceFiles: related.sourceFiles,
    knownModel: {
      playerStateArrayProperty: `CrabPS.${family.playerStateArrayProperty}`,
      wrapperClass: family.wrapperClass,
      dataAssetProperty: `${family.wrapperClass}.${family.dataAssetProperty}`,
      slotScalarProperty: family.slotScalarProperty ? `CrabPS.${family.slotScalarProperty}` : ''
    },
    catalogSummary: {
      status,
      importedCatalogSnapshotFound: false,
      candidateCount: 0,
      entryCount: 0,
      rejectedCount: 0,
      knownEntryCount: 0,
      fieldCountAttemptedPerEntry: 0,
      objectdumpSignals: [
        `CrabPS.${family.playerStateArrayProperty}`,
        family.slotScalarProperty ? `CrabPS.${family.slotScalarProperty}` : '',
        family.wrapperClass,
        `${family.wrapperClass}.${family.dataAssetProperty}`
      ].filter(Boolean),
      relatedRuntimeEvidenceSessions: related.relatedSessions,
      relatedRuntimeEvidenceKinds: related.relatedProbeNames,
      relatedRuntimeEvidenceRows: related.relatedRuntimeEvidenceRows,
      campaignPhase: {
        phaseId: family.phaseId,
        label: phase && phase.label ? phase.label : family.phaseLabel,
        implemented: phase ? phase.implemented === true : false,
        blockedReason: phase && phase.blockedReason ? phase.blockedReason : BLOCKED_REASON_FALLBACK
      },
      selectionReason: `No imported read-only catalog snapshot has been selected yet for ${family.title}. Current outputs document only related objectdump/shallow runtime evidence and the campaign placeholder phase.`,
      readOnlyNotice: READ_ONLY_NOTICE
    },
    entries: []
  };
}

function renderCsv(model) {
  const lines = [
    'catalogIndex,shortName,fullName,sourceClass,wrapperClass,dataAssetProperty,readStatus,notes'
  ];
  for (const entry of model.entries) {
    const row = [
      entry.catalogIndex,
      entry.shortName,
      entry.fullName,
      entry.sourceClass,
      model.knownModel.wrapperClass,
      model.knownModel.dataAssetProperty,
      entry.readStatus,
      ''
    ].map(csvEscape);
    lines.push(row.join(','));
  }
  return `${lines.join('\n')}\n`;
}

function renderRelatedEvidenceRows(model) {
  const rows = model.catalogSummary.relatedRuntimeEvidenceRows || [];
  if (!rows.length) return '- No imported runtime rows matching this family were found.\n';
  return [
    '| Session | Probe | Result | Summary |',
    '|---|---|---|---|',
    ...rows.map((row) =>
      `| ${markdownCell(row.sessionId)} | ${markdownCell(row.probeName)} | ${markdownCell(row.result || row.runtimeStatus)} | ${markdownCell(shorten(row.valueSummary, 96))} |`
    ),
    ''
  ].join('\n');
}

function renderMarkdown(model) {
  const summary = model.catalogSummary;
  const sourceFiles = model.sourceFiles.length > 0
    ? model.sourceFiles.map((filePath) => `- \`${filePath}\``).join('\n')
    : '- none';
  return [
    `# ${model.title}`,
    '',
    '> Generated by `tools/extract_related_dataasset_catalog_status.js`. Do not edit by hand.',
    '',
    READ_ONLY_NOTICE,
    '',
    '## Current Status',
    '',
    '- Imported read-only catalog snapshot selected: no',
    `- Status: \`${summary.status}\``,
    `- Campaign phase: \`${summary.campaignPhase.phaseId}\` (${summary.campaignPhase.implemented ? 'implemented' : 'placeholder'})`,
    `- Blocked reason: ${summary.campaignPhase.blockedReason}`,
    `- Selection reason: ${summary.selectionReason}`,
    '',
    '## Known Model',
    '',
    `- PlayerState array property: \`${model.knownModel.playerStateArrayProperty}\``,
    model.knownModel.slotScalarProperty
      ? `- Related slot scalar property: \`${model.knownModel.slotScalarProperty}\``
      : '- Related slot scalar property: none documented yet',
    `- Wrapper class: \`${model.knownModel.wrapperClass}\``,
    `- DataAsset property path: \`${model.knownModel.dataAssetProperty}\``,
    '',
    '## Known Safe Evidence',
    '',
    `- Related runtime evidence sessions: ${summary.relatedRuntimeEvidenceSessions.length ? summary.relatedRuntimeEvidenceSessions.join(', ') : 'none imported yet'}`,
    `- Related runtime evidence kinds: ${summary.relatedRuntimeEvidenceKinds.length ? summary.relatedRuntimeEvidenceKinds.join(', ') : 'none imported yet'}`,
    `- Objectdump signals: ${summary.objectdumpSignals.join(', ')}`,
    'Source files:',
    sourceFiles,
    '',
    renderRelatedEvidenceRows(model).trimEnd(),
    '',
    '## Not Yet Proven',
    '',
    '- No imported catalog snapshot has enumerated live entries for this family yet.',
    '- No read-only field coverage matrix exists yet because no catalog entry rows have been imported.',
    '- No decoded scalar/enum vs object_ref split exists yet for this family.',
    '- No safe slot element dereference, InventoryInfo read, Enhancement read, write, RPC, or DataAsset mutation evidence is added by this docs pass.',
    '',
    '## CrabModFramework Implications',
    '',
    '- These JSON/CSV/Markdown outputs are status artifacts only until a dedicated read-only catalog phase is implemented and imported.',
    '- Future CrabModFramework ingestion should treat this family as schema-known but entry-unknown for now.',
    '- RuntimeProbe catalog evidence is not permission to mutate DataAssets.',
    ''
  ].join('\n');
}

function outputPaths(outputRoot, family) {
  return {
    markdown: path.join(outputRoot, 'docs', family.markdownFile),
    json: path.join(outputRoot, 'docs', family.jsonFile),
    csv: path.join(outputRoot, 'docs', family.csvFile)
  };
}

function generateRelatedDataAssetCatalogStatusOutputs(options = {}) {
  const repoRoot = path.resolve(options.repoRoot || process.cwd());
  const outputRoot = path.resolve(options.outputRoot || repoRoot);
  const quiet = options.quiet === true;
  const requestedFamilies = Array.isArray(options.families) && options.families.length > 0
    ? options.families
    : null;
  const selectedFamilies = (requestedFamilies
    ? requestedFamilies.map(familyForId).filter(Boolean)
    : FAMILY_CONFIGS);
  const rows = listAccessEvidenceRows(repoRoot);
  const plan = loadCampaignPlan(repoRoot);
  const results = [];

  for (const family of selectedFamilies) {
    const model = buildModel(repoRoot, rows, plan, family);
    const paths = outputPaths(outputRoot, family);
    writeIfChanged(paths.json, `${JSON.stringify(model, null, 2)}\n`);
    writeIfChanged(paths.csv, renderCsv(model));
    writeIfChanged(paths.markdown, renderMarkdown(model));
    results.push({
      familyId: family.familyId,
      model,
      outputs: paths
    });
    if (!quiet) {
      console.log(`${family.familyId} catalog status = ${model.catalogSummary.status}`);
      console.log(`generated ${family.familyId} catalog json = ${path.relative(outputRoot, paths.json)}`);
      console.log(`generated ${family.familyId} catalog csv = ${path.relative(outputRoot, paths.csv)}`);
      console.log(`generated ${family.familyId} catalog markdown = ${path.relative(outputRoot, paths.markdown)}`);
    }
  }

  return results;
}

module.exports = {
  FAMILY_CONFIGS,
  buildModel,
  generateRelatedDataAssetCatalogStatusOutputs,
  renderCsv,
  renderMarkdown
};

if (require.main === module) {
  const familyArg = arg('--family');
  generateRelatedDataAssetCatalogStatusOutputs({
    repoRoot: arg('--repo-root'),
    outputRoot: arg('--output-root'),
    quiet: hasFlag('--quiet'),
    families: familyArg ? familyArg.split(',').map((value) => value.trim()).filter(Boolean) : null
  });
}
