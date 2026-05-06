[CmdletBinding()]
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
    throw "$Label missing expected content: $Expected"
  }
}

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$SourceConfigPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\config.txt"
$ProbeRegistryPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\probe_registry.lua"
$ProbeRunnerPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\probe_runner.lua"
$PlanPath = Join-Path $RepoRoot "campaign\campaign_plan.crabruntimeprobe-read-map.json"
$QuickCampaignCollectPath = Join-Path $RepoRoot "scripts\quick-campaign-collect.ps1"
$RunLocalDiagnosticCyclePath = Join-Path $RepoRoot "scripts\run-local-diagnostic-cycle.ps1"

if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "allowInventoryArrayCountProbes") -ne "false") {
  throw "default config expected allowInventoryArrayCountProbes = false."
}

$plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json -ErrorAction Stop
$phase = @($plan.phases | Where-Object { $_.phaseId -eq "inventory-array-count-read" })[0]
if ($null -eq $phase) { throw "campaign plan missing inventory-array-count-read." }
if ($phase.probeSet -ne "inventory-array-count-read") { throw "inventory-array-count-read phase has wrong probeSet." }
if ($phase.implemented -ne $true) { throw "inventory-array-count-read phase must be implemented." }
if ($phase.requiredGates.allowInventoryArrayCountProbes -ne $true) { throw "inventory-array-count-read phase must enable allowInventoryArrayCountProbes." }
if ($phase.nextPhase -ne "inventory-element-da-read") { throw "inventory-array-count-read nextPhase should remain inventory-element-da-read." }
foreach ($gate in @("allowInventoryArrayShapeConfirmProbes", "allowInventoryArrayShallowProbes", "allowInventoryUserdataIntrospectionProbes", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowWriteProbes", "allowRpcProbes", "allowHudTickHook", "allowRawIdentityEvidence", "allowHealthProbes", "allowIdentityProbes", "allowResourceVisibilityProbes", "allowCrystalsReadProbes", "allowSlotsReadProbes", "allowSafeScalarWatchProbes", "allowPerkDataAssetCatalogProbes", "allowMaxSafePlayRecorderProbes", "allowUnknownRoleProbes", "allowJoinedClientDeepProbes")) {
  if (@($phase.forbiddenGates) -notcontains $gate) {
    throw "inventory-array-count-read phase must forbid $gate."
  }
}

$runner = Get-Content -Raw -LiteralPath $ProbeRunnerPath
Assert-Contains -Text $runner -Expected "probe.set == 'inventory-array-count-read' and not config.allowInventoryArrayCountProbes" -Label "probe_runner.lua"

$quickCollect = Get-Content -Raw -LiteralPath $QuickCampaignCollectPath
Assert-Contains -Text $quickCollect -Expected '$PhaseId -eq "inventory-array-count-read"' -Label "quick-campaign-collect.ps1"
Assert-Contains -Text $quickCollect -Expected "-CollectInventoryArrayCountRead" -Label "quick-campaign-collect.ps1"

$cycle = Get-Content -Raw -LiteralPath $RunLocalDiagnosticCyclePath
Assert-Contains -Text $cycle -Expected '[switch]$CollectInventoryArrayCountRead' -Label "run-local-diagnostic-cycle.ps1"
Assert-Contains -Text $cycle -Expected '-AllowInventoryArrayCountProbes:($Mode -eq "CollectInventoryArrayCountRead")' -Label "run-local-diagnostic-cycle.ps1"
foreach ($expected in @(
  "inventory_array_count_probe_ran",
  "inventory_array_count_classification",
  "inventory_array_count_results",
  "inventory_array_count_safety_violation"
)) {
  Assert-Contains -Text $cycle -Expected $expected -Label "run-local-diagnostic-cycle.ps1"
}

$registry = Get-Content -Raw -LiteralPath $ProbeRegistryPath
$helperStart = $registry.IndexOf("local function buildInventoryArrayCountReadCache")
$helperEnd = $registry.IndexOf("local function buildInventoryElementDAReadCache")
$probeStart = $registry.IndexOf("Inventory.LocalArrays.CountRead")
$probeEnd = $registry.IndexOf("Resource.Crystals.Read")
if ($helperStart -lt 0 -or $helperEnd -le $helperStart -or $probeStart -lt 0 -or $probeEnd -le $probeStart) { throw "could not isolate inventory array count read probe block." }
$countBlock = $registry.Substring($helperStart, $helperEnd - $helperStart) + "`n" + $registry.Substring($probeStart, $probeEnd - $probeStart)
foreach ($required in @(
  "Inventory.LocalArrays.CountRead",
  "buildInventoryArrayCountReadCache",
  "safe.getProperty(playerState, fieldName)",
  "safeLenOperator(value)",
  "lua_len_operator_pcall",
  "noInventoryTraversal = true",
  "noArrayTraversal = true",
  "noElementDereference = true",
  "noItemDataAssetRead = true",
  "noInventoryInfo = true",
  "noEnhancements = true",
  "noWrites = true",
  "noRpcs = true",
  "noHud = true",
  "noDeepArrays = true",
  "noDataAssetMutation = true",
  "passiveOnly = true",
  "crashAttributionMarker = 'inventory-array-count-read'"
)) {
  Assert-Contains -Text $countBlock -Expected $required -Label "inventory count probe block"
}
foreach ($forbidden in @("safe.countArrayLimited", "safe.forEachArrayLimited", "safe.getArrayElement", "getArrayElement", "forEachArrayLimited", ":get(", ":Get(", "pairs(value)", "ipairs(value)", "InventoryInfo')", "Enhancements')", "WeaponModDA", "AbilityModDA", "MeleeModDA", "PerkDA", "RelicDA", "allowWriteProbes = true", "allowRpcProbes = true", "allowHudTickHook = true", "allowDeepArrayProbes = true")) {
  if ($countBlock -match [regex]::Escape($forbidden)) {
    throw "inventory count probe block must not contain $forbidden."
  }
}

$NodeTestPath = Join-Path $RepoRoot "dist\inventory-array-count-classifier-test.js"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $NodeTestPath) | Out-Null
Set-Content -LiteralPath $NodeTestPath -Encoding ASCII -Value @'
const helpers = require(process.argv[2]);
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
const safeGates = {
  allowInventoryArrayCountProbes: true,
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
  allowWriteProbes: false,
  allowRpcProbes: false
};
const base = {
  probeName: 'Inventory.LocalArrays.CountRead',
  localPlayerStatePresent: true,
  fieldsReadable: ['WeaponMods'],
  fieldsNilOrUnsupported: ['AbilityMods', 'MeleeMods', 'Perks', 'Relics'],
  valueKinds: { WeaponMods: 'userdata', AbilityMods: 'userdata', MeleeMods: 'userdata', Perks: 'userdata', Relics: 'userdata' },
  tostringPrefixes: { WeaponMods: 'userdata:<redacted>' },
  countAttempted: { WeaponMods: true, AbilityMods: true, MeleeMods: true, Perks: true, Relics: true },
  countMethods: { WeaponMods: 'lua_len_operator_pcall', AbilityMods: 'lua_len_operator_pcall', MeleeMods: 'lua_len_operator_pcall', Perks: 'lua_len_operator_pcall', Relics: 'lua_len_operator_pcall' },
  countResults: { WeaponMods: 3 },
  countErrors: { AbilityMods: 'unsupported', MeleeMods: 'unsupported', Perks: 'unsupported', Relics: 'unsupported' },
  fieldResults: { WeaponMods: 'count', AbilityMods: 'count_unsupported', MeleeMods: 'count_unsupported', Perks: 'count_unsupported', Relics: 'count_unsupported' },
  noWrites: true,
  noRpcs: true,
  noHud: true,
  noDeepArrays: true,
  noInventoryTraversal: true,
  noArrayTraversal: true,
  noElementDereference: true,
  noItemDataAssetRead: true,
  noInventoryInfo: true,
  noEnhancements: true,
  noDataAssetMutation: true,
  passiveOnly: true,
  safetyGates: safeGates
};
let result = helpers.classifyInventoryArrayCountEvidence([base]);
assert(result.status === 'inventory_array_count_confirmed', `expected confirmed, got ${result.status}`);
assert(result.countResultFields.includes('WeaponMods'), 'count result field should be preserved');
result = helpers.classifyInventoryArrayCountEvidence([{ ...base, fieldsReadable: [], countResults: {}, countErrors: { WeaponMods: 'unsupported', AbilityMods: 'unsupported', MeleeMods: 'unsupported', Perks: 'unsupported', Relics: 'unsupported' }, fieldResults: { WeaponMods: 'count_unsupported', AbilityMods: 'count_unsupported', MeleeMods: 'count_unsupported', Perks: 'count_unsupported', Relics: 'count_unsupported' } }]);
assert(result.status === 'inventory_array_count_unsupported', `expected unsupported, got ${result.status}`);
result = helpers.classifyInventoryArrayCountEvidence([{ ...base, localPlayerStatePresent: false, fieldsReadable: [], countResults: {}, fieldResults: { WeaponMods: 'no_local_player_state', AbilityMods: 'no_local_player_state', MeleeMods: 'no_local_player_state', Perks: 'no_local_player_state', Relics: 'no_local_player_state' } }]);
assert(result.status === 'inventory_array_count_not_found', `expected not found, got ${result.status}`);
result = helpers.classifyInventoryArrayCountEvidence([base], { crashSuspect: true });
assert(result.status === 'crash_suspect_inventory_array_count', `expected crash suspect, got ${result.status}`);
result = helpers.classifyInventoryArrayCountEvidence([{ ...base, noArrayTraversal: false }]);
assert(result.status === 'failed', 'array traversal marker violation must fail');
result = helpers.classifyInventoryArrayCountEvidence([{ ...base, noElementDereference: false }]);
assert(result.status === 'failed', 'element dereference marker violation must fail');
result = helpers.classifyInventoryArrayCountEvidence([{ ...base, noInventoryInfo: false }]);
assert(result.status === 'failed', 'InventoryInfo marker violation must fail');
result = helpers.classifyInventoryArrayCountEvidence([{ ...base, noEnhancements: false }]);
assert(result.status === 'failed', 'Enhancements marker violation must fail');
result = helpers.classifyInventoryArrayCountEvidence([{ ...base, safetyGates: { ...safeGates, allowDeepArrayProbes: true } }]);
assert(result.status === 'failed', 'forbidden gate must fail');
'@
node $NodeTestPath (Join-Path $RepoRoot "tools\campaign_helpers.js")
if ($LASTEXITCODE -ne 0) { throw "inventory array count classifier tests failed." }

Write-Host "CrabRuntimeProbe inventory-array-count-read checks passed."
