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
$RunLocalDiagnosticCyclePath = Join-Path $RepoRoot "scripts\run-local-diagnostic-cycle.ps1"

if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "allowSafeScalarWatchProbes") -ne "false") {
  throw "default config expected allowSafeScalarWatchProbes = false."
}

$plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json -ErrorAction Stop
$phase = @($plan.phases | Where-Object { $_.phaseId -eq "safe-scalar-watch" })[0]
if ($null -eq $phase) { throw "campaign plan missing safe-scalar-watch." }
if ($phase.implemented -ne $true) { throw "safe-scalar-watch must be implemented." }
if ($phase.probeSet -ne "safe-scalar-watch") { throw "safe-scalar-watch phase has wrong probeSet." }
if ($phase.requiredGates.allowSafeScalarWatchProbes -ne $true) { throw "safe-scalar-watch phase must enable allowSafeScalarWatchProbes." }
if (($plan.phases | Where-Object { $_.phaseId -eq "slots-read" }).nextPhase -ne "safe-scalar-watch") {
  throw "slots-read must advance to safe-scalar-watch."
}
if ($phase.nextPhase -ne "perk-da-catalog-read") {
  throw "safe-scalar-watch must advance to perk-da-catalog-read."
}
foreach ($gate in @("allowHudTickHook", "allowUnknownRoleProbes", "allowJoinedClientDeepProbes", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowHealthProbes", "allowIdentityProbes", "allowRawIdentityEvidence", "allowResourceVisibilityProbes", "allowCrystalsReadProbes", "allowSlotsReadProbes", "allowPerkDataAssetCatalogProbes", "allowInventoryArrayShallowProbes", "allowInventoryArrayShapeConfirmProbes", "allowInventoryUserdataIntrospectionProbes", "allowWriteProbes", "allowRpcProbes")) {
  if (@($phase.forbiddenGates) -notcontains $gate) {
    throw "safe-scalar-watch phase must forbid $gate."
  }
}

$runner = Get-Content -Raw -LiteralPath $ProbeRunnerPath
if ($runner -notmatch [regex]::Escape("probe.set == 'safe-scalar-watch' and not config.allowSafeScalarWatchProbes")) {
  throw "safe-scalar-watch probes must be gated by allowSafeScalarWatchProbes."
}
if ($runner -notmatch [regex]::Escape("meta.suppressEmit == true")) {
  throw "safe-scalar-watch needs suppressEmit support for unchanged non-heartbeat samples."
}

$cycle = Get-Content -Raw -LiteralPath $RunLocalDiagnosticCyclePath
foreach ($expected in @(
  '[switch]$PrepareSafeScalarWatch',
  '[switch]$CollectSafeScalarWatch',
  'allowSafeScalarWatchProbes',
  'safe_scalar_watch_sample_count',
  'safe_scalar_watch_first_values',
  'safe_scalar_watch_latest_values',
  'safe_scalar_watch_min_values',
  'safe_scalar_watch_max_values',
  'safe_scalar_watch_change_counts',
  'safe_scalar_watch_slot_model_status'
)) {
  if ($cycle -notmatch [regex]::Escape($expected)) {
    throw "run-local-diagnostic-cycle.ps1 missing safe scalar watch content: $expected"
  }
}

$registry = Get-Content -Raw -LiteralPath $ProbeRegistryPath
$helperStart = $registry.IndexOf("local function safeScalarWatchReadProperty")
$helperEnd = $registry.IndexOf("local PERK_DA_CLASS_CANDIDATES")
$probeStart = $registry.IndexOf("SafeWatch.Scalar.Sample")
$probeEnd = $registry.IndexOf("FindAllOf.CrabHC.Availability")
if ($helperStart -lt 0 -or $helperEnd -le $helperStart -or $probeStart -lt 0 -or $probeEnd -le $probeStart) { throw "could not isolate safe scalar watch probe block." }
$watchBlock = $registry.Substring($helperStart, $helperEnd - $helperStart) + "`n" + $registry.Substring($probeStart, $probeEnd - $probeStart)
foreach ($required in @(
  "SafeWatch.Scalar.Sample",
  "WeaponDA",
  "AbilityDA",
  "MeleeDA",
  "safeScalarWatchReadProperty(stats, playerState, 'Crystals')",
  "safe.getProperty(playerState, fieldName)",
  "safe.getProperty(playerState, 'HealthInfo')",
  "safe.getStructField(healthInfo, fieldName)",
  "safeScalarWatchIntervalSeconds",
  "safeScalarWatchHeartbeatSeconds",
  "safeScalarWatchMaxSamples",
  "noElementDereference = true",
  "noArrayCount = true",
  "noArrayTraversal = true",
  "noInventoryInfo = true",
  "noEnhancements = true",
  "noWrites = true",
  "noRpcs = true",
  "noHud = true",
  "noDeepArrays = true"
)) {
  if ($watchBlock -notmatch [regex]::Escape($required)) {
    throw "safe scalar watch block missing $required."
  }
}
foreach ($forbidden in @("safe.countArrayLimited", "safe.forEachArrayLimited", "safe.getArrayElement", "getArrayElement", "forEachArrayLimited", ":get(", "InventoryInfo')", "Enhancements')", "ServerIncrementNumInventorySlots", "lockedSlots", "allowWriteProbes = true", "allowRpcProbes = true", "allowHudTickHook = true", "allowDeepArrayProbes = true")) {
  if ($watchBlock -match [regex]::Escape($forbidden)) {
    throw "safe scalar watch block must not contain $forbidden."
  }
}

$WorkRoot = Join-Path $RepoRoot "dist\test-safe-scalar-watch-work"
if (Test-Path -LiteralPath $WorkRoot) {
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $WorkRoot "evidence\runtime\safewatch") | Out-Null
Copy-Item -LiteralPath (Join-Path $RepoRoot "campaign") -Destination (Join-Path $WorkRoot "campaign") -Recurse

$safeGates = '"allowHudTickHook":false,"allowUnknownRoleProbes":false,"allowJoinedClientDeepProbes":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowIdentityProbes":false,"allowRawIdentityEvidence":false,"allowResourceVisibilityProbes":false,"allowCrystalsReadProbes":false,"allowSlotsReadProbes":false,"allowSafeScalarWatchProbes":true,"allowPerkDataAssetCatalogProbes":false,"allowInventoryArrayShallowProbes":false,"allowInventoryArrayShapeConfirmProbes":false,"allowInventoryUserdataIntrospectionProbes":false,"allowWriteProbes":false,"allowRpcProbes":false'
$SessionDir = Join-Path $WorkRoot "evidence\runtime\safewatch"
$watchRow = ('{"timestamp":"2026-05-05T10:20:01Z","sessionId":"safewatch","probeId":"SafeWatch.Scalar.Sample","probeName":"SafeWatch.Scalar.Sample","probeSet":"safe-scalar-watch","category":"safe-scalar-watch","symbol":"CrabPS.SafeScalarWatch","owner":"CrabPS","member":"WeaponDA AbilityDA MeleeDA Crystals Num*Slots HealthInfo","accessMethod":"SafeScalarWatchSample","accessKind":"safeScalarWatch","mode":"active","tickDriver":"executeDelay","tick":500,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"safe_scalar_watch","valueSummary":"category=safe-scalar-watch sampleCount=2 loggedCount=1 reason=heartbeat playerStatePresent=true changed=false changedFields=none slotModel=observed scalar slot counters / candidate unlocked or usable slot counters; locked/max/total unresolved noArrayCount=true noArrayTraversal=true noElementDereference=true noInventoryInfo=true noEnhancements=true noWrites=true noRpcs=true noHud=true noDeepArrays=true crashAttributionMarker=safe-scalar-watch","sourceScope":"local_safe_scalar_watch","sourcePath":"CrabPC.PlayerState","sourceClass":"CrabPS","playerStatePresent":true,"localPlayerStatePresent":true,"sampleReason":"heartbeat","sampleChanged":false,"safeWatchSampleCount":2,"safeWatchLoggedCount":1,"safeWatchFirstValues":{"Crystals":100,"NumWeaponModSlots":24,"CurrentHealth":250},"safeWatchLatestValues":{"Crystals":100,"NumWeaponModSlots":24,"CurrentHealth":250},"safeWatchMinValues":{"Crystals":100,"NumWeaponModSlots":24,"CurrentHealth":250},"safeWatchMaxValues":{"Crystals":100,"NumWeaponModSlots":24,"CurrentHealth":250},"safeWatchChangedFields":[],"safeWatchChangeCounts":{},"firstContext":"solo","lastContext":"solo","firstRole":"solo-or-host","lastRole":"solo-or-host","lockedSlotModel":"observed scalar slot counters / candidate unlocked or usable slot counters; locked/max/total slot model unresolved","noElementDereference":true,"noArrayCount":true,"noArrayTraversal":true,"noInventoryInfo":true,"noEnhancements":true,"noWrites":true,"noRpcs":true,"noHud":true,"noDeepArrays":true,"crashAttributionMarker":"safe-scalar-watch","safetyGates":{' + $safeGates + '}}')
Set-Content -LiteralPath (Join-Path $SessionDir "access_evidence.jsonl") -Encoding ASCII -Value @($watchRow)
Set-Content -LiteralPath (Join-Path $SessionDir "probe_results.jsonl") -Encoding ASCII -Value @($watchRow)
Set-Content -LiteralPath (Join-Path $SessionDir "session_manifest.json") -Encoding ASCII -Value ('{"sessionId":"safewatch","probeSet":"safe-scalar-watch","tickDriver":"executeDelay","config":{"mode":"active","probeSet":"safe-scalar-watch","tickDriver":"executeDelay",' + $safeGates + '},"safetyGates":{' + $safeGates + '},"activeResearchGates":["allowSafeScalarWatchProbes"]}')
Set-Content -LiteralPath (Join-Path $SessionDir "diagnostic_summary.txt") -Encoding ASCII -Value @(
  "sessionId = safewatch",
  "safe_scalar_watch_probe_ran = True",
  "safe_scalar_watch_classification = safe_scalar_watch_confirmed_no_change",
  "safe_scalar_watch_sample_count = 2",
  "safe_scalar_watch_first_values = Crystals=100, CurrentHealth=250, NumWeaponModSlots=24",
  "safe_scalar_watch_latest_values = Crystals=100, CurrentHealth=250, NumWeaponModSlots=24",
  "safe_scalar_watch_min_values = Crystals=100, CurrentHealth=250, NumWeaponModSlots=24",
  "safe_scalar_watch_max_values = Crystals=100, CurrentHealth=250, NumWeaponModSlots=24",
  "safe_scalar_watch_changed_fields = none",
  "safe_scalar_watch_change_counts = none",
  "safe_scalar_watch_slot_model_status = observed scalar slot counters / candidate unlocked or usable slot counters; locked/max/total slot model unresolved",
  "safe_scalar_watch_safety_violation = False",
  "crash_after_prepare = False",
  "crash_suspect = False"
)

$NodeTestPath = Join-Path $WorkRoot "safe-watch-classifier-test.js"
Set-Content -LiteralPath $NodeTestPath -Encoding ASCII -Value @'
const helpers = require(process.argv[2]);
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
const row = {
  probeName: 'SafeWatch.Scalar.Sample',
  playerStatePresent: true,
  safeWatchSampleCount: 2,
  safeWatchChangedFields: [],
  safeWatchFirstValues: { Crystals: 100 },
  safeWatchLatestValues: { Crystals: 100 },
  safeWatchMinValues: { Crystals: 100 },
  safeWatchMaxValues: { Crystals: 100 },
  safeWatchChangeCounts: {},
  firstContext: 'solo',
  lastContext: 'solo',
  firstRole: 'solo-or-host',
  lastRole: 'solo-or-host',
  noElementDereference: true,
  noArrayCount: true,
  noArrayTraversal: true,
  noInventoryInfo: true,
  noEnhancements: true,
  noWrites: true,
  noRpcs: true,
  noHud: true,
  noDeepArrays: true,
  safetyGates: { allowSafeScalarWatchProbes: true }
};
let result = helpers.classifySafeScalarWatchEvidence([row]);
assert(result.status === 'safe_scalar_watch_confirmed_no_change', `watch no-change should confirm, got ${result.status}`);
result = helpers.classifySafeScalarWatchEvidence([{ ...row, safeWatchChangedFields: ['Crystals'], safeWatchChangeCounts: { Crystals: 1 } }]);
assert(result.status === 'safe_scalar_watch_observed_change', `watch change should classify observed_change, got ${result.status}`);
result = helpers.classifySafeScalarWatchEvidence([{ ...row, noArrayTraversal: false }]);
assert(result.status === 'failed', `watch safety violation should fail, got ${result.status}`);
'@
node $NodeTestPath (Join-Path $RepoRoot "tools\campaign_helpers.js")
if ($LASTEXITCODE -ne 0) { throw "safe scalar watch classifier tests failed." }

Push-Location $WorkRoot
try {
  node (Join-Path $RepoRoot "tools\generate_access_docs.js")
  node (Join-Path $RepoRoot "tools\generate_campaign_docs.js") --state (Join-Path $WorkRoot "evidence\campaign_state.json") --out (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") --write-state --quiet
} finally {
  Pop-Location
}

Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Safe Scalar Watch Summary"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Safe scalar watch status: safe_scalar_watch_confirmed_no_change"
Assert-Contains -Path (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") -Expected "Safe Scalar Watch"
Assert-Contains -Path (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") -Expected "Slot model status"

Write-Host "CrabRuntimeProbe safe-scalar-watch probe checks passed."
