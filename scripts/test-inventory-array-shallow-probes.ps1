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

if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "allowInventoryArrayShallowProbes") -ne "false") {
  throw "default config expected allowInventoryArrayShallowProbes = false."
}
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "allowInventoryArrayShapeConfirmProbes") -ne "false") {
  throw "default config expected allowInventoryArrayShapeConfirmProbes = false."
}

$plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json -ErrorAction Stop
$phase = @($plan.phases | Where-Object { $_.phaseId -eq "local-inventory-array-shallow-read" })[0]
if ($null -eq $phase) { throw "campaign plan missing local-inventory-array-shallow-read." }
if ($phase.probeSet -ne "local-inventory-array-shallow-read") { throw "local inventory phase has wrong probeSet." }
if ($phase.requiredGates.allowInventoryArrayShallowProbes -ne $true) { throw "local inventory phase must enable allowInventoryArrayShallowProbes." }
if (($phase.requiredGates.PSObject.Properties.Name -contains "allowInventoryArrayShapeConfirmProbes") -and $phase.requiredGates.allowInventoryArrayShapeConfirmProbes -eq $true) {
  throw "local inventory shallow phase must not enable allowInventoryArrayShapeConfirmProbes."
}
foreach ($gate in @("allowDeepArrayProbes", "allowInventoryInfoProbes", "allowWriteProbes", "allowRpcProbes", "allowHudTickHook", "allowRawIdentityEvidence")) {
  if (@($phase.forbiddenGates) -notcontains $gate) {
    throw "local inventory phase must forbid $gate."
  }
}

$runner = Get-Content -Raw -LiteralPath $ProbeRunnerPath
if ($runner -notmatch [regex]::Escape("probe.set == 'local-inventory-array-shallow-read' and not config.allowInventoryArrayShallowProbes")) {
  throw "local inventory probes must be gated by allowInventoryArrayShallowProbes."
}

$quickCollect = Get-Content -Raw -LiteralPath $QuickCampaignCollectPath
if ($quickCollect -notmatch [regex]::Escape('$PhaseId -eq "local-inventory-array-shallow-read"')) {
  throw "quick-campaign-collect.ps1 must route local-inventory-array-shallow-read."
}
if ($quickCollect -notmatch [regex]::Escape("-CollectLocalInventoryArrayShallow")) {
  throw "quick-campaign-collect.ps1 must invoke CollectLocalInventoryArrayShallow."
}

$cycle = Get-Content -Raw -LiteralPath $RunLocalDiagnosticCyclePath
if ($cycle -notmatch [regex]::Escape('[switch]$CollectLocalInventoryArrayShallow')) {
  throw "run-local-diagnostic-cycle.ps1 must expose CollectLocalInventoryArrayShallow."
}
if ($cycle -notmatch [regex]::Escape('-AllowInventoryArrayShallowProbes:($Mode -eq "CollectLocalInventoryArrayShallow")')) {
  throw "CollectLocalInventoryArrayShallow must allow only allowInventoryArrayShallowProbes."
}

$registry = Get-Content -Raw -LiteralPath $ProbeRegistryPath
foreach ($required in @(
  "Inventory.LocalArrays.Shape",
  "Inventory.LocalArrays.CountOnly",
  "Inventory.LocalSlots.Sample",
  "CrabPC.PlayerState",
  "noElementDereference = true",
  "LOCAL_INVENTORY_ARRAY_COUNT_CAP"
)) {
  if ($registry -notmatch [regex]::Escape($required)) {
    throw "probe_registry.lua missing local inventory probe/content: $required"
  }
}

$start = $registry.IndexOf("Inventory.LocalSlots.Sample")
$end = $registry.IndexOf("FindAllOf.CrabHC.Availability")
if ($start -lt 0 -or $end -le $start) { throw "could not isolate local inventory probe block." }
$localBlock = $registry.Substring($start, $end - $start)
if ([string]::IsNullOrWhiteSpace($localBlock)) { throw "could not isolate local inventory probe block." }
foreach ($forbidden in @("getArrayElement", ":get(", "safe.getProperty(playerState, 'InventoryInfo')", "safe.getProperty(playerState, 'Enhancements')", "FindFirstOf.CrabHC", "FindAllOf.CrabHC")) {
  if ($localBlock -match [regex]::Escape($forbidden)) {
    throw "local inventory probe block must not contain $forbidden."
  }
}

