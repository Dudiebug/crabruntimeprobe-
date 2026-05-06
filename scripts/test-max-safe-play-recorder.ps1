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
$MainPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\main.lua"
$RegistryPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\probe_registry.lua"
$RunnerPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\probe_runner.lua"
$EvidenceWriterPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\evidence_writer.lua"
$CyclePath = Join-Path $RepoRoot "scripts\run-local-diagnostic-cycle.ps1"
$WorkRoot = Join-Path $RepoRoot "dist\test-max-safe-play-work"

if (Test-Path -LiteralPath $WorkRoot) {
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

Assert-CrabRuntimeProbeConfig -ConfigPath $SourceConfigPath -Label "source config"
foreach ($pair in @(
  @("allowMaxSafePlayRecorderProbes", "false"),
  @("maxSafePlayIntervalSeconds", "5"),
  @("maxSafePlayHeartbeatSeconds", "60"),
  @("maxSafePlayMaxSamples", "720"),
  @("maxSafePlayPerkCatalogIntervalSeconds", "60"),
  @("maxSafePlayMaxPerkCatalogSnapshots", "60"),
  @("maxSafePlayLogUnchangedHeartbeat", "true")
)) {
  if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key $pair[0]) -ne $pair[1]) {
    throw "source config expected $($pair[0]) = $($pair[1])."
  }
}

$registry = Get-Content -Raw -LiteralPath $RegistryPath
$runner = Get-Content -Raw -LiteralPath $RunnerPath
$main = Get-Content -Raw -LiteralPath $MainPath
$writer = Get-Content -Raw -LiteralPath $EvidenceWriterPath
$cycle = Get-Content -Raw -LiteralPath $CyclePath

foreach ($expected in @(
  "MaxSafePlay.Scalar.Sample",
  "MaxSafePlay.PerkDataAsset.CatalogSnapshot",
  "MaxSafePlay.Session.Heartbeat",
  "MaxSafePlay.Session.Summary",
  "readMaxSafePlayScalarSample",
  "readMaxSafePlayPerkCatalogSnapshot",
  "collectPerkDataAssetCatalog(ctx)",
  "maxSafePlayMaxSamples",
  "maxSafePlayMaxPerkCatalogSnapshots",
  "passiveOnly = true",
  "noInventoryArrays = true",
  "noDataAssetMutation = true",
  "noFunctionCalls = true"
)) {
  Assert-Contains -Text $registry -Expected $expected -Label "probe_registry.lua"
}
foreach ($unexpected in @("InventoryInfo.", "['InventoryInfo']", '["InventoryInfo"]', "Enhancements.", "['Enhancements']", '["Enhancements"]', "ServerIncrementNumInventorySlots", "allowWriteProbes = true", "allowRpcProbes = true", "allowHudTickHook = true")) {
  $block = [regex]::Match($registry, "local function maxSafePlayState[\s\S]+?probes\[#probes \+ 1\] = mk\('FindAllOf\.CrabHC\.Availability'").Value
  if ($block -match [regex]::Escape($unexpected)) {
    throw "max-safe play block must not contain $unexpected."
  }
}
Assert-Contains -Text $runner -Expected "probe.set == 'max-safe-play-recorder' and not config.allowMaxSafePlayRecorderProbes" -Label "probe_runner.lua"
Assert-Contains -Text $main -Expected "allowMaxSafePlayRecorderProbes = false" -Label "main.lua"
Assert-Contains -Text $writer -Expected "allowMaxSafePlayRecorderProbes = config.allowMaxSafePlayRecorderProbes == true" -Label "evidence_writer.lua"
Assert-Contains -Text $cycle -Expected "PrepareMaxSafePlayRecorder" -Label "run-local-diagnostic-cycle.ps1"
Assert-Contains -Text $cycle -Expected "CollectMaxSafePlayRecorder" -Label "run-local-diagnostic-cycle.ps1"
Assert-Contains -Text $cycle -Expected "No PlayerState-present samples collected. Launch into a stable world/run and play for at least 1 to 5 minutes before collecting." -Label "run-local-diagnostic-cycle.ps1"

