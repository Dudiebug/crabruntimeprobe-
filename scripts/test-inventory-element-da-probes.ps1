[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

function Assert-Contains {
  param([string]$Text, [string]$Expected, [string]$Label)
  if ($Text -notmatch [regex]::Escape($Expected)) {
    throw "$Label missing expected content: $Expected"
  }
}

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$SourceConfigPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\config.txt"
$ProbeRegistryPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\probe_registry.lua"
$ProbeRunnerPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\probe_runner.lua"
$PlanPath = Join-Path $RepoRoot "campaign\campaign_plan.crabruntimeprobe-read-map.json"
$QuickCampaignCollectPath = Join-Path $RepoRoot "scripts\quick-campaign-collect.ps1"
$QuickCampaignPreparePath = Join-Path $RepoRoot "scripts\quick-campaign-prepare.ps1"
$RunLocalDiagnosticCyclePath = Join-Path $RepoRoot "scripts\run-local-diagnostic-cycle.ps1"

if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "allowInventoryElementDataAssetReadProbes") -ne "false") {
  throw "default config expected allowInventoryElementDataAssetReadProbes = false."
}

$plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json -ErrorAction Stop
$phase = @($plan.phases | Where-Object { $_.phaseId -eq "inventory-element-da-read" })[0]
if ($null -eq $phase) { throw "campaign plan missing inventory-element-da-read." }
if ($phase.probeSet -ne "inventory-element-da-read") { throw "inventory-element-da-read phase has wrong probeSet." }
if ($phase.implemented -ne $true) { throw "inventory-element-da-read phase must be implemented." }
if ($phase.requiredGates.allowInventoryElementDataAssetReadProbes -ne $true) { throw "inventory-element-da-read phase must enable allowInventoryElementDataAssetReadProbes." }
if ($phase.requiredGates.allowDeepArrayProbes -eq $true) { throw "inventory-element-da-read must not enable broad deep array probes." }
if ($phase.nextPhase -ne "inventoryinfo-scalar-read") { throw "inventory-element-da-read nextPhase should remain inventoryinfo-scalar-read." }
foreach ($gate in @("allowInventoryArrayCountProbes", "allowInventoryArrayShapeConfirmProbes", "allowInventoryArrayShallowProbes", "allowInventoryUserdataIntrospectionProbes", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowWriteProbes", "allowRpcProbes", "allowHudTickHook", "allowRawIdentityEvidence", "allowHealthProbes", "allowIdentityProbes", "allowResourceVisibilityProbes", "allowCrystalsReadProbes", "allowSlotsReadProbes", "allowSafeScalarWatchProbes", "allowPerkDataAssetCatalogProbes", "allowMaxSafePlayRecorderProbes", "allowUnknownRoleProbes", "allowJoinedClientDeepProbes")) {
  if (@($phase.forbiddenGates) -notcontains $gate) {
    throw "inventory-element-da-read phase must forbid $gate."
  }
}

$runner = Get-Content -Raw -LiteralPath $ProbeRunnerPath
Assert-Contains -Text $runner -Expected "probe.set == 'inventory-element-da-read' and not config.allowInventoryElementDataAssetReadProbes" -Label "probe_runner.lua"

$quickPrepare = Get-Content -Raw -LiteralPath $QuickCampaignPreparePath
Assert-Contains -Text $quickPrepare -Expected "allowInventoryElementDataAssetReadProbes" -Label "quick-campaign-prepare.ps1"
Assert-Contains -Text $quickPrepare -Expected '-AllowInventoryElementDataAssetReadProbes:($phase.phaseId -eq "inventory-element-da-read")' -Label "quick-campaign-prepare.ps1"

$quickCollect = Get-Content -Raw -LiteralPath $QuickCampaignCollectPath
Assert-Contains -Text $quickCollect -Expected '$PhaseId -eq "inventory-element-da-read"' -Label "quick-campaign-collect.ps1"
Assert-Contains -Text $quickCollect -Expected "-CollectInventoryElementDARead" -Label "quick-campaign-collect.ps1"
foreach ($expected in @("inventory_element_da_confirmed", "inventory_element_da_no_nonempty_arrays", "inventory_element_da_unsupported", "inventory_element_da_not_found", "crash_suspect_inventory_element_da")) {
  Assert-Contains -Text $quickCollect -Expected $expected -Label "quick-campaign-collect.ps1"
}

$cycle = Get-Content -Raw -LiteralPath $RunLocalDiagnosticCyclePath
Assert-Contains -Text $cycle -Expected '[switch]$CollectInventoryElementDARead' -Label "run-local-diagnostic-cycle.ps1"
Assert-Contains -Text $cycle -Expected '-AllowInventoryElementDataAssetReadProbes:($Mode -eq "CollectInventoryElementDARead")' -Label "run-local-diagnostic-cycle.ps1"
foreach ($expected in @("inventory_element_da_probe_ran", "inventory_element_da_classification", "inventory_element_da_nonempty_array_fields", "inventory_element_da_safety_violation")) {
  Assert-Contains -Text $cycle -Expected $expected -Label "run-local-diagnostic-cycle.ps1"
}

$registry = Get-Content -Raw -LiteralPath $ProbeRegistryPath
$helperStart = $registry.IndexOf("local function buildInventoryElementDAReadCache")
$helperEnd = $registry.IndexOf("local function integerLikeUInt32")
$probeStart = $registry.IndexOf("Inventory.LocalArrays.ElementDARead")
$probeEnd = $registry.IndexOf("Resource.Crystals.Read")
if ($helperStart -lt 0 -or $helperEnd -le $helperStart -or $probeStart -lt 0 -or $probeEnd -le $probeStart) { throw "could not isolate inventory element DA read probe block." }
$elementBlock = $registry.Substring($helperStart, $helperEnd - $helperStart) + "`n" + $registry.Substring($probeStart, $probeEnd - $probeStart)
foreach ($required in @("Inventory.LocalArrays.ElementDARead", "buildInventoryElementDAReadCache", "safe.getProperty(playerState, fieldName)", "safeLenOperator(value)", "unsupported_no_safe_first_element_helper", "WeaponModDA", "AbilityModDA", "MeleeModDA", "PerkDA", "RelicDA", "noArrayTraversal = true", "noFullArrayIteration = true", "cappedElementAccess = true", "maxElementsPerArray = 1", "noInventoryInfo = true", "noEnhancements = true", "noLevelRead = true", "noAccumulatedBuffRead = true", "noDataAssetMutation = true", "noFunctionCalls = true", "passiveOnly = true", "crashAttributionMarker = 'inventory-element-da-read'")) {
  Assert-Contains -Text $elementBlock -Expected $required -Label "inventory element DA probe block"
}
foreach ($forbidden in @("safe.forEachArrayLimited", "safe.getArrayElement", "getArrayElement", "forEachArrayLimited", ":get(", ":Get(", "pairs(value)", "ipairs(value)", "InventoryInfo')", "Enhancements')", "Level')", "AccumulatedBuff')", "allowWriteProbes = true", "allowRpcProbes = true", "allowHudTickHook = true", "allowDeepArrayProbes = true")) {
  if ($elementBlock -match [regex]::Escape($forbidden)) {
    throw "inventory element DA probe block must not contain $forbidden."
  }
}

$NodeTestPath = Join-Path $RepoRoot "dist\inventory-element-da-classifier-test.js"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $NodeTestPath) | Out-Null
Set-Content -LiteralPath $NodeTestPath -Encoding ASCII -Value @'
const helpers = require(process.argv[2]);
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
const safeGates = {
  allowInventoryElementDataAssetReadProbes: true,
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
  allowPerkDataAssetCatalogProbes: false,
  allowMaxSafePlayRecorderProbes: false,
  allowInventoryArrayShallowProbes: false,
  allowInventoryArrayShapeConfirmProbes: false,
  allowInventoryUserdataIntrospectionProbes: false,
  allowInventoryArrayCountProbes: false,
  allowWriteProbes: false,
  allowRpcProbes: false
};
const base = {
  probeName: 'Inventory.LocalArrays.ElementDARead',
  localPlayerStatePresent: true,
  valueKinds: { WeaponMods: 'userdata', AbilityMods: 'userdata', MeleeMods: 'userdata', Perks: 'userdata', Relics: 'userdata' },
  countResults: { WeaponMods: 1, AbilityMods: 0, MeleeMods: 0, Perks: 0, Relics: 0 },
  nonEmptyArrayFields: ['WeaponMods'],
  fieldResults: { WeaponMods: 'element_identity', AbilityMods: 'empty_array', MeleeMods: 'empty_array', Perks: 'empty_array', Relics: 'empty_array' },
  elementAccessAttempted: { WeaponMods: true },
  elementAccessMethods: { WeaponMods: 'capped_first_element_safe_helper' },
  elementAccessSupported: true,
  elementIdentities: { WeaponMods: { shortName: 'CrabWeaponMod_1', className: 'CrabWeaponMod' } },
  dataAssetIdentities: { WeaponMods: { fieldName: 'WeaponModDA', shortName: 'DA_WeaponMod_Test' } },
  dataAssetFieldResults: { WeaponMods: 'identity_read' },
  maxElementsPerArray: 1,
  noWrites: true,
  noRpcs: true,
  noHud: true,
  noBroadDeepArrays: true,
  noArrayTraversal: true,
  noFullArrayIteration: true,
  cappedElementAccess: true,
  noInventoryInfo: true,
  noEnhancements: true,
  noLevelRead: true,
  noAccumulatedBuffRead: true,
  noDataAssetMutation: true,
  noFunctionCalls: true,
  passiveOnly: true,
  safetyGates: safeGates
};
let result = helpers.classifyInventoryElementDataAssetEvidence([base]);
assert(result.status === 'inventory_element_da_confirmed', `expected confirmed, got ${result.status}`);
result = helpers.classifyInventoryElementDataAssetEvidence([{ ...base, countResults: { WeaponMods: 0, AbilityMods: 0, MeleeMods: 0, Perks: 0, Relics: 0 }, nonEmptyArrayFields: [], elementAccessAttempted: {}, elementAccessSupported: false, elementIdentities: {}, dataAssetIdentities: {}, fieldResults: { WeaponMods: 'empty_array', AbilityMods: 'empty_array', MeleeMods: 'empty_array', Perks: 'empty_array', Relics: 'empty_array' } }]);
assert(result.status === 'inventory_element_da_no_nonempty_arrays', `expected no non-empty arrays, got ${result.status}`);
result = helpers.classifyInventoryElementDataAssetEvidence([{ ...base, elementAccessSupported: false, elementAccessAttempted: { WeaponMods: false }, elementAccessMethods: { WeaponMods: 'unsupported_no_safe_first_element_helper' }, elementIdentities: {}, dataAssetIdentities: {}, fieldResults: { WeaponMods: 'element_access_unsupported', AbilityMods: 'empty_array', MeleeMods: 'empty_array', Perks: 'empty_array', Relics: 'empty_array' } }]);
assert(result.status === 'inventory_element_da_unsupported', `expected unsupported, got ${result.status}`);
result = helpers.classifyInventoryElementDataAssetEvidence([{ ...base, localPlayerStatePresent: false, countResults: {}, nonEmptyArrayFields: [], elementIdentities: {}, dataAssetIdentities: {}, fieldResults: { WeaponMods: 'no_local_player_state', AbilityMods: 'no_local_player_state', MeleeMods: 'no_local_player_state', Perks: 'no_local_player_state', Relics: 'no_local_player_state' } }]);
assert(result.status === 'inventory_element_da_not_found', `expected not found, got ${result.status}`);
result = helpers.classifyInventoryElementDataAssetEvidence([base], { crashSuspect: true });
assert(result.status === 'crash_suspect_inventory_element_da', `expected crash suspect, got ${result.status}`);
for (const marker of ['noInventoryInfo', 'noEnhancements', 'noLevelRead', 'noAccumulatedBuffRead', 'noArrayTraversal']) {
  result = helpers.classifyInventoryElementDataAssetEvidence([{ ...base, [marker]: false }]);
  assert(result.status === 'failed', `${marker} marker violation must fail`);
}
result = helpers.classifyInventoryElementDataAssetEvidence([{ ...base, maxElementsPerArray: 2 }]);
assert(result.status === 'failed', 'multiple element cap violation must fail');
result = helpers.classifyInventoryElementDataAssetEvidence([{ ...base, safetyGates: { ...safeGates, allowDeepArrayProbes: true } }]);
assert(result.status === 'failed', 'forbidden gate must fail');
result = helpers.classifyInventoryElementDataAssetEvidence([{ ...base, safetyGates: { ...safeGates, allowInventoryElementDataAssetReadProbes: false } }]);
assert(result.status === 'failed', 'missing narrow gate must fail');
'@
node $NodeTestPath (Join-Path $RepoRoot "tools\campaign_helpers.js")
if ($LASTEXITCODE -ne 0) { throw "inventory element DA classifier tests failed." }

Write-Host "CrabRuntimeProbe inventory-element-da-read checks passed."
