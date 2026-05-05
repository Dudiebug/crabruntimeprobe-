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

if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "allowResourceVisibilityProbes") -ne "false") {
  throw "default config expected allowResourceVisibilityProbes = false."
}
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "allowInventoryArrayShallowProbes") -ne "false") {
  throw "default config expected allowInventoryArrayShallowProbes = false."
}
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "allowInventoryArrayShapeConfirmProbes") -ne "false") {
  throw "default config expected allowInventoryArrayShapeConfirmProbes = false."
}
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "allowInventoryUserdataIntrospectionProbes") -ne "false") {
  throw "default config expected allowInventoryUserdataIntrospectionProbes = false."
}

$probeRegistry = Get-Content -Raw -LiteralPath $ProbeRegistryPath
$probeRunner = Get-Content -Raw -LiteralPath $ProbeRunnerPath
foreach ($required in @(
  "ResourceVisibility.PlayerState.Sample",
  "ResourceVisibility.Health.Sample",
  "ResourceVisibility.Resources.Sample",
  "ResourceVisibility.Slots.Sample",
  "ResourceVisibility.Equipment.Sample",
  "ResourceVisibility.InventoryArrays.ShallowSample",
  "GetPropertyValueCountOnly",
  "no element dereference, InventoryInfo, or Enhancements"
)) {
  if ($probeRegistry -notmatch [regex]::Escape($required)) {
    throw "probe_registry.lua missing resource visibility probe/content: $required"
  }
}
if ($probeRunner -notmatch [regex]::Escape("probe.set == 'multiplayer-resource-visibility-read' and not (config.allowIdentityProbes and config.allowHealthProbes and config.allowResourceVisibilityProbes)")) {
  throw "multiplayer-resource-visibility-read probes must be gated by identity, health, and resource visibility gates."
}

$WorkRoot = Join-Path $RepoRoot "dist\test-resource-visibility-work"
if (Test-Path -LiteralPath $WorkRoot) {
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $WorkRoot "evidence\runtime\resourcevisible") | Out-Null
Copy-Item -LiteralPath (Join-Path $RepoRoot "campaign") -Destination (Join-Path $WorkRoot "campaign") -Recurse

$safeGates = '"allowHudTickHook":false,"allowUnknownRoleProbes":false,"allowJoinedClientDeepProbes":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":true,"allowIdentityProbes":true,"allowRawIdentityEvidence":false,"allowResourceVisibilityProbes":true,"allowInventoryArrayShallowProbes":false,"allowInventoryArrayShapeConfirmProbes":false,"allowInventoryUserdataIntrospectionProbes":false,"allowWriteProbes":false,"allowRpcProbes":false'
$SessionDir = Join-Path $WorkRoot "evidence\runtime\resourcevisible"
Set-Content -LiteralPath (Join-Path $SessionDir "access_evidence.jsonl") -Encoding ASCII -Value @(
  ('{"timestamp":"2026-05-05T00:00:01Z","sessionId":"resourcevisible","probeId":"ResourceVisibility.PlayerState.Sample","probeName":"ResourceVisibility.PlayerState.Sample","probeSet":"multiplayer-resource-visibility-read","category":"resource-visibility","symbol":"PlayerState.Identity","owner":"PlayerState","member":"PlayerName UniqueId","accessMethod":"GetPropertyValue","accessKind":"resourceVisibilityIdentity","mode":"active","tickDriver":"executeDelay","tick":100,"context":"multiplayer","role":"joined-client","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"resource_visibility_identity","valueSummary":"visiblePlayerCount=2 sampledPlayerStateCount=2 rawIdentityEvidence=false","visiblePlayerCount":2,"sampledPlayerStateCount":2,"visiblePlayerCap":16,"displayNameFingerprints":["abc12345:len7","feedcafe:len5"],"stableIdFingerprints":["def67890:len17","0123abcd:len17"],"identityRawRedacted":true,"rawIdentityEvidence":false,"readableCrystalsCount":2,"readableSlotsCount":2,"readableEquipmentCount":2,"readableInventoryArrayCount":2,"readableHealthCount":2,"resourceVisibilityClass":"remote-visible","supportsP2PResourceMerge":"yes","fieldsVisibleAcrossMultiple":["Crystals","NumWeaponModSlots","WeaponDA","WeaponMods"],"fieldsOnlyVisibleOnLocal":[],"fieldsNilOrErrors":["Keys"],"nonIdentityResourceCategoryEvaluated":true,"safetyGates":{' + $safeGates + '}}'),
  ('{"timestamp":"2026-05-05T00:00:02Z","sessionId":"resourcevisible","probeId":"ResourceVisibility.Resources.Sample","probeName":"ResourceVisibility.Resources.Sample","probeSet":"multiplayer-resource-visibility-read","category":"resource-visibility","symbol":"CrabPS.Crystals","owner":"CrabPS","member":"Crystals Keys","accessMethod":"GetPropertyValue","accessKind":"getProperty","mode":"active","tickDriver":"executeDelay","tick":110,"context":"multiplayer","role":"joined-client","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"resource_visibility_resources","valueSummary":"category=resources visiblePlayerCount=2 sampledPlayerStateCount=2 readableCrystals=2 readableSlots=2 readableEquipment=2 readableInventoryArrayCounts=2 class=remote-visible rawIdentityEvidence=false","visiblePlayerCount":2,"sampledPlayerStateCount":2,"readableCrystalsCount":2,"readableSlotsCount":2,"readableEquipmentCount":2,"readableInventoryArrayCount":2,"readableHealthCount":2,"resourceVisibilityClass":"remote-visible","supportsP2PResourceMerge":"yes","fieldsVisibleAcrossMultiple":["Crystals","NumWeaponModSlots","WeaponDA","WeaponMods"],"fieldsOnlyVisibleOnLocal":[],"fieldsNilOrErrors":["Keys"],"nonIdentityResourceCategoryEvaluated":true,"rawIdentityEvidence":false,"safetyGates":{' + $safeGates + '}}')
)
Set-Content -LiteralPath (Join-Path $SessionDir "probe_results.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-05T00:00:01Z","sessionId":"resourcevisible","event":"ResourceVisibility.PlayerState.Sample","probeName":"ResourceVisibility.PlayerState.Sample","result":"ok"}',
  '{"timestamp":"2026-05-05T00:00:02Z","sessionId":"resourcevisible","event":"ResourceVisibility.Resources.Sample","probeName":"ResourceVisibility.Resources.Sample","result":"ok"}'
)
Set-Content -LiteralPath (Join-Path $SessionDir "session_manifest.json") -Encoding ASCII -Value ('{"sessionId":"resourcevisible","probeSet":"multiplayer-resource-visibility-read","tickDriver":"executeDelay","config":{"mode":"active","probeSet":"multiplayer-resource-visibility-read","tickDriver":"executeDelay",' + $safeGates + '},"safetyGates":{' + $safeGates + '},"activeResearchGates":["allowHealthProbes","allowIdentityProbes","allowResourceVisibilityProbes"],"warning":"research gates enabled: allowHealthProbes, allowIdentityProbes, allowResourceVisibilityProbes"}')

