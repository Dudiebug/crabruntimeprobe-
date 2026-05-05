[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

function Assert-Contains {
  param(
    [string]$Path,
    [string]$Expected
  )

  $text = Get-Content -Raw -LiteralPath $Path
  if ($text -notmatch [regex]::Escape($Expected)) {
    throw "$Path missing expected content: $Expected"
  }
}

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$SourceConfigPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\config.txt"
$ProbeRegistryPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\probe_registry.lua"
$ProbeRunnerPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\probe_runner.lua"
$PlanPath = Join-Path $RepoRoot "campaign\campaign_plan.crabruntimeprobe-read-map.json"
$QuickCampaignCollectPath = Join-Path $RepoRoot "scripts\quick-campaign-collect.ps1"
$RunLocalDiagnosticCyclePath = Join-Path $RepoRoot "scripts\run-local-diagnostic-cycle.ps1"

if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "allowInventoryArrayShapeConfirmProbes") -ne "false") {
  throw "default config expected allowInventoryArrayShapeConfirmProbes = false."
}

$plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json -ErrorAction Stop
$phase = @($plan.phases | Where-Object { $_.phaseId -eq "local-inventory-array-shape-confirm" })[0]
if ($null -eq $phase) { throw "campaign plan missing local-inventory-array-shape-confirm." }
if ($phase.probeSet -ne "local-inventory-array-shape-confirm") { throw "shape confirm phase has wrong probeSet." }
if ($phase.requiredGates.allowInventoryArrayShapeConfirmProbes -ne $true) { throw "shape confirm phase must enable allowInventoryArrayShapeConfirmProbes." }
foreach ($gate in @("allowInventoryArrayShallowProbes", "allowInventoryUserdataIntrospectionProbes", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowWriteProbes", "allowRpcProbes", "allowHudTickHook", "allowRawIdentityEvidence", "allowHealthProbes", "allowIdentityProbes", "allowResourceVisibilityProbes", "allowUnknownRoleProbes", "allowJoinedClientDeepProbes")) {
  if (@($phase.forbiddenGates) -notcontains $gate) {
    throw "shape confirm phase must forbid $gate."
  }
}

$runner = Get-Content -Raw -LiteralPath $ProbeRunnerPath
if ($runner -notmatch [regex]::Escape("probe.set == 'local-inventory-array-shape-confirm' and not config.allowInventoryArrayShapeConfirmProbes")) {
  throw "shape confirm probes must be gated by allowInventoryArrayShapeConfirmProbes."
}

$quickCollect = Get-Content -Raw -LiteralPath $QuickCampaignCollectPath
if ($quickCollect -notmatch [regex]::Escape('$PhaseId -eq "local-inventory-array-shape-confirm"')) {
  throw "quick-campaign-collect.ps1 must route local-inventory-array-shape-confirm."
}
if ($quickCollect -notmatch [regex]::Escape("-CollectLocalInventoryArrayShapeConfirm")) {
  throw "quick-campaign-collect.ps1 must invoke CollectLocalInventoryArrayShapeConfirm."
}

$cycle = Get-Content -Raw -LiteralPath $RunLocalDiagnosticCyclePath
if ($cycle -notmatch [regex]::Escape('[switch]$CollectLocalInventoryArrayShapeConfirm')) {
  throw "run-local-diagnostic-cycle.ps1 must expose CollectLocalInventoryArrayShapeConfirm."
}
if ($cycle -notmatch [regex]::Escape('-AllowInventoryArrayShapeConfirmProbes:($Mode -eq "CollectLocalInventoryArrayShapeConfirm")')) {
  throw "CollectLocalInventoryArrayShapeConfirm must allow only allowInventoryArrayShapeConfirmProbes."
}
foreach ($expected in @(
  "local_inventory_shape_confirm_probe_ran",
  "local_inventory_shape_confirm_array_value_kinds",
  "local_inventory_shape_confirm_no_array_count",
  "local_inventory_shape_confirm_no_array_traversal",
  "local_inventory_shape_confirm_no_element_dereference",
  "crash_after_prepare",
  "crash_suspect"
)) {
  if ($cycle -notmatch [regex]::Escape($expected)) {
    throw "run-local-diagnostic-cycle.ps1 missing shape-confirm summary field: $expected"
  }
}

$registry = Get-Content -Raw -LiteralPath $ProbeRegistryPath
$helperStart = $registry.IndexOf("buildLocalInventoryShapeConfirmCache")
$helperEnd = $registry.IndexOf("localInventoryShapeConfirmMeta")
$probeStart = $registry.IndexOf("Inventory.LocalArrays.ShapeConfirm")
$probeEnd = $registry.IndexOf("FindAllOf.CrabHC.Availability")
if ($helperStart -lt 0 -or $helperEnd -le $helperStart -or $probeStart -lt 0 -or $probeEnd -le $probeStart) { throw "could not isolate shape confirm probe block." }
$shapeBlock = $registry.Substring($helperStart, $helperEnd - $helperStart) + "`n" + $registry.Substring($probeStart, $probeEnd - $probeStart)
foreach ($required in @(
  "Inventory.LocalArrays.ShapeConfirm",
  "buildLocalInventoryShapeConfirmCache",
  "safe.getProperty(playerState, fieldName)",
  "noElementDereference = true",
  "noArrayCount = true",
  "noArrayTraversal = true",
  "noInventoryInfo = true",
  "noEnhancements = true",
  "crashAttributionMarker = 'shape-confirm'"
)) {
  if ($shapeBlock -notmatch [regex]::Escape($required)) {
    throw "shape confirm probe block missing $required."
  }
}
foreach ($forbidden in @("safe.countArrayLimited", "safe.forEachArrayLimited", "safe.getArrayElement", "getArrayElement", "InventoryInfo')", "Enhancements')", ":get(")) {
  if ($shapeBlock -match [regex]::Escape($forbidden)) {
    throw "shape confirm probe block must not contain $forbidden."
  }
}

$WorkRoot = Join-Path $RepoRoot "dist\test-local-inventory-array-shape-confirm-work"
if (Test-Path -LiteralPath $WorkRoot) {
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $WorkRoot "evidence\runtime\shapeconfirm") | Out-Null
Copy-Item -LiteralPath (Join-Path $RepoRoot "campaign") -Destination (Join-Path $WorkRoot "campaign") -Recurse

$safeGates = '"allowHudTickHook":false,"allowUnknownRoleProbes":false,"allowJoinedClientDeepProbes":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowIdentityProbes":false,"allowRawIdentityEvidence":false,"allowResourceVisibilityProbes":false,"allowInventoryArrayShallowProbes":false,"allowInventoryArrayShapeConfirmProbes":true,"allowInventoryUserdataIntrospectionProbes":false,"allowWriteProbes":false,"allowRpcProbes":false'
$SessionDir = Join-Path $WorkRoot "evidence\runtime\shapeconfirm"
$shapeRow = ('{"timestamp":"2026-05-05T08:00:01Z","sessionId":"shapeconfirm","probeId":"Inventory.LocalArrays.ShapeConfirm","probeName":"Inventory.LocalArrays.ShapeConfirm","probeSet":"local-inventory-array-shape-confirm","category":"inventory-local-shape-confirm","symbol":"CrabPS.WeaponMods","owner":"CrabPS","member":"WeaponMods AbilityMods MeleeMods Perks Relics","accessMethod":"GetPropertyValueShapeConfirm","accessKind":"localInventoryArrayShapeConfirm","mode":"active","tickDriver":"executeDelay","tick":100,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"local_inventory_array_shape_confirm","valueSummary":"category=shape-confirm localPlayerStatePresent=true fieldsReadable=5 fieldsNilOrUnsupported=0 noArrayCount=true noArrayTraversal=true noElementDereference=true crashAttributionMarker=shape-confirm","sourceScope":"local_player_state_inventory_shape_confirm","sourcePath":"CrabPC.PlayerState","sourceClass":"CrabPS","localPlayerStatePresent":true,"arrayFieldNames":["WeaponMods","AbilityMods","MeleeMods","Perks","Relics"],"arrayValueKinds":{"WeaponMods":"userdata","AbilityMods":"userdata","MeleeMods":"userdata","Perks":"userdata","Relics":"userdata"},"arrayPropertiesPresent":{"WeaponMods":true,"AbilityMods":true,"MeleeMods":true,"Perks":true,"Relics":true},"arrayTostringKinds":{"WeaponMods":"string","AbilityMods":"string","MeleeMods":"string","Perks":"string","Relics":"string"},"slotScalarValues":{"NumWeaponModSlots":24,"NumAbilityModSlots":12,"NumMeleeModSlots":12,"NumPerkSlots":24},"fieldResults":{"WeaponMods":"present","AbilityMods":"present","MeleeMods":"present","Perks":"present","Relics":"present"},"fieldsReadable":["WeaponMods","AbilityMods","MeleeMods","Perks","Relics"],"fieldsNilOrUnsupported":[],"noElementDereference":true,"noArrayCount":true,"noArrayTraversal":true,"noInventoryInfo":true,"noEnhancements":true,"crashAttributionMarker":"shape-confirm","safetyGates":{' + $safeGates + '}}')
Set-Content -LiteralPath (Join-Path $SessionDir "access_evidence.jsonl") -Encoding ASCII -Value @($shapeRow)
Set-Content -LiteralPath (Join-Path $SessionDir "probe_results.jsonl") -Encoding ASCII -Value @($shapeRow)
Set-Content -LiteralPath (Join-Path $SessionDir "session_manifest.json") -Encoding ASCII -Value ('{"sessionId":"shapeconfirm","probeSet":"local-inventory-array-shape-confirm","tickDriver":"executeDelay","config":{"mode":"active","probeSet":"local-inventory-array-shape-confirm","tickDriver":"executeDelay",' + $safeGates + '},"safetyGates":{' + $safeGates + '},"activeResearchGates":["allowInventoryArrayShapeConfirmProbes"]}')
Set-Content -LiteralPath (Join-Path $SessionDir "diagnostic_summary.txt") -Encoding ASCII -Value @(
  "sessionId = shapeconfirm",
  "local_inventory_shape_confirm_probe_ran = True",
  "local_inventory_shape_confirm_array_value_kinds = AbilityMods=userdata, MeleeMods=userdata, Perks=userdata, Relics=userdata, WeaponMods=userdata",
  "local_inventory_shape_confirm_no_array_count = True",
  "local_inventory_shape_confirm_no_array_traversal = True",
  "local_inventory_shape_confirm_no_element_dereference = True",
  "crash_after_prepare = True",
  "crash_suspect = True"
)

$NodeTestPath = Join-Path $WorkRoot "shape-confirm-classifier-test.js"
Set-Content -LiteralPath $NodeTestPath -Encoding ASCII -Value @'
const helpers = require(process.argv[2]);
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
const safeGates = {
  allowInventoryArrayShapeConfirmProbes: true,
  allowInventoryUserdataIntrospectionProbes: false,
  allowInventoryArrayShallowProbes: false,
  allowDeepArrayProbes: false,
  allowInventoryInfoProbes: false,
  allowWriteProbes: false,
  allowRpcProbes: false,
  allowHudTickHook: false,
  allowRawIdentityEvidence: false,
  allowHealthProbes: false,
  allowIdentityProbes: false,
  allowResourceVisibilityProbes: false,
  allowUnknownRoleProbes: false,
  allowJoinedClientDeepProbes: false
};
let result = helpers.classifyLocalInventoryArrayShapeConfirmEvidence([
  { probeName: 'Inventory.LocalArrays.ShapeConfirm', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], arrayValueKinds: { WeaponMods: 'userdata' }, arrayPropertiesPresent: { WeaponMods: true }, slotScalarValues: { NumWeaponModSlots: 24 }, noElementDereference: true, noArrayCount: true, noArrayTraversal: true, noInventoryInfo: true, noEnhancements: true, safetyGates: safeGates }
]);
assert(result.status === 'local_inventory_shape_confirmed', `shape-confirm should confirm, got ${result.status}`);
assert(result.arrayValueKinds.WeaponMods === 'userdata', 'shape-confirm should preserve userdata value kind');
result = helpers.classifyLocalInventoryArrayShapeConfirmEvidence([
  { probeName: 'Inventory.LocalArrays.ShapeConfirm', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], arrayValueKinds: { WeaponMods: 'userdata' }, arrayPropertiesPresent: { WeaponMods: true }, noElementDereference: true, noArrayCount: true, noArrayTraversal: true, noInventoryInfo: true, noEnhancements: true, safetyGates: safeGates }
], { crashSuspect: true });
assert(result.status === 'crash_suspect_local_inventory_shape_confirmed', `crash evidence should be crash-suspect, got ${result.status}`);
result = helpers.classifyLocalInventoryArrayShapeConfirmEvidence([
  { probeName: 'Inventory.LocalArrays.ShapeConfirm', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], arrayValueKinds: { WeaponMods: 'userdata' }, noElementDereference: true, noArrayCount: false, noArrayTraversal: true, noInventoryInfo: true, noEnhancements: true, safetyGates: safeGates }
]);
assert(result.status === 'failed', `shape-confirm count attempt should fail, got ${result.status}`);
result = helpers.classifyLocalInventoryArrayShapeConfirmEvidence([
  { probeName: 'Inventory.LocalArrays.ShapeConfirm', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], arrayValueKinds: { WeaponMods: 'userdata' }, noElementDereference: true, noArrayCount: true, noArrayTraversal: true, noInventoryInfo: true, noEnhancements: true, safetyGates: { ...safeGates, allowInventoryArrayShallowProbes: true } }
]);
assert(result.status === 'failed', `shape-confirm forbidden gate should fail, got ${result.status}`);
'@
node $NodeTestPath (Join-Path $RepoRoot "tools\campaign_helpers.js")
if ($LASTEXITCODE -ne 0) { throw "shape-confirm classifier tests failed." }

Push-Location $WorkRoot
try {
  node (Join-Path $RepoRoot "tools\generate_access_docs.js")
  node (Join-Path $RepoRoot "tools\generate_campaign_docs.js") --state (Join-Path $WorkRoot "evidence\campaign_state.json") --out (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") --write-state --quiet
} finally {
  Pop-Location
}

Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Local Inventory Array Shape Confirm Summary"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Local inventory shape confirm status: crash_suspect_local_inventory_shape_confirmed"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Array value kinds: AbilityMods=userdata, MeleeMods=userdata, Perks=userdata, Relics=userdata, WeaponMods=userdata"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Array counts attempted: no"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Array traversal attempted: no"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Array elements dereferenced: no"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "InventoryInfo read: no"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Enhancements read: no"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Shape confirm distinguishes userdata shape visibility from countable Lua table arrays"
Assert-Contains -Path (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") -Expected "Local Inventory Array Shape Confirm"
Assert-Contains -Path (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") -Expected "Local inventory shape confirm status: crash_suspect_local_inventory_shape_confirmed"

Write-Host "CrabRuntimeProbe local inventory array shape confirm probe checks passed."
