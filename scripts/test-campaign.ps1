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

function Assert-UnsafeReadCampaignGatesFalse {
  param([string]$ConfigPath)

foreach ($key in @(
    "allowHudTickHook",
    "allowWriteProbes",
    "allowRpcProbes",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowRawIdentityEvidence"
  )) {
    $value = Get-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key $key
    if ($value -ne "false") {
      throw "Campaign read config expected $key = false, got '$value'"
    }
  }
}

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$PlanPath = Join-Path $RepoRoot "campaign\campaign_plan.crabruntimeprobe-read-map.json"
$SourceConfigPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\config.txt"
$WorkRoot = Join-Path $RepoRoot "dist\test-campaign-work"
$GameBin = Join-Path $WorkRoot "game-bin"
$StatePath = Join-Path $WorkRoot "campaign_state.json"
$DocPath = Join-Path $WorkRoot "CAMPAIGN_STATUS.md"

if (Test-Path -LiteralPath $WorkRoot) {
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json -ErrorAction Stop
if ($plan.campaign -ne "crabruntimeprobe-read-map") {
  throw "campaign plan parses but has wrong name."
}
if (@($plan.phases).Count -lt 13) {
  throw "campaign plan should contain the requested initial phases."
}

Assert-CrabRuntimeProbeConfig -ConfigPath $SourceConfigPath -Label "source config"
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "tickDriver") -ne "none") {
  throw "default config tickDriver must remain none."
}
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "probeSet") -ne "shallow-core") {
  throw "default config probeSet must remain shallow-core."
}
foreach ($key in @("allowHudTickHook", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowHealthProbes", "allowIdentityProbes", "allowRawIdentityEvidence", "allowResourceVisibilityProbes", "allowInventoryArrayShallowProbes", "allowInventoryArrayShapeConfirmProbes", "allowInventoryUserdataIntrospectionProbes", "allowWriteProbes", "allowRpcProbes")) {
  if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key $key) -ne "false") {
    throw "default config expected $key = false."
  }
}

$NodeTestPath = Join-Path $WorkRoot "campaign-helper-test.js"
Set-Content -LiteralPath $NodeTestPath -Encoding ASCII -Value @'
const path = require('path');
const helpers = require(process.argv[2]);
const repoRoot = process.argv[3];
const plan = helpers.loadPlan(repoRoot);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

let state = helpers.reconcileState(plan, {
  campaign: plan.campaign,
  completedPhases: [{ phaseId: 'smoke-startup' }],
  failedPhases: [],
  blockedPhases: []
}, repoRoot);
assert(state.nextRecommendedPhase === 'executeDelay', `expected executeDelay, got ${state.nextRecommendedPhase}`);

state = helpers.reconcileState(plan, {
  campaign: plan.campaign,
  completedPhases: [
    { phaseId: 'smoke-startup' },
    { phaseId: 'executeDelay' },
    { phaseId: 'observe-context' },
    { phaseId: 'equipment-property-read' },
    { phaseId: 'health-playerstate-read' },
    { phaseId: 'health-playerstate-watch' },
    { phaseId: 'multiplayer-roster-read' },
    { phaseId: 'multiplayer-health-playerstate-watch' }
  ],
  failedPhases: [],
  blockedPhases: []
}, repoRoot);
assert(state.nextRecommendedPhase === 'multiplayer-resource-visibility-read', `expected multiplayer-resource-visibility-read, got ${state.nextRecommendedPhase}`);

const defaultState = helpers.reconcileState(plan, null, repoRoot);
assert(Array.isArray(defaultState.completedPhases), 'state initializes completedPhases');
assert(defaultState.blockedPhases.some((entry) => entry.phaseId === 'crystals-read'), 'unimplemented crystals phase is blocked');