$NodeTestPath = Join-Path $WorkRoot "max-safe-play-classifier-test.js"
Set-Content -LiteralPath $NodeTestPath -Encoding ASCII -Value @'
const helpers = require(process.argv[2]);
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
const gates = {
  allowMaxSafePlayRecorderProbes: true,
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
  allowInventoryArrayShallowProbes: false,
  allowInventoryArrayShapeConfirmProbes: false,
  allowInventoryUserdataIntrospectionProbes: false,
  allowWriteProbes: false,
  allowRpcProbes: false
};
const safety = {
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
  passiveOnly: true,
  safetyGates: gates
};
const scalar = {
  probeName: 'MaxSafePlay.Scalar.Sample',
  playerStatePresent: true,
  maxSafePlayScalarSampleCount: 2,
  maxSafePlayScalarLoggedCount: 2,
  maxSafePlayFirstValues: { Crystals: 100, CurrentHealth: 250 },
  maxSafePlayLatestValues: { Crystals: 100, CurrentHealth: 250 },
  maxSafePlayMinValues: { Crystals: 100, CurrentHealth: 250 },
  maxSafePlayMaxValues: { Crystals: 100, CurrentHealth: 250 },
  maxSafePlayChangedFields: [],
  maxSafePlayChangeCounts: {},
  ...safety
};
const catalog = {
  probeName: 'MaxSafePlay.PerkDataAsset.CatalogSnapshot',
  discoveryAttempted: true,
  catalogFound: true,
  catalogEntryCount: 1,
  catalogCandidateCount: 1,
  catalogEntries: [{ shortName: 'DA_Perk_TastyOrange', fullName: '/Game/Perks/DA_Perk_TastyOrange' }],
  maxSafePlayCatalogSnapshotCount: 1,
  maxSafePlayCatalogKnownEntryCount: 1,
  maxSafePlayNewDataAssets: [{ shortName: 'DA_Perk_TastyOrange' }],
  maxSafePlayChangedCatalogEntries: [],
  tastyOrangeFound: true,
  collectorFound: false,
  ...safety
};
let result = helpers.classifyMaxSafePlayEvidence([scalar, catalog]);
assert(result.status === 'max_safe_play_observed_change', `expected observed change from new DA, got ${result.status}`);
assert(result.tastyOrangeFound === true, 'TastyOrange should be summarized as a normal catalog entry');
result = helpers.classifyMaxSafePlayEvidence([{ ...scalar, maxSafePlayScalarSampleCount: 2 }, { ...catalog, maxSafePlayNewDataAssets: [], catalogEntries: [], maxSafePlayCatalogKnownEntryCount: 1 }]);
assert(result.status === 'max_safe_play_confirmed_no_change', `expected confirmed no change, got ${result.status}`);
result = helpers.classifyMaxSafePlayEvidence([{ ...scalar, playerStatePresent: false, maxSafePlayScalarSampleCount: 1 }]);
assert(result.status === 'max_safe_play_no_playerstate_samples', `expected no playerstate samples, got ${result.status}`);
result = helpers.classifyMaxSafePlayEvidence([{ ...scalar, noInventoryArrays: false }]);
assert(result.status === 'failed', 'safety marker failure should fail');
result = helpers.classifyMaxSafePlayEvidence([{ ...scalar, safetyGates: { ...gates, allowWriteProbes: true } }]);
assert(result.status === 'failed', 'forbidden gate failure should fail');
'@
node $NodeTestPath (Join-Path $RepoRoot "tools\campaign_helpers.js")
if ($LASTEXITCODE -ne 0) { throw "max-safe play classifier tests failed." }

$GameBin = Join-Path $WorkRoot "game-bin"
New-Item -ItemType Directory -Force -Path $GameBin | Out-Null
& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $GameBin -PrepareMaxSafePlayRecorder
$InstalledConfigPath = Join-Path $GameBin "Mods\CrabRuntimeProbe\Scripts\config.txt"
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "probeSet") -ne "max-safe-play-recorder") {
  throw "prepare did not set max-safe-play-recorder probeSet."
}
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "allowMaxSafePlayRecorderProbes") -ne "true") {
  throw "prepare did not enable allowMaxSafePlayRecorderProbes."
}
foreach ($gate in @("allowHudTickHook", "allowUnknownRoleProbes", "allowJoinedClientDeepProbes", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowHealthProbes", "allowIdentityProbes", "allowRawIdentityEvidence", "allowResourceVisibilityProbes", "allowCrystalsReadProbes", "allowSlotsReadProbes", "allowSafeScalarWatchProbes", "allowPerkDataAssetCatalogProbes", "allowInventoryArrayShallowProbes", "allowInventoryArrayShapeConfirmProbes", "allowInventoryUserdataIntrospectionProbes", "allowWriteProbes", "allowRpcProbes")) {
  if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key $gate) -ne "false") {
    throw "prepare must leave $gate false."
  }
}