$WorkRoot = Join-Path $RepoRoot "dist\test-local-inventory-array-work"
if (Test-Path -LiteralPath $WorkRoot) {
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $WorkRoot "evidence\runtime\localinventory") | Out-Null
Copy-Item -LiteralPath (Join-Path $RepoRoot "campaign") -Destination (Join-Path $WorkRoot "campaign") -Recurse

$safeGates = '"allowHudTickHook":false,"allowUnknownRoleProbes":false,"allowJoinedClientDeepProbes":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowIdentityProbes":false,"allowRawIdentityEvidence":false,"allowResourceVisibilityProbes":false,"allowInventoryArrayShallowProbes":true,"allowInventoryArrayShapeConfirmProbes":false,"allowWriteProbes":false,"allowRpcProbes":false'
$SessionDir = Join-Path $WorkRoot "evidence\runtime\localinventory"
Set-Content -LiteralPath (Join-Path $SessionDir "access_evidence.jsonl") -Encoding ASCII -Value @(
  ('{"timestamp":"2026-05-05T00:00:01Z","sessionId":"localinventory","probeId":"Inventory.LocalArrays.Shape","probeName":"Inventory.LocalArrays.Shape","probeSet":"local-inventory-array-shallow-read","category":"inventory-local","symbol":"CrabPS.WeaponMods","owner":"CrabPS","member":"WeaponMods AbilityMods MeleeMods Perks Relics","accessMethod":"GetPropertyValueShapeOnly","accessKind":"localInventoryArrayShape","mode":"active","tickDriver":"executeDelay","tick":100,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"local_inventory_array_shape","valueSummary":"category=array-shape localPlayerStatePresent=true fieldsReadable=1 fieldsNilOrUnsupported=4 countCap=64 noElementDereference=true","sourceScope":"local_player_state_inventory_arrays","sourcePath":"CrabPC.PlayerState","sourceClass":"CrabPS","localPlayerStatePresent":true,"arrayFieldNames":["WeaponMods","AbilityMods","MeleeMods","Perks","Relics"],"arrayValueKinds":{"WeaponMods":"table","AbilityMods":"nil","MeleeMods":"nil","Perks":"nil","Relics":"nil"},"arrayCounts":{"WeaponMods":0},"arrayCountCap":64,"slotScalarValues":{"NumWeaponModSlots":3,"NumAbilityModSlots":1,"NumMeleeModSlots":1,"NumPerkSlots":2},"fieldResults":{"WeaponMods":"count","AbilityMods":"nil","MeleeMods":"nil","Perks":"nil","Relics":"nil"},"fieldsReadable":["WeaponMods"],"fieldsNilOrUnsupported":["AbilityMods","MeleeMods","Perks","Relics"],"noElementDereference":true,"safetyGates":{' + $safeGates + '}}')
)
Set-Content -LiteralPath (Join-Path $SessionDir "probe_results.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-05T00:00:01Z","sessionId":"localinventory","event":"Inventory.LocalArrays.Shape","probeName":"Inventory.LocalArrays.Shape","result":"ok"}'
)
Set-Content -LiteralPath (Join-Path $SessionDir "session_manifest.json") -Encoding ASCII -Value ('{"sessionId":"localinventory","probeSet":"local-inventory-array-shallow-read","tickDriver":"executeDelay","config":{"mode":"active","probeSet":"local-inventory-array-shallow-read","tickDriver":"executeDelay",' + $safeGates + '},"safetyGates":{' + $safeGates + '},"activeResearchGates":["allowInventoryArrayShallowProbes"]}')