for (const phase of plan.phases) {
  if (phase.implemented !== true) continue;
  const gates = helpers.gateConfigForPhase(phase);
  assert(gates.allowWriteProbes === false, `${phase.phaseId} enabled writes`);
  assert(gates.allowRpcProbes === false, `${phase.phaseId} enabled RPCs`);
  assert(gates.allowHudTickHook === false, `${phase.phaseId} enabled HUD`);
  assert(gates.allowDeepArrayProbes === false, `${phase.phaseId} enabled deep arrays`);
  assert(gates.allowInventoryInfoProbes === false, `${phase.phaseId} enabled InventoryInfo`);
  assert(gates.allowRawIdentityEvidence === false, `${phase.phaseId} enabled raw identity evidence`);
  if (phase.phaseId !== 'local-inventory-array-shallow-read') {
    assert(gates.allowInventoryArrayShallowProbes === false, `${phase.phaseId} enabled local inventory arrays outside local phase`);
  }
  if (phase.phaseId !== 'local-inventory-array-shape-confirm') {
    assert(gates.allowInventoryArrayShapeConfirmProbes === false, `${phase.phaseId} enabled local inventory shape confirm outside shape confirm phase`);
  }
  if (phase.phaseId !== 'local-inventory-userdata-introspection') {
    assert(gates.allowInventoryUserdataIntrospectionProbes === false, `${phase.phaseId} enabled local inventory userdata introspection outside userdata phase`);
  }
  if (!/^health-|^multiplayer-health-/.test(phase.phaseId) && phase.phaseId !== 'multiplayer-resource-visibility-read') {
    assert(gates.allowHealthProbes === false, `${phase.phaseId} enabled health outside health phases`);
  }
  if (phase.phaseId !== 'multiplayer-roster-read' && phase.phaseId !== 'multiplayer-resource-visibility-read') {
    assert(gates.allowIdentityProbes === false, `${phase.phaseId} enabled identity outside roster phase`);
  }
  if (phase.phaseId !== 'multiplayer-resource-visibility-read') {
    assert(gates.allowResourceVisibilityProbes === false, `${phase.phaseId} enabled resource visibility outside resource phase`);
  }
}

const afterObserve = helpers.reconcileState(plan, {
  campaign: plan.campaign,
  completedPhases: [
    { phaseId: 'smoke-startup' },
    { phaseId: 'executeDelay' },
    { phaseId: 'observe-context' },
    { phaseId: 'equipment-property-read' },
    { phaseId: 'health-playerstate-read' },
    { phaseId: 'health-playerstate-watch' }
  ],
  failedPhases: [],
  blockedPhases: []
}, repoRoot);
assert(afterObserve.nextRecommendedPhase === 'multiplayer-roster-read', `expected multiplayer-roster-read, got ${afterObserve.nextRecommendedPhase}`);

const redactedLocalRows = [
  { probeName: 'Identity.LocalPlayer.Sample', result: 'ok', localPlayerPresent: true, rawIdentityEvidence: false, identityRawRedacted: true, displayNameFingerprints: ['abc:len3'], safetyGates: { allowRawIdentityEvidence: false } },
  { probeName: 'Identity.VisiblePlayers.Sample', result: 'nil', visiblePlayerCount: 0, rawIdentityEvidence: false, identityRawRedacted: true, safetyGates: { allowRawIdentityEvidence: false } }
];
let roster = helpers.classifyRosterEvidence(redactedLocalRows);
assert(roster.status === 'local_identity_confirmed', `expected local_identity_confirmed, got ${roster.status}`);
assert(roster.rawIdentityLeak === false, 'redacted identity row must not count as raw identity leak');

roster = helpers.classifyRosterEvidence([
  { probeName: 'Identity.LocalPlayer.Sample', result: 'ok', localPlayerPresent: true, rawIdentityEvidence: true, safetyGates: { allowRawIdentityEvidence: false } }
]);
assert(roster.rawIdentityLeak === true && roster.status === 'failed', 'rawIdentityEvidence=true must fail when raw identity evidence is disabled');

roster = helpers.classifyRosterEvidence([
  { probeName: 'Identity.LocalPlayer.Sample', result: 'ok', localPlayerPresent: true, rawIdentityEvidence: false, rawDisplayNames: ['ActualName'], safetyGates: { allowRawIdentityEvidence: false } }
]);
assert(roster.rawIdentityLeak === true && roster.status === 'failed', 'non-empty rawDisplayNames must fail when raw identity evidence is disabled');

roster = helpers.classifyRosterEvidence([
  { probeName: 'Identity.LocalPlayer.Sample', result: 'ok', localPlayerPresent: true, rawIdentityEvidence: false, rawStableIds: { local: 'SteamId' }, safetyGates: { allowRawIdentityEvidence: false } }
]);
assert(roster.rawIdentityLeak === true && roster.status === 'failed', 'non-empty rawStableIds must fail when raw identity evidence is disabled');