$ScriptsRoot = Join-Path $GameBin "Mods\CrabRuntimeProbe\Scripts"
$ResultsRoot = Join-Path $ScriptsRoot "results"
$BuildInfoPath = Join-Path $ScriptsRoot "build_info.txt"
$SummaryPath = Join-Path $ScriptsRoot "diagnostic_summary.txt"
$commit = "unavailable"
foreach ($line in @(Get-Content -LiteralPath $BuildInfoPath)) {
  if ($line -match "^\s*git_commit\s*=\s*(.*?)\s*$") { $commit = $matches[1].Trim() }
}
$manifest = @{
  sessionId = "maxnosample"
  startedAt = "2026-05-06T00:00:00Z"
  game = "Crab Champions"
  mod = "CrabRuntimeProbe"
  schemaVersion = 1
  buildInfo = @{ git_commit = $commit; git_branch = "test" }
  config = @{
    mode = "active"
    probeSet = "max-safe-play-recorder"
    tickDriver = "executeDelay"
    allowMaxSafePlayRecorderProbes = $true
  }
  probeSet = "max-safe-play-recorder"
  tickDriver = "executeDelay"
  safetyGates = @{
    allowMaxSafePlayRecorderProbes = $true
    allowHudTickHook = $false
    allowUnknownRoleProbes = $false
    allowJoinedClientDeepProbes = $false
    allowDeepArrayProbes = $false
    allowInventoryInfoProbes = $false
    allowHealthProbes = $false
    allowIdentityProbes = $false
    allowRawIdentityEvidence = $false
    allowResourceVisibilityProbes = $false
    allowCrystalsReadProbes = $false
    allowSlotsReadProbes = $false
    allowSafeScalarWatchProbes = $false
    allowPerkDataAssetCatalogProbes = $false
    allowInventoryArrayShallowProbes = $false
    allowInventoryArrayShapeConfirmProbes = $false
    allowInventoryUserdataIntrospectionProbes = $false
    allowWriteProbes = $false
    allowRpcProbes = $false
  }
}
Set-Content -LiteralPath (Join-Path $ResultsRoot "session_manifest_maxnosample.json") -Encoding ASCII -Value ($manifest | ConvertTo-Json -Depth 8 -Compress)
Set-Content -LiteralPath (Join-Path $ResultsRoot "probe_results_maxnosample.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-06T00:00:00Z","sessionId":"maxnosample","event":"Debug.StartupSmoke","probeId":"Debug.StartupSmoke","probeName":"Debug.StartupSmoke","probeSet":"max-safe-play-recorder","mode":"active","tickDriver":"executeDelay","result":"ok"}',
  '{"timestamp":"2026-05-06T00:00:00Z","sessionId":"maxnosample","event":"Debug.WriterSelfTest","probeId":"Debug.WriterSelfTest","probeName":"Debug.WriterSelfTest","probeSet":"max-safe-play-recorder","mode":"active","tickDriver":"executeDelay","result":"ok"}'
)
Set-Content -LiteralPath (Join-Path $ResultsRoot "access_evidence_maxnosample.jsonl") -Encoding ASCII -Value @()
Set-Content -LiteralPath (Join-Path $GameBin "UE4SS.log") -Encoding ASCII -Value @(
  "[CrabRuntimeProbe] started session=maxnosample mode=active",
  "[CrabRuntimeProbe] build git_commit = $commit",
  "[CrabRuntimeProbe] tick source registered: executeDelay",
  "[CrabRuntimeProbe] boot phase: startup complete"
)
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $GameBin -CollectMaxSafePlayRecorder | Out-Host
if ($LASTEXITCODE -eq 0) {
  throw "max-safe play collect must fail for no-sample sessions."
}
$summary = Get-Content -Raw -LiteralPath $SummaryPath
Assert-Contains -Text $summary -Expected "max_safe_play_classification = max_safe_play_no_playerstate_samples" -Label "no-sample diagnostic_summary.txt"
Assert-Contains -Text $summary -Expected "No PlayerState-present samples collected. Launch into a stable world/run and play for at least 1 to 5 minutes before collecting." -Label "no-sample diagnostic_summary.txt"

Write-Host "CrabRuntimeProbe max-safe-play-recorder checks passed."