$NodeTestPath = Join-Path $WorkRoot "resource-classifier-test.js"
Set-Content -LiteralPath $NodeTestPath -Encoding ASCII -Value @'
const helpers = require(process.argv[2]);
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
let result = helpers.classifyResourceVisibilityEvidence([
  { probeName: 'ResourceVisibility.Resources.Sample', sampledPlayerStateCount: 1, visiblePlayerCount: 1, readableCrystalsCount: 1, readableSlotsCount: 1, readableEquipmentCount: 1, readableInventoryArrayCount: 1, rawIdentityEvidence: false, safetyGates: { allowRawIdentityEvidence: false } }
]);
assert(result.status === 'local_only_evidence', `one-player sample got ${result.status}`);
result = helpers.classifyResourceVisibilityEvidence([
  { probeName: 'ResourceVisibility.Resources.Sample', sampledPlayerStateCount: 2, visiblePlayerCount: 2, readableCrystalsCount: 2, readableSlotsCount: 2, readableEquipmentCount: 2, readableInventoryArrayCount: 2, fieldsVisibleAcrossMultiple: ['Crystals', 'WeaponMods'], rawIdentityEvidence: false, safetyGates: { allowRawIdentityEvidence: false } }
]);
assert(result.status === 'passed', `remote-visible sample got ${result.status}`);
'@
node $NodeTestPath (Join-Path $RepoRoot "tools\campaign_helpers.js")
if ($LASTEXITCODE -ne 0) { throw "resource visibility classifier tests failed." }

Push-Location $WorkRoot
try {
  node (Join-Path $RepoRoot "tools\generate_access_docs.js")
  node (Join-Path $RepoRoot "tools\generate_campaign_docs.js") --state (Join-Path $WorkRoot "evidence\campaign_state.json") --out (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") --write-state --quiet
} finally {
  Pop-Location
}

Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Resource visibility samples: 2"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Summary: remote-visible"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Fields visible across more than one PlayerState: Crystals, NumWeaponModSlots, WeaponDA, WeaponMods"
Assert-Contains -Path (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") -Expected "Supports future P2P resource merge design: yes"
Assert-Contains -Path (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") -Expected "No writes/RPCs/HUD hooks/deep array element reads/InventoryInfo/Enhancements are part of this phase."

Write-Host "CrabRuntimeProbe resource visibility probe checks passed."