roster = helpers.classifyRosterEvidence([
  { probeName: 'Identity.LocalPlayer.Sample', result: 'ok', localPlayerPresent: true, rawIdentityEvidence: false, identityRawRedacted: true, displayNameFingerprints: ['abc:len3'], safetyGates: { allowRawIdentityEvidence: false } },
  { probeName: 'Identity.GameState.SourceCandidate', result: 'ok', sourceScope: 'runtime_roster_candidate', sourcePath: 'GameStateBase', visiblePlayerCount: 0, rawIdentityEvidence: false, safetyGates: { allowRawIdentityEvidence: false } },
  { probeName: 'Identity.PlayerArray.Shape', result: 'nil', sourcePath: 'GameStateBase.PlayerArray', playerArrayValueKind: 'nil', visiblePlayerCount: 0, rawIdentityEvidence: false, safetyGates: { allowRawIdentityEvidence: false } },
  { probeName: 'Identity.FindAll.PlayerStateCandidates', result: 'nil', sourcePath: 'FindAllOf(PlayerState,CrabPS)', visiblePlayerCount: 0, rawIdentityEvidence: false, safetyGates: { allowRawIdentityEvidence: false } }
]);
assert(roster.status === 'local_identity_confirmed', `candidate rows without visible players must not claim roster success, got ${roster.status}`);
assert(roster.visibleRosterConfirmed === false, 'candidate source rows with count 0 must leave visible roster unresolved');

let resources = helpers.classifyResourceVisibilityEvidence([
  { probeName: 'ResourceVisibility.Resources.Sample', result: 'ok', sampledPlayerStateCount: 1, visiblePlayerCount: 1, readableCrystalsCount: 1, readableSlotsCount: 0, readableEquipmentCount: 0, readableInventoryArrayCount: 0, rawIdentityEvidence: false, safetyGates: { allowRawIdentityEvidence: false } }
]);
assert(resources.status === 'local_only_evidence', `one-player resource sample must not complete phase, got ${resources.status}`);
resources = helpers.classifyResourceVisibilityEvidence([
  { probeName: 'ResourceVisibility.Resources.Sample', result: 'nil', sampledPlayerStateCount: 2, visiblePlayerCount: 2, readableCrystalsCount: 0, readableSlotsCount: 0, readableEquipmentCount: 0, readableInventoryArrayCount: 0, rawIdentityEvidence: false, safetyGates: { allowRawIdentityEvidence: false } }
]);
assert(resources.status === 'remote_resources_unresolved', `multi-player nil resources should be unresolved, got ${resources.status}`);
resources = helpers.classifyResourceVisibilityEvidence([
  { probeName: 'ResourceVisibility.Resources.Sample', result: 'ok', sampledPlayerStateCount: 2, visiblePlayerCount: 2, readableCrystalsCount: 2, readableSlotsCount: 2, readableEquipmentCount: 2, readableInventoryArrayCount: 2, fieldsVisibleAcrossMultiple: ['Crystals', 'WeaponMods'], rawIdentityEvidence: false, safetyGates: { allowRawIdentityEvidence: false } }
]);
assert(resources.status === 'passed' && resources.classification === 'remote-visible', 'complete multi-player resource visibility should pass');

let localInventory = helpers.classifyLocalInventoryArrayEvidence([
  { probeName: 'Inventory.LocalArrays.Shape', result: 'ok', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], fieldsNilOrUnsupported: ['Relics'], arrayValueKinds: { WeaponMods: 'table', Relics: 'nil' }, arrayCounts: { WeaponMods: 0 }, noElementDereference: true, safetyGates: { allowInventoryArrayShallowProbes: true, allowDeepArrayProbes: false, allowInventoryInfoProbes: false, allowWriteProbes: false, allowRpcProbes: false, allowHudTickHook: false, allowRawIdentityEvidence: false } }
]);
assert(localInventory.status === 'passed', `local inventory shape/count should pass, got ${localInventory.status}`);
localInventory = helpers.classifyLocalInventoryArrayEvidence([
  { probeName: 'Inventory.LocalArrays.Shape', result: 'nil', localPlayerStatePresent: true, fieldsReadable: [], fieldsNilOrUnsupported: ['WeaponMods'], arrayValueKinds: { WeaponMods: 'nil' }, noElementDereference: true, safetyGates: { allowInventoryArrayShallowProbes: true, allowDeepArrayProbes: false, allowInventoryInfoProbes: false, allowWriteProbes: false, allowRpcProbes: false, allowHudTickHook: false, allowRawIdentityEvidence: false } }
]);
assert(localInventory.status === 'local_inventory_unresolved', `all nil local inventory arrays should be unresolved, got ${localInventory.status}`);
localInventory = helpers.classifyLocalInventoryArrayEvidence([
  { probeName: 'Inventory.LocalArrays.Shape', result: 'ok', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], noElementDereference: false, safetyGates: { allowDeepArrayProbes: true } }
]);
assert(localInventory.status === 'failed', 'element dereference or unsafe gates must fail local inventory evidence');

