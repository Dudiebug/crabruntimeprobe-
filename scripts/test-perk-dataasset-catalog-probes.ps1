param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Expected,
    [string]$Label
  )
  if ($Text -notmatch [regex]::Escape($Expected)) {
    throw "$Label did not contain expected text: $Expected"
  }
}

function Assert-NotContains {
  param(
    [string]$Text,
    [string]$Unexpected,
    [string]$Label
  )
  if ($Text -match [regex]::Escape($Unexpected)) {
    throw "$Label contained unexpected text: $Unexpected"
  }
}

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$SourceConfigPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\config.txt"
$ProbeRegistryPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\probe_registry.lua"
$ProbeRunnerPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\probe_runner.lua"
$PlanPath = Join-Path $RepoRoot "campaign\campaign_plan.crabruntimeprobe-read-map.json"
$WorkRoot = Join-Path $RepoRoot "dist\test-perk-dataasset-catalog-work"

if (Test-Path -LiteralPath $WorkRoot) {
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

Assert-CrabRuntimeProbeConfig -ConfigPath $SourceConfigPath -Label "source config"
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "allowPerkDataAssetCatalogProbes") -ne "false") {
  throw "default allowPerkDataAssetCatalogProbes must remain false."
}
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "perkDataAssetCatalogMaxCandidates") -ne "64") {
  throw "default perkDataAssetCatalogMaxCandidates must remain 64."
}
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "perkDataAssetCatalogMaxFields") -ne "32") {
  throw "default perkDataAssetCatalogMaxFields must remain 32."
}

$registry = Get-Content -Raw -LiteralPath $ProbeRegistryPath
$runner = Get-Content -Raw -LiteralPath $ProbeRunnerPath
Assert-Contains -Text $runner -Expected "allowPerkDataAssetCatalogProbes" -Label "probe_runner.lua"
Assert-Contains -Text $registry -Expected "DataAsset.Perks.CatalogRead" -Label "probe_registry.lua"
Assert-Contains -Text $registry -Expected "PERK_DA_CLASS_CANDIDATES" -Label "probe_registry.lua"
Assert-Contains -Text $registry -Expected "PERK_DA_FIELD_ALLOWLIST" -Label "probe_registry.lua"
Assert-Contains -Text $registry -Expected "FindAllOfCappedCuratedClasses" -Label "probe_registry.lua"
Assert-Contains -Text $registry -Expected "noInventoryArrays = true" -Label "probe_registry.lua"
Assert-Contains -Text $registry -Expected "noArrayCount = true" -Label "probe_registry.lua"
Assert-Contains -Text $registry -Expected "noArrayTraversal = true" -Label "probe_registry.lua"
Assert-Contains -Text $registry -Expected "noElementDereference = true" -Label "probe_registry.lua"
Assert-Contains -Text $registry -Expected "noInventoryInfo = true" -Label "probe_registry.lua"
Assert-Contains -Text $registry -Expected "noEnhancements = true" -Label "probe_registry.lua"
Assert-Contains -Text $registry -Expected "noDataAssetMutation = true" -Label "probe_registry.lua"
Assert-Contains -Text $registry -Expected "noFunctionCalls = true" -Label "probe_registry.lua"

$catalogBlock = [regex]::Match($registry, "local PERK_DA_CLASS_CANDIDATES[\s\S]+?local function maxSafePlayState").Value
if ([string]::IsNullOrWhiteSpace($catalogBlock)) {
  throw "Could not isolate perk DataAsset catalog block."
}
Assert-NotContains -Text $catalogBlock -Unexpected "TastyOrange" -Label "perk catalog block"
Assert-NotContains -Text $catalogBlock -Unexpected "Collector" -Label "perk catalog block"
Assert-NotContains -Text $catalogBlock -Unexpected "ServerIncrementNumInventorySlots" -Label "perk catalog block"
Assert-NotContains -Text $catalogBlock -Unexpected "safe.getArrayElement" -Label "perk catalog block"

$NodeTestPath = Join-Path $WorkRoot "perk-dataasset-catalog-test.js"
Set-Content -LiteralPath $NodeTestPath -Encoding ASCII -Value @'
const helpers = require(process.argv[2]);
const repoRoot = process.argv[3];
const plan = helpers.loadPlan(repoRoot);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const phase = plan.phases.find((item) => item.phaseId === 'perk-da-catalog-read');
assert(phase, 'perk-da-catalog-read phase exists');
assert(phase.implemented === true, 'perk-da-catalog-read is implemented');
assert(phase.probeSet === 'perk-da-catalog-read', 'phase probeSet is perk-da-catalog-read');
assert(phase.nextPhase === 'inventory-array-shallow-read', 'perk catalog advances to inventory-array-shallow-read placeholder');

const safeWatch = plan.phases.find((item) => item.phaseId === 'safe-scalar-watch');
assert(safeWatch && safeWatch.nextPhase === 'perk-da-catalog-read', 'safe scalar watch advances to perk catalog');

const gates = helpers.gateConfigForPhase(phase);
assert(gates.allowPerkDataAssetCatalogProbes === true, 'perk catalog gate enabled for phase');
for (const key of [
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
  'allowMaxSafePlayRecorderProbes',
  'allowInventoryArrayShallowProbes',
  'allowInventoryArrayShapeConfirmProbes',
  'allowInventoryUserdataIntrospectionProbes',
  'allowWriteProbes',
  'allowRpcProbes'
]) {
  assert(gates[key] === false, `${key} must remain false`);
}