$NodeTestPath = Join-Path $WorkRoot "local-inventory-classifier-test.js"
Set-Content -LiteralPath $NodeTestPath -Encoding ASCII -Value @'
const helpers = require(process.argv[2]);
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
let result = helpers.classifyLocalInventoryArrayEvidence([
  { probeName: 'Inventory.LocalArrays.Shape', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], arrayValueKinds: { WeaponMods: 'table' }, arrayCounts: { WeaponMods: 0 }, noElementDereference: true, safetyGates: { allowDeepArrayProbes: false, allowInventoryInfoProbes: false, allowWriteProbes: false, allowRpcProbes: false, allowHudTickHook: false, allowRawIdentityEvidence: false } }
]);
assert(result.status === 'passed', `local array shape/count got ${result.status}`);
result = helpers.classifyLocalInventoryArrayEvidence([
  { probeName: 'Inventory.LocalArrays.Shape', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods', 'AbilityMods'], arrayValueKinds: { WeaponMods: 'userdata', AbilityMods: 'userdata' }, arrayCounts: {}, noElementDereference: true, safetyGates: { allowDeepArrayProbes: false, allowInventoryInfoProbes: false, allowWriteProbes: false, allowRpcProbes: false, allowHudTickHook: false, allowRawIdentityEvidence: false, allowHealthProbes: false, allowIdentityProbes: false, allowResourceVisibilityProbes: false, allowInventoryArrayShallowProbes: true } }
]);
assert(result.status === 'passed', `userdata shape-visible evidence should not be hard failed, got ${result.status}`);
assert(result.hasCount === false, 'userdata shapes should not be reported as countable Lua tables');
result = helpers.classifyLocalInventoryArrayEvidence([
  { probeName: 'Inventory.LocalArrays.Shape', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], arrayValueKinds: { WeaponMods: 'userdata' }, arrayCounts: {}, noElementDereference: true, safetyGates: { allowDeepArrayProbes: false, allowInventoryInfoProbes: false, allowWriteProbes: false, allowRpcProbes: false, allowHudTickHook: false, allowRawIdentityEvidence: false, allowHealthProbes: false, allowIdentityProbes: false, allowResourceVisibilityProbes: false, allowInventoryArrayShallowProbes: true } }
], { crashSuspect: true });
assert(result.status === 'crash_suspect_local_inventory_shape_visible', `crash dump after prepare/run should classify as crash-suspect, got ${result.status}`);
result = helpers.classifyLocalInventoryArrayEvidence([
  { probeName: 'Inventory.LocalArrays.Shape', localPlayerStatePresent: true, fieldsReadable: [], arrayValueKinds: { WeaponMods: 'nil' }, noElementDereference: true, safetyGates: { allowDeepArrayProbes: false, allowInventoryInfoProbes: false, allowWriteProbes: false, allowRpcProbes: false, allowHudTickHook: false, allowRawIdentityEvidence: false } }
]);
assert(result.status === 'local_inventory_unresolved', `nil arrays got ${result.status}`);
result = helpers.classifyLocalInventoryArrayEvidence([
  { probeName: 'Inventory.LocalArrays.Shape', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], noElementDereference: false, safetyGates: { allowDeepArrayProbes: true } }
]);
assert(result.status === 'failed', `unsafe local arrays got ${result.status}`);
'@
node $NodeTestPath (Join-Path $RepoRoot "tools\campaign_helpers.js")
if ($LASTEXITCODE -ne 0) { throw "local inventory classifier tests failed." }

Push-Location $WorkRoot
try {
  node (Join-Path $RepoRoot "tools\generate_access_docs.js")
  node (Join-Path $RepoRoot "tools\generate_campaign_docs.js") --state (Join-Path $WorkRoot "evidence\campaign_state.json") --out (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") --write-state --quiet
} finally {
  Pop-Location
}

Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Local inventory array status: passed"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Array value kinds: AbilityMods=nil, MeleeMods=nil, Perks=nil, Relics=nil, WeaponMods=table"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Array counts available: yes, Lua table counts for WeaponMods"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Local inventory array visibility is separate from remote PlayerState inventory array visibility."
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected 'InventoryInfo and Enhancements were not read; writes/RPCs/HUD hooks/deep arrays were disabled.'
Assert-Contains -Path (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") -Expected "Local inventory array status: passed"
Assert-Contains -Path (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") -Expected "Array elements dereferenced: no"
Assert-Contains -Path (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") -Expected "Array counts available: yes, Lua table counts for WeaponMods"

Write-Host "CrabRuntimeProbe local inventory array shallow probe checks passed."