let shapeConfirm = helpers.classifyLocalInventoryArrayShapeConfirmEvidence([
  { probeName: 'Inventory.LocalArrays.ShapeConfirm', result: 'ok', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], arrayValueKinds: { WeaponMods: 'userdata' }, arrayPropertiesPresent: { WeaponMods: true }, slotScalarValues: { NumWeaponModSlots: 24 }, noElementDereference: true, noArrayCount: true, noArrayTraversal: true, noInventoryInfo: true, noEnhancements: true, safetyGates: { allowInventoryArrayShapeConfirmProbes: true, allowInventoryArrayShallowProbes: false, allowDeepArrayProbes: false, allowInventoryInfoProbes: false, allowWriteProbes: false, allowRpcProbes: false, allowHudTickHook: false, allowRawIdentityEvidence: false, allowHealthProbes: false, allowIdentityProbes: false, allowResourceVisibilityProbes: false } }
]);
assert(shapeConfirm.status === 'local_inventory_shape_confirmed', `shape-confirm userdata evidence should confirm, got ${shapeConfirm.status}`);
shapeConfirm = helpers.classifyLocalInventoryArrayShapeConfirmEvidence([
  { probeName: 'Inventory.LocalArrays.ShapeConfirm', result: 'ok', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], arrayValueKinds: { WeaponMods: 'userdata' }, arrayPropertiesPresent: { WeaponMods: true }, noElementDereference: true, noArrayCount: true, noArrayTraversal: true, noInventoryInfo: true, noEnhancements: true, safetyGates: { allowInventoryArrayShapeConfirmProbes: true, allowInventoryArrayShallowProbes: false, allowDeepArrayProbes: false, allowInventoryInfoProbes: false, allowWriteProbes: false, allowRpcProbes: false, allowHudTickHook: false, allowRawIdentityEvidence: false, allowHealthProbes: false, allowIdentityProbes: false, allowResourceVisibilityProbes: false } }
], { crashSuspect: true });
assert(shapeConfirm.status === 'crash_suspect_local_inventory_shape_confirmed', `crash evidence should keep shape-confirm crash-suspect, got ${shapeConfirm.status}`);
shapeConfirm = helpers.classifyLocalInventoryArrayShapeConfirmEvidence([
  { probeName: 'Inventory.LocalArrays.ShapeConfirm', result: 'ok', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], arrayValueKinds: { WeaponMods: 'userdata' }, noElementDereference: true, noArrayCount: false, noArrayTraversal: true, noInventoryInfo: true, noEnhancements: true, safetyGates: { allowInventoryArrayShapeConfirmProbes: true, allowInventoryArrayShallowProbes: false } }
]);
assert(shapeConfirm.status === 'failed', 'shape-confirm must fail if count/traversal/element markers or safety gates are violated');

