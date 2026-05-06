[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$WorkRoot = Join-Path $RepoRoot "dist\test-perk-dataasset-catalog-docs-work"
$ToolPath = Join-Path $RepoRoot "tools\extract_perk_dataasset_catalog.js"

if (Test-Path -LiteralPath $WorkRoot) {
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$NodeTestPath = Join-Path $WorkRoot "perk-dataasset-catalog-docs-test.js"
Set-Content -LiteralPath $NodeTestPath -Encoding ASCII -Value @'
const fs = require('fs');
const path = require('path');

const tool = require(process.argv[2]);
const repoRoot = process.argv[3];
const workRoot = process.argv[4];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const jsonOut = path.join(workRoot, 'perk_dataasset_catalog.latest.json');
const csvOut = path.join(workRoot, 'perk_dataasset_catalog.latest.csv');
const markdownOut = path.join(workRoot, 'PERK_DATAASSET_CATALOG.md');

const snapshots = tool.listPerkCatalogSnapshots(repoRoot);
const selected = tool.selectBestPerkCatalogSnapshot(snapshots);
assert(selected, 'expected at least one imported MaxSafePlay perk catalog snapshot');

const expectedSessionId = snapshots.some((candidate) =>
  candidate.sessionId === '20260506T032658Z' &&
  Number(candidate.row.catalogEntryCount || 0) === 64
) ? '20260506T032658Z' : null;

tool.generatePerkDataAssetCatalogOutputs({
  repoRoot,
  jsonOut,
  csvOut,
  markdownOut,
  quiet: true
});

assert(fs.existsSync(jsonOut), 'expected JSON output');
assert(fs.existsSync(csvOut), 'expected CSV output');
assert(fs.existsSync(markdownOut), 'expected Markdown output');

const model = JSON.parse(fs.readFileSync(jsonOut, 'utf8'));
assert(model.generatedAt, 'generatedAt should be present');
assert(model.sourceSessionId, 'sourceSessionId should be present');
assert(model.sourceCommit, 'sourceCommit should be present');
assert(Array.isArray(model.sourceFiles) && model.sourceFiles.length > 0, 'sourceFiles should be present');
assert(model.catalogSummary && typeof model.catalogSummary === 'object', 'catalogSummary should be present');
assert(Array.isArray(model.entries), 'entries should be present');
assert(model.catalogSummary.entryCount === model.entries.length, 'entryCount should match entries length');

if (expectedSessionId) {
  assert(model.sourceSessionId === expectedSessionId, `expected selected session ${expectedSessionId}, got ${model.sourceSessionId}`);
}

if (Number(selected.row.catalogEntryCount || 0) === 64) {
  assert(model.entries.length === 64, `expected 64 entries from current imported evidence, got ${model.entries.length}`);
}

assert(model.catalogSummary.tastyOrangeFound === true, 'TastyOrange should be present in the current imported evidence');
assert(model.catalogSummary.collectorFound === false, 'Collector should not be present in the current imported evidence');

for (const fieldName of ['PerkType', 'Rarity', 'Cooldown', 'Icon', 'Description', 'DisplayName', 'BaseValue', 'Value', 'Multiplier']) {
  const coverage = model.catalogSummary.fieldCoverage.find((item) => item.fieldName === fieldName);
  assert(coverage, `missing field coverage for ${fieldName}`);
}

const tastyOrange = model.entries.find((entry) => /TastyOrange/.test(`${entry.shortName} ${entry.fullName}`));
assert(tastyOrange, 'TastyOrange entry should exist');
assert(tastyOrange.enumFields.Rarity && tastyOrange.enumFields.Rarity.decoded === true, 'Rarity should remain decoded');
assert(tastyOrange.enumFields.PerkType && tastyOrange.enumFields.PerkType.decoded === true, 'PerkType should remain decoded');
assert(tastyOrange.scalarFields.Cooldown && tastyOrange.scalarFields.Cooldown.decoded === true, 'Cooldown should remain decoded');
assert(!Object.prototype.hasOwnProperty.call(tastyOrange.scalarFields, 'BaseValue'), 'BaseValue must not be treated as a scalar');
assert(Object.prototype.hasOwnProperty.call(tastyOrange.objectRefFields, 'BaseValue'), 'BaseValue must remain an object_ref field');
assert(Object.prototype.hasOwnProperty.call(tastyOrange.objectRefFields, 'Icon'), 'Icon must remain an object_ref field');
assert(tastyOrange.decodeNeededFields.includes('BaseValue'), 'BaseValue should be marked decode-needed');
assert(tastyOrange.decodeNeededFields.includes('Icon'), 'Icon should be marked decode-needed');
assert(tastyOrange.objectRefFields.BaseValue.decodeNeeded === true, 'BaseValue object_ref should be decode-needed');
assert(tastyOrange.objectRefFields.Icon.decodeNeeded === true, 'Icon object_ref should be decode-needed');

const csvText = fs.readFileSync(csvOut, 'utf8');
assert(csvText.startsWith('catalogIndex,shortName,fullName,sourceClass,PerkType,Rarity,PerkRarity,Tier,PerkTier,Type,Category,Cooldown,Icon,readStatus,readableFieldCount,objectRefFieldCount,decodeNeededFieldCount'), 'CSV header should include the expected columns');
assert(csvText.includes('DA_Perk_TastyOrange'), 'CSV should include TastyOrange');

const markdownText = fs.readFileSync(markdownOut, 'utf8');
assert(markdownText.includes('RuntimeProbe catalog evidence is read-only'), 'generated Markdown should include the read-only warning');
assert(markdownText.includes('RuntimeProbe catalog evidence is not permission to mutate DataAssets.'), 'generated Markdown should include the no-mutation warning');
assert(markdownText.includes('## TastyOrange Spotlight'), 'generated Markdown should include the TastyOrange spotlight');

const frameworkDoc = fs.readFileSync(path.join(repoRoot, 'docs', 'CRABMODFRAMEWORK_DATAASSET_CATALOG.md'), 'utf8');
assert(frameworkDoc.includes('RuntimeProbe catalog evidence is not permission to mutate DataAssets.'), 'framework doc should repeat the no-mutation warning');

const docsIndex = fs.readFileSync(path.join(repoRoot, 'docs', 'README.md'), 'utf8');
assert(docsIndex.includes('Perk DataAsset Catalog'), 'docs index should link to the perk catalog docs');
'@

node $NodeTestPath $ToolPath $RepoRoot $WorkRoot
if ($LASTEXITCODE -ne 0) { throw "perk dataasset catalog docs tests failed." }

Write-Host "CrabRuntimeProbe perk dataasset catalog docs checks passed."
