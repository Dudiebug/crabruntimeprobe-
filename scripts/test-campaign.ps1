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
    "allowInventoryInfoProbes"
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
foreach ($key in @("allowHudTickHook", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowHealthProbes", "allowWriteProbes", "allowRpcProbes")) {
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
    { phaseId: 'multiplayer-health-playerstate-watch' }
  ],
  failedPhases: [],
  blockedPhases: []
}, repoRoot);
assert(state.nextRecommendedPhase === null, `unimplemented blocked phase should not be selected, got ${state.nextRecommendedPhase}`);

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
  if (!/^health-|^multiplayer-health-/.test(phase.phaseId)) {
    assert(gates.allowHealthProbes === false, `${phase.phaseId} enabled health outside health phases`);
  }
}
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

& (Join-Path $PSScriptRoot "quick-campaign-prepare.ps1") -GameBin $GameBin | Out-Null
$InstalledConfigPath = Join-Path $GameBin "Mods\CrabRuntimeProbe\Scripts\config.txt"
$PrepareMarkerPath = Join-Path $GameBin "Mods\CrabRuntimeProbe\Scripts\results\prepare_marker.json"
$CampaignStatePath = Join-Path $GameBin "Mods\CrabRuntimeProbe\Scripts\results\campaign_state.json"
if (-not (Test-Path -LiteralPath $PrepareMarkerPath -PathType Leaf)) { throw "campaign prepare did not write prepare_marker.json." }
if (-not (Test-Path -LiteralPath $CampaignStatePath -PathType Leaf)) { throw "campaign prepare did not write campaign_state.json." }
Assert-UnsafeReadCampaignGatesFalse -ConfigPath $InstalledConfigPath

Write-Host "CrabRuntimeProbe campaign checks passed."