let userdata = helpers.classifyLocalInventoryUserdataIntrospectionEvidence([
  { probeName: 'Inventory.LocalArrays.UserdataIntrospection', result: 'ok', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], valueKinds: { WeaponMods: 'userdata' }, tostringKinds: { WeaponMods: 'string' }, tostringPrefixes: { WeaponMods: 'userdata:<redacted>' }, metatableKinds: { WeaponMods: 'table' }, metatableKeys: { WeaponMods: ['__len'] }, lenOperatorAttempted: { WeaponMods: true }, lenOperatorResults: { WeaponMods: 0 }, noElementDereference: true, noArrayTraversal: true, noInventoryInfo: true, noEnhancements: true, noWrites: true, noRpcs: true, safetyGates: { allowInventoryUserdataIntrospectionProbes: true, allowInventoryArrayShapeConfirmProbes: false, allowInventoryArrayShallowProbes: false, allowDeepArrayProbes: false, allowInventoryInfoProbes: false, allowWriteProbes: false, allowRpcProbes: false, allowHudTickHook: false, allowRawIdentityEvidence: false, allowHealthProbes: false, allowIdentityProbes: false, allowResourceVisibilityProbes: false } }
]);
assert(userdata.status === 'local_inventory_userdata_introspection_confirmed', `userdata introspection should confirm, got ${userdata.status}`);
userdata = helpers.classifyLocalInventoryUserdataIntrospectionEvidence([
  { probeName: 'Inventory.LocalArrays.UserdataIntrospection', result: 'ok', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], valueKinds: { WeaponMods: 'userdata' }, lenOperatorAttempted: { WeaponMods: true }, noElementDereference: true, noArrayTraversal: true, noInventoryInfo: true, noEnhancements: true, noWrites: true, noRpcs: true, safetyGates: { allowInventoryUserdataIntrospectionProbes: true, allowInventoryArrayShallowProbes: false } }
], { crashSuspect: true });
assert(userdata.status === 'crash_suspect_local_inventory_userdata_introspection', `crash evidence should keep userdata introspection crash-suspect, got ${userdata.status}`);
userdata = helpers.classifyLocalInventoryUserdataIntrospectionEvidence([
  { probeName: 'Inventory.LocalArrays.UserdataIntrospection', result: 'ok', localPlayerStatePresent: true, fieldsReadable: ['WeaponMods'], valueKinds: { WeaponMods: 'userdata' }, lenOperatorAttempted: { WeaponMods: true }, noElementDereference: false, noArrayTraversal: true, noInventoryInfo: true, noEnhancements: true, noWrites: true, noRpcs: true, safetyGates: { allowInventoryUserdataIntrospectionProbes: true } }
]);
assert(userdata.status === 'failed', 'userdata introspection must fail on element dereference marker or safety violation');

const partialState = helpers.markCollected(plan, afterObserve, 'multiplayer-roster-read', {
  status: 'local_identity_confirmed',
  latestSessionId: '20260505T035239Z',
  latestCommit: '7b9c773f133d5464a1f5d6046bdf4ebdd565c75f',
  latestSummaryPath: 'evidence/runtime/20260505T035239Z/diagnostic_summary.txt'
});
assert(partialState.phaseStatuses['multiplayer-roster-read'].status === 'local_identity_confirmed', 'local identity evidence should be partial, not failed');
assert(partialState.nextRecommendedPhase === 'multiplayer-roster-read', `partial roster should keep next phase at multiplayer-roster-read, got ${partialState.nextRecommendedPhase}`);

const unresolvedState = helpers.markCollected(plan, afterObserve, 'multiplayer-roster-read', {
  status: 'roster_source_unresolved',
  latestSessionId: '20260505T040000Z',
  latestCommit: '7b9c773f133d5464a1f5d6046bdf4ebdd565c75f',
  latestSummaryPath: 'evidence/runtime/20260505T040000Z/diagnostic_summary.txt'
});
assert(unresolvedState.phaseStatuses['multiplayer-roster-read'].status === 'roster_source_unresolved', 'candidate-only roster evidence should be partial unresolved, not complete');
assert(unresolvedState.nextRecommendedPhase === 'multiplayer-roster-read', `unresolved roster should keep next phase at multiplayer-roster-read, got ${unresolvedState.nextRecommendedPhase}`);

const remotePartialState = helpers.markCollected(plan, state, 'multiplayer-resource-visibility-read', {
  status: 'remote_resources_partial',
  latestSessionId: '20260505T063937Z',
  latestCommit: 'e0702326d778d31d3b5b84430e99640ee44d603e',
  latestSummaryPath: 'evidence/runtime/20260505T063937Z/diagnostic_summary.txt'
});
assert(remotePartialState.phaseStatuses['multiplayer-resource-visibility-read'].status === 'remote_resources_partial', 'remote resource visibility should remain partial');
assert(remotePartialState.nextRecommendedPhase === 'local-inventory-array-shallow-read', `remote resource partial should advance to local inventory phase, got ${remotePartialState.nextRecommendedPhase}`);