const baseRow = {
  probeName: 'DataAsset.Perks.CatalogRead',
  result: 'ok',
  discoveryAttempted: true,
  catalogFound: true,
  catalogEntryCount: 1,
  catalogCandidateCount: 1,
  catalogCandidateCap: 64,
  catalogFieldCap: 32,
  catalogEntries: [{ shortName: 'DA_Perk_Example', fullName: '/Game/Perks/DA_Perk_Example', className: 'CrabPerkDA', catalogIndex: 0, valid: true }],
  catalogReadStatuses: { DisplayName: 'read' },
  catalogValueKinds: { DisplayName: 'text' },
  noWrites: true,
  noRpcs: true,
  noHud: true,
  noDeepArrays: true,
  noInventoryArrays: true,
  noArrayCount: true,
  noArrayTraversal: true,
  noElementDereference: true,
  noInventoryInfo: true,
  noEnhancements: true,
  noDataAssetMutation: true,
  noFunctionCalls: true,
  safetyGates: {
    allowPerkDataAssetCatalogProbes: true,
    allowHudTickHook: false,
    allowUnknownRoleProbes: false,
    allowJoinedClientDeepProbes: false,
    allowDeepArrayProbes: false,
    allowInventoryInfoProbes: false,
    allowHealthProbes: false,
    allowIdentityProbes: false,
    allowRawIdentityEvidence: false,
    allowResourceVisibilityProbes: false,
    allowCrystalsReadProbes: false,
    allowSlotsReadProbes: false,
    allowSafeScalarWatchProbes: false,
    allowMaxSafePlayRecorderProbes: false,
    allowInventoryArrayShallowProbes: false,
    allowInventoryArrayShapeConfirmProbes: false,
    allowInventoryUserdataIntrospectionProbes: false,
    allowWriteProbes: false,
    allowRpcProbes: false
  }
};

let result = helpers.classifyPerkDataAssetCatalogEvidence([baseRow]);
assert(result.status === 'perk_da_catalog_confirmed', `expected confirmed, got ${result.status}`);
assert(result.noWrites && result.noRpcs && result.noHud && result.noDeepArrays, 'basic read-only markers must be true');
assert(result.noInventoryArrays && result.noArrayCount && result.noArrayTraversal && result.noElementDereference, 'array and inventory markers must be true');
assert(result.noInventoryInfo && result.noEnhancements && result.noDataAssetMutation && result.noFunctionCalls, 'forbidden read/mutation markers must be true');

result = helpers.classifyPerkDataAssetCatalogEvidence([{ ...baseRow, result: 'nil', catalogFound: false, catalogEntryCount: 0, catalogEntries: [] }]);
assert(result.status === 'perk_da_catalog_not_found', `expected not-found, got ${result.status}`);

result = helpers.classifyPerkDataAssetCatalogEvidence([{ ...baseRow, noDataAssetMutation: false }]);
assert(result.status === 'failed', 'missing/false safety markers must fail');

result = helpers.classifyPerkDataAssetCatalogEvidence([{ ...baseRow, safetyGates: { ...baseRow.safetyGates, allowWriteProbes: true } }]);
assert(result.status === 'failed', 'forbidden gates must fail');

result = helpers.classifyPerkDataAssetCatalogEvidence([{ ...baseRow, safetyGates: { ...baseRow.safetyGates, allowPerkDataAssetCatalogProbes: false } }]);
assert(result.status === 'failed', 'phase gate must be true for catalog evidence');

const completedBeforeSafeWatch = plan.phases
  .slice(0, plan.phases.findIndex((item) => item.phaseId === 'safe-scalar-watch'))
  .map((item) => ({ phaseId: item.phaseId, status: 'complete' }));
const slotsCompleteState = helpers.markCollected(plan, {
  campaign: plan.campaign,
  completedPhases: completedBeforeSafeWatch,
  partialPhases: [],
  failedPhases: [],
  blockedPhases: []
}, 'safe-scalar-watch', { status: 'safe_scalar_watch_observed_change' });
assert(slotsCompleteState.nextRecommendedPhase === 'perk-da-catalog-read', `expected perk-da-catalog-read, got ${slotsCompleteState.nextRecommendedPhase}`);

const perkCompleteState = helpers.markCollected(plan, slotsCompleteState, 'perk-da-catalog-read', { status: 'perk_da_catalog_confirmed' });
assert(perkCompleteState.nextRecommendedPhase === 'inventory-array-shallow-read', `expected inventory-array-shallow-read, got ${perkCompleteState.nextRecommendedPhase}`);
const perkNotFoundState = helpers.markCollected(plan, slotsCompleteState, 'perk-da-catalog-read', { status: 'perk_da_catalog_not_found' });
assert(perkNotFoundState.nextRecommendedPhase === 'inventory-array-shallow-read', `expected inventory-array-shallow-read after not-found, got ${perkNotFoundState.nextRecommendedPhase}`);
'@

node $NodeTestPath (Join-Path $RepoRoot "tools\campaign_helpers.js") $RepoRoot
if ($LASTEXITCODE -ne 0) { throw "perk DataAsset catalog node tests failed." }

Write-Host "CrabRuntimeProbe perk DataAsset catalog checks passed."
