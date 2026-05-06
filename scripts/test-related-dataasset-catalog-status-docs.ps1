[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$WorkRoot = Join-Path $RepoRoot "dist\test-related-dataasset-catalog-status-docs-work"
$ToolPath = Join-Path $RepoRoot "tools\extract_related_dataasset_catalog_status.js"

if (Test-Path -LiteralPath $WorkRoot) {
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$NodeTestPath = Join-Path $WorkRoot "related-dataasset-catalog-status-test.js"
Set-Content -LiteralPath $NodeTestPath -Encoding ASCII -Value @'
const fs = require('fs');
const path = require('path');

const tool = require(process.argv[2]);
const repoRoot = process.argv[3];
const workRoot = process.argv[4];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

tool.generateRelatedDataAssetCatalogStatusOutputs({
  repoRoot,
  outputRoot: workRoot,
  quiet: true
});

const families = [
  {
    familyId: 'weaponmod',
    markdown: 'WEAPONMOD_DATAASSET_CATALOG.md',
    json: path.join('data', 'weaponmod_dataasset_catalog.latest.json'),
    csv: path.join('data', 'weaponmod_dataasset_catalog.latest.csv'),
    playerStateArrayProperty: 'CrabPS.WeaponMods',
    wrapperClass: 'CrabWeaponMod',
    dataAssetProperty: 'CrabWeaponMod.WeaponModDA',
    slotScalarProperty: 'CrabPS.NumWeaponModSlots',
    phaseId: 'weaponmod-da-catalog-read'
  },
  {
    familyId: 'abilitymod',
    markdown: 'ABILITYMOD_DATAASSET_CATALOG.md',
    json: path.join('data', 'abilitymod_dataasset_catalog.latest.json'),
    csv: path.join('data', 'abilitymod_dataasset_catalog.latest.csv'),
    playerStateArrayProperty: 'CrabPS.AbilityMods',
    wrapperClass: 'CrabAbilityMod',
    dataAssetProperty: 'CrabAbilityMod.AbilityModDA',
    slotScalarProperty: 'CrabPS.NumAbilityModSlots',
    phaseId: 'abilitymod-da-catalog-read'
  },
  {
    familyId: 'meleemod',
    markdown: 'MELEEMOD_DATAASSET_CATALOG.md',
    json: path.join('data', 'meleemod_dataasset_catalog.latest.json'),
    csv: path.join('data', 'meleemod_dataasset_catalog.latest.csv'),
    playerStateArrayProperty: 'CrabPS.MeleeMods',
    wrapperClass: 'CrabMeleeMod',
    dataAssetProperty: 'CrabMeleeMod.MeleeModDA',
    slotScalarProperty: 'CrabPS.NumMeleeModSlots',
    phaseId: 'meleemod-da-catalog-read'
  },
  {
    familyId: 'relic',
    markdown: 'RELIC_DATAASSET_CATALOG.md',
    json: path.join('data', 'relic_dataasset_catalog.latest.json'),
    csv: path.join('data', 'relic_dataasset_catalog.latest.csv'),
    playerStateArrayProperty: 'CrabPS.Relics',
    wrapperClass: 'CrabRelic',
    dataAssetProperty: 'CrabRelic.RelicDA',
    slotScalarProperty: '',
    phaseId: 'relic-da-catalog-read'
  }
];

for (const family of families) {
  const markdownPath = path.join(workRoot, 'docs', family.markdown);
  const jsonPath = path.join(workRoot, 'docs', family.json);
  const csvPath = path.join(workRoot, 'docs', family.csv);
  assert(fs.existsSync(markdownPath), `expected ${family.markdown}`);
  assert(fs.existsSync(jsonPath), `expected ${family.json}`);
  assert(fs.existsSync(csvPath), `expected ${family.csv}`);

  const model = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
  assert(model.generatedAt, `${family.familyId} generatedAt missing`);
  assert(model.familyId === family.familyId, `${family.familyId} familyId mismatch`);
  assert(model.catalogSummary.status === 'no-imported-catalog-snapshot', `${family.familyId} should remain no-imported-catalog-snapshot`);
  assert(Array.isArray(model.entries) && model.entries.length === 0, `${family.familyId} should have zero entries`);
  assert(model.catalogSummary.importedCatalogSnapshotFound === false, `${family.familyId} should not claim imported snapshot`);
  assert(model.catalogSummary.campaignPhase.phaseId === family.phaseId, `${family.familyId} phase mismatch`);
  assert(model.catalogSummary.campaignPhase.implemented === false, `${family.familyId} phase should remain placeholder`);
  assert(model.catalogSummary.readOnlyNotice === 'RuntimeProbe catalog evidence is read-only and is not permission to mutate DataAssets.', `${family.familyId} readOnlyNotice mismatch`);
  assert(model.knownModel.playerStateArrayProperty === family.playerStateArrayProperty, `${family.familyId} playerStateArrayProperty mismatch`);
  assert(model.knownModel.wrapperClass === family.wrapperClass, `${family.familyId} wrapperClass mismatch`);
  assert(model.knownModel.dataAssetProperty === family.dataAssetProperty, `${family.familyId} dataAssetProperty mismatch`);
  assert(model.knownModel.slotScalarProperty === family.slotScalarProperty, `${family.familyId} slotScalarProperty mismatch`);
  assert(Array.isArray(model.catalogSummary.relatedRuntimeEvidenceKinds) && model.catalogSummary.relatedRuntimeEvidenceKinds.length > 0, `${family.familyId} should preserve related runtime evidence kinds`);

  const csvText = fs.readFileSync(csvPath, 'utf8');
  assert(csvText.startsWith('catalogIndex,shortName,fullName,sourceClass,wrapperClass,dataAssetProperty,readStatus,notes'), `${family.familyId} CSV header mismatch`);

  const markdownText = fs.readFileSync(markdownPath, 'utf8');
  assert(markdownText.includes('RuntimeProbe catalog evidence is read-only and is not permission to mutate DataAssets.'), `${family.familyId} markdown missing read-only warning`);
  assert(markdownText.includes('Imported read-only catalog snapshot selected: no'), `${family.familyId} markdown missing snapshot status`);
  assert(markdownText.includes('RuntimeProbe catalog evidence is not permission to mutate DataAssets.'), `${family.familyId} markdown missing no-mutation warning`);
}
'@

node $NodeTestPath $ToolPath $RepoRoot $WorkRoot
if ($LASTEXITCODE -ne 0) { throw "related dataasset catalog status docs tests failed." }

Write-Host "CrabRuntimeProbe related dataasset catalog status docs checks passed."