const localInventoryCrashSuspectState = helpers.markCollected(plan, remotePartialState, 'local-inventory-array-shallow-read', {
  status: 'crash_suspect_local_inventory_shape_visible',
  reason: 'Local inventory array fields were visible as shallow userdata shapes, but a crash dump exists after this run.',
  latestSessionId: '20260505T072250Z',
  latestCommit: '591389d5f71e99e2c19f7c287290cbf853a8e496',
  latestSummaryPath: 'evidence/runtime/20260505T072250Z/diagnostic_summary.txt'
});
assert(localInventoryCrashSuspectState.phaseStatuses['local-inventory-array-shallow-read'].status === 'crash_suspect_local_inventory_shape_visible', 'local inventory crash-suspect evidence should be partial, not failed or complete');
assert(localInventoryCrashSuspectState.failedPhases.every((entry) => entry.phaseId !== 'local-inventory-array-shallow-read'), 'local inventory crash-suspect evidence must not be stored as hard failed');
assert(localInventoryCrashSuspectState.nextRecommendedPhase === 'local-inventory-array-shape-confirm', `local inventory crash-suspect should advance only to safer shape confirm, got ${localInventoryCrashSuspectState.nextRecommendedPhase}`);

const shapeConfirmCrashSuspectState = helpers.markCollected(plan, localInventoryCrashSuspectState, 'local-inventory-array-shape-confirm', {
  status: 'crash_suspect_local_inventory_shape_confirmed',
  reason: 'Local inventory array fields were confirmed as property shapes, but crash evidence exists.',
  latestSessionId: '20260505T080000Z',
  latestCommit: '591389d5f71e99e2c19f7c287290cbf853a8e496',
  latestSummaryPath: 'evidence/runtime/20260505T080000Z/diagnostic_summary.txt'
});
assert(shapeConfirmCrashSuspectState.phaseStatuses['local-inventory-array-shape-confirm'].status === 'crash_suspect_local_inventory_shape_confirmed', 'shape-confirm crash-suspect evidence should be partial, not failed or complete');
assert(shapeConfirmCrashSuspectState.nextRecommendedPhase === 'local-inventory-array-shape-confirm', `shape-confirm crash-suspect should keep next phase at shape confirm, got ${shapeConfirmCrashSuspectState.nextRecommendedPhase}`);

const shapeConfirmCompleteState = helpers.markCollected(plan, localInventoryCrashSuspectState, 'local-inventory-array-shape-confirm', {
  status: 'local_inventory_shape_confirmed',
  reason: 'Local inventory array fields were confirmed as property shapes.',
  latestSessionId: '20260505T080100Z',
  latestCommit: '591389d5f71e99e2c19f7c287290cbf853a8e496',
  latestSummaryPath: 'evidence/runtime/20260505T080100Z/diagnostic_summary.txt'
});
assert(shapeConfirmCompleteState.nextRecommendedPhase === 'local-inventory-userdata-introspection', `shape-confirm completion should advance to userdata introspection, got ${shapeConfirmCompleteState.nextRecommendedPhase}`);
'@
node $NodeTestPath (Join-Path $RepoRoot "tools\campaign_helpers.js") $RepoRoot
if ($LASTEXITCODE -ne 0) { throw "campaign helper tests failed." }

Push-Location $RepoRoot
try {
  node tools/generate_campaign_docs.js --state $StatePath --out $DocPath --write-state --quiet
  if ($LASTEXITCODE -ne 0) { throw "campaign docs generation failed." }
} finally {
  Pop-Location
}
Assert-Contains -Path $DocPath -Expected "Next recommended phase:"
Assert-Contains -Path $DocPath -Expected "Campaign read phases never enable writes, RPCs, or HUD hooks."
Assert-Contains -Path (Join-Path $RepoRoot "docs\RUNTIME_CONTEXTS.md") -Expected "this detector cannot distinguish true solo from multiplayer host"

$prepareRan = $false
try {
  & (Join-Path $PSScriptRoot "quick-campaign-prepare.ps1") -GameBin $GameBin | Out-Null
  $prepareRan = $true
} catch {
  if ($_.Exception.Message -notmatch "No pending implemented campaign phase is runnable") {
    throw
  }
  Write-Host "campaign prepare found no pending implemented phase, as expected for a completed implemented campaign."
}

if ($prepareRan) {
  $InstalledConfigPath = Join-Path $GameBin "Mods\CrabRuntimeProbe\Scripts\config.txt"
  $PrepareMarkerPath = Join-Path $GameBin "Mods\CrabRuntimeProbe\Scripts\results\prepare_marker.json"
  $CampaignStatePath = Join-Path $GameBin "Mods\CrabRuntimeProbe\Scripts\results\campaign_state.json"
  if (-not (Test-Path -LiteralPath $PrepareMarkerPath -PathType Leaf)) { throw "campaign prepare did not write prepare_marker.json." }
  if (-not (Test-Path -LiteralPath $CampaignStatePath -PathType Leaf)) { throw "campaign prepare did not write campaign_state.json." }
  Assert-UnsafeReadCampaignGatesFalse -ConfigPath $InstalledConfigPath
  $preparedPhase = (Get-Content -Raw -LiteralPath $PrepareMarkerPath | ConvertFrom-Json).phaseId
  if ($preparedPhase -eq "multiplayer-roster-read") {
    if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "allowIdentityProbes") -ne "true") {
      throw "roster campaign phase expected allowIdentityProbes = true."
    }
    if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "allowRawIdentityEvidence") -ne "false") {
      throw "roster campaign phase expected allowRawIdentityEvidence = false."
    }
    if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "allowHealthProbes") -ne "false") {
      throw "roster campaign phase must not enable health probes."
    }
  } elseif ($preparedPhase -eq "multiplayer-resource-visibility-read") {
    foreach ($key in @("allowIdentityProbes", "allowHealthProbes", "allowResourceVisibilityProbes")) {
      if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key $key) -ne "true") {
        throw "resource visibility campaign phase expected $key = true."
      }
    }
    foreach ($key in @("allowRawIdentityEvidence", "allowWriteProbes", "allowRpcProbes", "allowHudTickHook", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowJoinedClientDeepProbes")) {
      if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key $key) -ne "false") {
        throw "resource visibility campaign phase expected $key = false."
      }
    }
  } elseif ($preparedPhase -eq "local-inventory-array-shallow-read") {
    if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "allowInventoryArrayShallowProbes") -ne "true") {
      throw "local inventory array campaign phase expected allowInventoryArrayShallowProbes = true."
    }
    foreach ($key in @("allowRawIdentityEvidence", "allowWriteProbes", "allowRpcProbes", "allowHudTickHook", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowHealthProbes", "allowIdentityProbes", "allowResourceVisibilityProbes", "allowJoinedClientDeepProbes")) {
      if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key $key) -ne "false") {
        throw "local inventory campaign phase expected $key = false."
      }
    }
  } elseif ($preparedPhase -eq "local-inventory-array-shape-confirm") {
    if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "allowInventoryArrayShapeConfirmProbes") -ne "true") {
      throw "local inventory array shape confirm campaign phase expected allowInventoryArrayShapeConfirmProbes = true."
    }
    foreach ($key in @("allowInventoryArrayShallowProbes", "allowRawIdentityEvidence", "allowWriteProbes", "allowRpcProbes", "allowHudTickHook", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowHealthProbes", "allowIdentityProbes", "allowResourceVisibilityProbes", "allowJoinedClientDeepProbes")) {
      if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key $key) -ne "false") {
        throw "local inventory shape confirm campaign phase expected $key = false."
      }
    }
  } elseif ($preparedPhase -eq "local-inventory-userdata-introspection") {
    if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "allowInventoryUserdataIntrospectionProbes") -ne "true") {
      throw "local inventory userdata introspection campaign phase expected allowInventoryUserdataIntrospectionProbes = true."
    }
    foreach ($key in @("allowInventoryArrayShapeConfirmProbes", "allowInventoryArrayShallowProbes", "allowRawIdentityEvidence", "allowWriteProbes", "allowRpcProbes", "allowHudTickHook", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowHealthProbes", "allowIdentityProbes", "allowResourceVisibilityProbes", "allowJoinedClientDeepProbes")) {
      if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key $key) -ne "false") {
        throw "local inventory userdata introspection campaign phase expected $key = false."
      }
    }
  }
}

Write-Host "CrabRuntimeProbe campaign checks passed."
