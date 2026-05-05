[CmdletBinding()]
param(
  [string]$GameBinPath
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

function Assert-ConfigValue {
  param(
    [string]$ConfigPath,
    [string]$Key,
    [string]$Expected
  )

  $actual = Get-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key $Key
  if ($actual -ne $Expected) {
    throw "$ConfigPath expected $Key = $Expected, got '$actual'"
  }
}

function Assert-UnsafeGatesFalse {
  param([string]$ConfigPath)

  foreach ($key in @(
    "allowHudTickHook",
    "allowUnknownRoleProbes",
    "allowJoinedClientDeepProbes",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowHealthProbes",
    "allowRawIdentityEvidence",
    "allowResourceVisibilityProbes",
    "allowInventoryArrayShallowProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )) {
    Assert-ConfigValue -ConfigPath $ConfigPath -Key $key -Expected "false"
  }
}

function Assert-HealthBaselineGates {
  param([string]$ConfigPath)

  Assert-ConfigValue -ConfigPath $ConfigPath -Key "allowHealthProbes" -Expected "true"
  foreach ($key in @(
    "allowHudTickHook",
    "allowUnknownRoleProbes",
    "allowJoinedClientDeepProbes",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowIdentityProbes",
    "allowRawIdentityEvidence",
    "allowResourceVisibilityProbes",
    "allowInventoryArrayShallowProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )) {
    Assert-ConfigValue -ConfigPath $ConfigPath -Key $key -Expected "false"
  }
}

function Set-TestConfigValue {
  param(
    [string]$ConfigPath,
    [string]$Key,
    [string]$Value
  )

  $pattern = "^\s*$([regex]::Escape($Key))\s*="
  $lines = @(Get-Content -LiteralPath $ConfigPath)
  $updated = foreach ($line in $lines) {
    if ($line -match $pattern) { "$Key = $Value" } else { $line }
  }
  Set-Content -LiteralPath $ConfigPath -Value $updated -Encoding ASCII
}

function Get-TestBuildInfoValue {
  param(
    [string]$ScriptsRoot,
    [string]$Key
  )

  $path = Join-Path $ScriptsRoot "build_info.txt"
  foreach ($line in @(Get-Content -LiteralPath $path)) {
    if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.*?)\s*$") {
      return $matches[1].Trim()
    }
  }
  throw "Missing $Key in $path"
}

function Write-TestSessionManifest {
  param(
    [string]$ResultsRoot,
    [string]$SessionId,
    [string]$GitCommit,
    [string]$ProbeSet,
    [string]$TickDriver
  )

  $manifest = [ordered]@{
    sessionId = $SessionId
    startedAt = "2026-05-04T00:00:00Z"
    game = "Crab Champions"
    mod = "CrabRuntimeProbe"
    schemaVersion = 1
    buildInfo = [ordered]@{
      git_commit = $GitCommit
      git_branch = "main"
    }
    config = [ordered]@{
      probeSet = $ProbeSet
      tickDriver = $TickDriver
      mode = "active"
    }
    probeSet = $ProbeSet
    tickDriver = $TickDriver
    safetyGates = [ordered]@{
      allowHudTickHook = $false
      allowDeepArrayProbes = $false
      allowInventoryInfoProbes = $false
      allowHealthProbes = $true
      allowIdentityProbes = $false
      allowRawIdentityEvidence = $false
      allowResourceVisibilityProbes = $false
      allowInventoryArrayShallowProbes = $false
      allowWriteProbes = $false
      allowRpcProbes = $false
      allowJoinedClientDeepProbes = $false
      allowUnknownRoleProbes = $false
    }
  }

  Set-Content -LiteralPath (Join-Path $ResultsRoot "session_manifest_$SessionId.json") -Encoding ASCII -Value ($manifest | ConvertTo-Json -Depth 8 -Compress)
}

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$SourceModRoot = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe"
$SourceConfigPath = Join-Path $SourceModRoot "Scripts\config.txt"
$ExportRoot = Join-Path $RepoRoot "dist\CrabRuntimeProbe-client"
$ExportedModRoot = Join-Path $ExportRoot "Mods\CrabRuntimeProbe"
$ExportedConfigPath = Join-Path $ExportedModRoot "Scripts\config.txt"
$TestGameBin = if ([string]::IsNullOrWhiteSpace($GameBinPath)) {
  Join-Path $RepoRoot "dist\test-packaging-game-bin"
} else {
  [System.IO.Path]::GetFullPath($GameBinPath)
}
$InstalledConfigPath = Join-Path $TestGameBin "Mods\CrabRuntimeProbe\Scripts\config.txt"

Assert-CrabRuntimeProbeModLayout -ModRoot $SourceModRoot -Label "source CrabRuntimeProbe mod"
Assert-CrabRuntimeProbeConfig -ConfigPath $SourceConfigPath -Label "source config"
Assert-ConfigValue -ConfigPath $SourceConfigPath -Key "tickDriver" -Expected "none"
Assert-ConfigValue -ConfigPath $SourceConfigPath -Key "probeSet" -Expected "shallow-core"
Assert-UnsafeGatesFalse -ConfigPath $SourceConfigPath

& (Join-Path $PSScriptRoot "export-client-folder.ps1") -OutputPath $ExportRoot

Assert-CrabRuntimeProbeModLayout -ModRoot $ExportedModRoot -Label "exported CrabRuntimeProbe mod"
Assert-CrabRuntimeProbeConfig -ConfigPath $ExportedConfigPath -Label "exported config"
Assert-ConfigValue -ConfigPath $ExportedConfigPath -Key "tickDriver" -Expected "none"
Assert-ConfigValue -ConfigPath $ExportedConfigPath -Key "probeSet" -Expected "shallow-core"
Assert-UnsafeGatesFalse -ConfigPath $ExportedConfigPath

New-Item -ItemType Directory -Force -Path $TestGameBin | Out-Null
& (Join-Path $PSScriptRoot "install-client-to-game.ps1") $TestGameBin
& (Join-Path $PSScriptRoot "verify-installed-client.ps1") $TestGameBin
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "none"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "probeSet" -Expected "shallow-core"
Assert-UnsafeGatesFalse -ConfigPath $InstalledConfigPath

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareSmoke
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "none"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "debugWriterSelfTest" -Expected "true"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "debugTickHeartbeat" -Expected "false"
Assert-UnsafeGatesFalse -ConfigPath $InstalledConfigPath

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareTickDriver "executeDelay"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "executeDelay"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "mode" -Expected "observe"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "probeSet" -Expected "shallow-core"
Assert-UnsafeGatesFalse -ConfigPath $InstalledConfigPath

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareEquipmentProperty
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "executeDelay"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "mode" -Expected "active"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "probeSet" -Expected "equipment-property-read"
Assert-UnsafeGatesFalse -ConfigPath $InstalledConfigPath

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareHealthBaseline
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "executeDelay"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "mode" -Expected "active"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "probeSet" -Expected "health-baseline-read"
Assert-HealthBaselineGates -ConfigPath $InstalledConfigPath

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareHealthPlayerState
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "executeDelay"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "mode" -Expected "active"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "probeSet" -Expected "health-playerstate-read"
Assert-HealthBaselineGates -ConfigPath $InstalledConfigPath

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareHealthPlayerStateWatch
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "executeDelay"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "mode" -Expected "active"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "probeSet" -Expected "health-playerstate-watch"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "repeatProbeSet" -Expected "true"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "allowHealthProbes" -Expected "true"
foreach ($key in @(
  "allowHudTickHook",
  "allowUnknownRoleProbes",
  "allowJoinedClientDeepProbes",
  "allowDeepArrayProbes",
  "allowInventoryInfoProbes",
  "allowInventoryArrayShallowProbes",
  "allowWriteProbes",
  "allowRpcProbes"
)) {
  Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key $key -Expected "false"
}

$gameplayPrepareScript = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "quick-gameplay-observe-prepare.ps1")
if ($gameplayPrepareScript -notmatch 'PrepareTickDriver executeDelay') {
  throw "quick-gameplay-observe-prepare.ps1 must prepare executeDelay explicitly."
}
if ($gameplayPrepareScript -match 'equipment-property-read') {
  throw "quick-gameplay-observe-prepare.ps1 must stay on the shallow-core observe path."
}

$equipmentPropertyPrepareScript = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "quick-equipment-property-prepare.ps1")
if ($equipmentPropertyPrepareScript -notmatch 'PrepareEquipmentProperty') {
  throw "quick-equipment-property-prepare.ps1 must use the equipment property prepare path."
}

$healthBaselinePrepareScript = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "quick-health-baseline-prepare.ps1")
if ($healthBaselinePrepareScript -notmatch 'PrepareHealthBaseline') {
  throw "quick-health-baseline-prepare.ps1 must use the health baseline prepare path."
}

$healthPlayerStatePrepareScript = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "quick-health-playerstate-prepare.ps1")
if ($healthPlayerStatePrepareScript -notmatch 'PrepareHealthPlayerState') {
  throw "quick-health-playerstate-prepare.ps1 must use the health playerstate prepare path."
}
$healthPlayerStateCollectScript = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "quick-health-playerstate-collect.ps1")
if ($healthPlayerStateCollectScript -notmatch 'validate-latest-crash-bundle\.ps1' -or $healthPlayerStateCollectScript -notmatch 'health-playerstate-read') {
  throw "quick-health-playerstate-collect.ps1 must run the stale bundle validator for health-playerstate-read."
}
$healthPlayerStateWatchPrepareScript = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "quick-health-playerstate-watch-prepare.ps1")
if ($healthPlayerStateWatchPrepareScript -notmatch 'PrepareHealthPlayerStateWatch') {
  throw "quick-health-playerstate-watch-prepare.ps1 must use the health playerstate watch prepare path."
}
$healthPlayerStateWatchCollectScript = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "quick-health-playerstate-watch-collect.ps1")
if ($healthPlayerStateWatchCollectScript -notmatch 'validate-latest-crash-bundle\.ps1' -or $healthPlayerStateWatchCollectScript -notmatch 'health-playerstate-watch') {
  throw "quick-health-playerstate-watch-collect.ps1 must run the stale bundle validator for health-playerstate-watch."
}

$probeRegistry = Get-Content -Raw -LiteralPath (Join-Path $SourceModRoot "Scripts\probe_registry.lua")
foreach ($required in @(
  "CrabPS.GetPropertyValue.",
  "equipment-property-read",
  "CrabPS.DirectField.",
  "equipment-direct-field-read",
  "health-baseline-read",
  "health-playerstate-read",
  "health-playerstate-watch",
  "Health.PlayerState.Sample",
  "Identity.GameState.SourceCandidate",
  "Identity.CrabGS.SourceCandidate",
  "Identity.PlayerArray.Shape",
  "Identity.FindAll.PlayerStateCandidates",
  "Identity.PlayerControllerCandidates",
  "Identity.VisiblePlayers.SourceCandidate",
  "health-hc-discovery-read"
)) {
  if ($probeRegistry -notmatch [regex]::Escape($required)) {
    throw "probe_registry.lua missing expected equipment probe registry content: $required"
  }
}
if ($probeRegistry -match "CrabPS\.DirectField\.[\s\S]*equipment-property-read") {
  throw "equipment-property-read must not include DirectField probes."
}
if ($equipmentPropertyPrepareScript -match "equipment-direct-field-read") {
  throw "quick-equipment-property-prepare.ps1 must not select equipment-direct-field-read."
}
if ($healthPlayerStatePrepareScript -match "FindFirstOf.CrabHC") {
  throw "quick-health-playerstate-prepare.ps1 must not mention FindFirstOf.CrabHC."
}
if ($healthPlayerStateWatchPrepareScript -match "FindFirstOf.CrabHC|FindAllOf.CrabHC|InventoryInfo|allowWriteProbes\s*=\s*true|allowRpcProbes\s*=\s*true|allowHudTickHook\s*=\s*true") {
  throw "quick-health-playerstate-watch-prepare.ps1 must stay on the safe playerstate-only watch path."
}

$hudFailed = $false
try {
  & (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareTickDriver "hud"
} catch {
  $hudFailed = $true
}
if (-not $hudFailed) {
  throw "Expected hud tick driver prepare to fail while allowHudTickHook is false."
}

$logModule = Get-Content -Raw -LiteralPath (Join-Path $SourceModRoot "Scripts\crp_log.lua")
if ($logModule -notmatch [regex]::Escape("text:gsub('[\r\n]+$', '')")) {
  throw "crp_log.lua must trim existing trailing newlines before logging."
}
if ($logModule -notmatch [regex]::Escape("print(normalize(message) .. '\n')")) {
  throw "crp_log.lua must append exactly one newline to CrabRuntimeProbe log lines."
}

$rawCrabRuntimePrints = @(Select-String -Path (Join-Path $SourceModRoot "Scripts\*.lua") -Pattern "print\('\[CrabRuntimeProbe" | Where-Object {
  $_.Path -notlike "*crp_log.lua"
})
if ($rawCrabRuntimePrints.Count -gt 0) {
  throw "CrabRuntimeProbe logs must go through crp_log.lua; raw print found in $($rawCrabRuntimePrints[0].Path):$($rawCrabRuntimePrints[0].LineNumber)"
}

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareTickDriver "executeDelay"
$scriptsRoot = Join-Path $TestGameBin "Mods\CrabRuntimeProbe\Scripts"
$resultsRoot = Join-Path $scriptsRoot "results"
New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null
Set-Content -LiteralPath (Join-Path $TestGameBin "UE4SS.log") -Encoding ASCII -Value @(
  "[CrabRuntimeProbe] boot phase: config loaded",
  "[CrabRuntimeProbe] started session=test mode=observe",
  "[CrabRuntimeProbe] tickDriver=executeDelay",
  "[CrabRuntimeProbe] tick driver register begin: executeDelay",
  "[CrabRuntimeProbe] tick source registered: executeDelay",
  "[CrabRuntimeProbe] tick heartbeat tick=100 mode=observe",
  "[CrabRuntimeProbe] tick heartbeat tick=200 mode=observe"
)
Set-Content -LiteralPath (Join-Path $resultsRoot "probe_results_test.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-04T00:00:01Z","event":"Debug.StartupSmoke","probeId":"Debug.StartupSmoke","probeName":"Debug.StartupSmoke","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:02Z","event":"Debug.WriterSelfTest","probeId":"Debug.WriterSelfTest","probeName":"Debug.WriterSelfTest","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:03Z","probeId":"Observe.Context","probeName":"Observe.Context","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","crabPcExists":true,"playerStateExists":true}',
  '{"timestamp":"2026-05-04T00:00:04Z","probeId":"Observe.Context","probeName":"Observe.Context","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","crabPcExists":true,"playerStateExists":true}'
)
& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -Collect -ExpectObserveContext

$summaryPath = Join-Path $scriptsRoot "diagnostic_summary.txt"
$summary = Get-Content -Raw -LiteralPath $summaryPath
foreach ($required in @(
  "jsonl_event_count = 4",
  "access_evidence_file_count = 0",
  "session_manifest_file_count = 0",
  "observe_context_count = 2",
  "debug_startup_smoke_count = 1",
  "debug_writer_self_test_count = 1",
  "jsonl_event_type_counts:",
  " - Observe.Context: 2",
  "last_5_crabruntimeprobe_log_lines:",
  "last_5_jsonl_events:",
  "observe_context_latest_context = solo",
  "observe_context_latest_role = solo-or-host"
)) {
  if ($summary -notmatch [regex]::Escape($required)) {
    throw "diagnostic_summary.txt missing expected content: $required"
  }
}

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareEquipmentProperty
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "executeDelay"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "mode" -Expected "active"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "probeSet" -Expected "equipment-property-read"
Assert-UnsafeGatesFalse -ConfigPath $InstalledConfigPath

New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null
Set-Content -LiteralPath (Join-Path $TestGameBin "UE4SS.log") -Encoding ASCII -Value @(
  "[CrabRuntimeProbe] boot phase: config loaded",
  "[CrabRuntimeProbe] started session=test mode=active",
  "[CrabRuntimeProbe] tickDriver=executeDelay",
  "[CrabRuntimeProbe] tick driver register begin: executeDelay",
  "[CrabRuntimeProbe] tick source registered: executeDelay",
  "[CrabRuntimeProbe] tick heartbeat tick=100 mode=active"
)
Set-Content -LiteralPath (Join-Path $resultsRoot "probe_results_property_directfield_fail.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-04T00:00:01Z","event":"Debug.StartupSmoke","probeId":"Debug.StartupSmoke","probeName":"Debug.StartupSmoke","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:02Z","event":"Debug.WriterSelfTest","probeId":"Debug.WriterSelfTest","probeName":"Debug.WriterSelfTest","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:03Z","probeId":"CrabPS.GetPropertyValue.WeaponDA","probeName":"CrabPS.GetPropertyValue.WeaponDA","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"exists=true isValid=true fullName=/Game/Test.WeaponDA name=WeaponDA"}',
  '{"timestamp":"2026-05-04T00:00:04Z","probeId":"CrabPS.GetPropertyValue.AbilityDA","probeName":"CrabPS.GetPropertyValue.AbilityDA","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"exists=true isValid=true fullName=/Game/Test.AbilityDA name=AbilityDA"}',
  '{"timestamp":"2026-05-04T00:00:05Z","probeId":"CrabPS.GetPropertyValue.MeleeDA","probeName":"CrabPS.GetPropertyValue.MeleeDA","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"exists=true isValid=true fullName=/Game/Test.MeleeDA name=MeleeDA"}',
  '{"timestamp":"2026-05-04T00:00:06Z","probeId":"CrabPS.DirectField.WeaponDA","probeName":"CrabPS.DirectField.WeaponDA","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"direct field should fail property-only collection"}'
)
$powerShellExe = (Get-Process -Id $PID).Path
& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -CollectEquipmentProperty | Out-Host
if ($LASTEXITCODE -eq 0) {
  throw "quick equipment property collection must fail when DirectField probe evidence appears."
}

$directFieldFailureSummary = Get-Content -Raw -LiteralPath $summaryPath
foreach ($required in @(
  "probeSet = equipment-property-read",
  "mode = active",
  "direct_field_probe_ran = True",
  "equipment_property_probe_ran = True",
  "equipment_property_weapon_count = 1",
  "equipment_property_ability_count = 1",
  "equipment_property_melee_count = 1",
  "unique_contexts_seen = solo",
  "unique_roles_seen = solo-or-host",
  "first_context = solo",
  "last_context = solo",
  "DirectField equipment probe appeared during property-only collection."
)) {
  if ($directFieldFailureSummary -notmatch [regex]::Escape($required)) {
    throw "direct-field failure diagnostic_summary.txt missing expected content: $required"
  }
}

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareHealthBaseline
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "executeDelay"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "mode" -Expected "active"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "probeSet" -Expected "health-baseline-read"
Assert-HealthBaselineGates -ConfigPath $InstalledConfigPath

New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null
Set-Content -LiteralPath (Join-Path $TestGameBin "UE4SS.log") -Encoding ASCII -Value @(
  "[CrabRuntimeProbe] boot phase: config loaded",
  "[CrabRuntimeProbe] started session=test mode=active",
  "[CrabRuntimeProbe] tickDriver=executeDelay",
  "[CrabRuntimeProbe] tick driver register begin: executeDelay",
  "[CrabRuntimeProbe] tick source registered: executeDelay",
  "[CrabRuntimeProbe] tick heartbeat tick=100 mode=active"
)
Set-Content -LiteralPath (Join-Path $resultsRoot "probe_results_health_baseline.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-04T00:00:01Z","event":"Debug.StartupSmoke","probeId":"Debug.StartupSmoke","probeName":"Debug.StartupSmoke","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:02Z","event":"Debug.WriterSelfTest","probeId":"Debug.WriterSelfTest","probeName":"Debug.WriterSelfTest","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:03Z","probeId":"CrabHC.HealthInfo.CurrentHealth","probeName":"CrabHC.HealthInfo.CurrentHealth","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"250"}',
  '{"timestamp":"2026-05-04T00:00:04Z","probeId":"CrabHC.HealthInfo.CurrentMaxHealth","probeName":"CrabHC.HealthInfo.CurrentMaxHealth","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"250"}',
  '{"timestamp":"2026-05-04T00:00:05Z","probeId":"CrabPS.GetPropertyValue.BaseMaxHealth","probeName":"CrabPS.GetPropertyValue.BaseMaxHealth","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"250"}'
)
& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -CollectHealthBaseline

$healthSummary = Get-Content -Raw -LiteralPath $summaryPath
foreach ($required in @(
  "probeSet = health-baseline-read",
  "allowHealthProbes = true",
  "health_probe_ran = True",
  "latest_CrabHC_CurrentHealth = 250",
  "latest_CrabHC_CurrentMaxHealth = 250",
  "latest_CrabPS_BaseMaxHealth = 250",
  "possible_base_health_model = local PlayerState base appears 250",
  "failures:",
  " - none"
)) {
  if ($healthSummary -notmatch [regex]::Escape($required)) {
    throw "health diagnostic_summary.txt missing expected content: $required"
  }
}

Set-TestConfigValue -ConfigPath $InstalledConfigPath -Key "allowWriteProbes" -Value "true"
& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -CollectHealthBaseline | Out-Host
if ($LASTEXITCODE -eq 0) {
  throw "health baseline collection must fail when allowWriteProbes is true."
}

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareHealthPlayerState
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "executeDelay"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "mode" -Expected "active"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "probeSet" -Expected "health-playerstate-read"
Assert-HealthBaselineGates -ConfigPath $InstalledConfigPath
$healthPlayerStatePrepareMarker = Get-Content -Raw -LiteralPath (Join-Path $resultsRoot "prepare_marker.json") | ConvertFrom-Json
if ($healthPlayerStatePrepareMarker.expectedProbeSet -ne "health-playerstate-read" -or $healthPlayerStatePrepareMarker.expectedTickDriver -ne "executeDelay" -or $healthPlayerStatePrepareMarker.expectedMode -ne "active") {
  throw "health playerstate prepare marker did not record the expected prepared run contract."
}

New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null
$healthPlayerStateBuildCommit = Get-TestBuildInfoValue -ScriptsRoot $scriptsRoot -Key "git_commit"
Write-TestSessionManifest -ResultsRoot $resultsRoot -SessionId "test" -GitCommit $healthPlayerStateBuildCommit -ProbeSet "health-playerstate-read" -TickDriver "executeDelay"
Set-Content -LiteralPath (Join-Path $TestGameBin "UE4SS.log") -Encoding ASCII -Value @(
  "[CrabRuntimeProbe] boot phase: config loaded",
  "[CrabRuntimeProbe] started session=test mode=active",
  "[CrabRuntimeProbe] build git_commit = $healthPlayerStateBuildCommit",
  "[CrabRuntimeProbe] tickDriver=executeDelay",
  "[CrabRuntimeProbe] tick driver register begin: executeDelay",
  "[CrabRuntimeProbe] tick source registered: executeDelay",
  "[CrabRuntimeProbe] boot phase: startup complete",
  "[CrabRuntimeProbe] tick heartbeat tick=100 mode=active"
)
Set-Content -LiteralPath (Join-Path $resultsRoot "probe_results_health_playerstate.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-04T00:00:01Z","event":"Debug.StartupSmoke","probeId":"Debug.StartupSmoke","probeName":"Debug.StartupSmoke","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:02Z","event":"Debug.WriterSelfTest","probeId":"Debug.WriterSelfTest","probeName":"Debug.WriterSelfTest","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:03Z","probeId":"CrabPS.GetPropertyValue.HealthInfo","probeName":"CrabPS.GetPropertyValue.HealthInfo","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"HealthInfo obtained"}',
  '{"timestamp":"2026-05-04T00:00:04Z","probeId":"CrabPS.HealthInfo.CurrentHealth","probeName":"CrabPS.HealthInfo.CurrentHealth","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"250.0"}',
  '{"timestamp":"2026-05-04T00:00:05Z","probeId":"CrabPS.HealthInfo.CurrentMaxHealth","probeName":"CrabPS.HealthInfo.CurrentMaxHealth","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"250.0"}',
  '{"timestamp":"2026-05-04T00:00:06Z","probeId":"CrabPS.GetPropertyValue.BaseMaxHealth","probeName":"CrabPS.GetPropertyValue.BaseMaxHealth","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"250.0"}',
  '{"timestamp":"2026-05-04T00:00:07Z","probeId":"CrabPS.GetPropertyValue.MaxHealthMultiplier","probeName":"CrabPS.GetPropertyValue.MaxHealthMultiplier","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"1.0"}'
)
& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -CollectHealthPlayerState

$playerStateHealthSummary = Get-Content -Raw -LiteralPath $summaryPath
foreach ($required in @(
  "probeSet = health-playerstate-read",
  "allowHealthProbes = true",
  "playerstate_health_probe_ran = True",
  "ambiguous_crabhc_detected = False",
  "playerstate_current_health = 250.0",
  "playerstate_current_max_health = 250.0",
  "playerstate_base_max_health = 250.0",
  "playerstate_max_health_multiplier = 1.0",
  "possible_base_health_model = local PlayerState base appears 250",
  "failures:",
  " - none"
)) {
  if ($playerStateHealthSummary -notmatch [regex]::Escape($required)) {
    throw "health playerstate diagnostic_summary.txt missing expected content: $required"
  }
}

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareHealthPlayerStateWatch
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "executeDelay"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "mode" -Expected "active"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "probeSet" -Expected "health-playerstate-watch"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "repeatProbeSet" -Expected "true"
Assert-HealthBaselineGates -ConfigPath $InstalledConfigPath
$healthPlayerStateWatchPrepareMarker = Get-Content -Raw -LiteralPath (Join-Path $resultsRoot "prepare_marker.json") | ConvertFrom-Json
if ($healthPlayerStateWatchPrepareMarker.expectedProbeSet -ne "health-playerstate-watch" -or $healthPlayerStateWatchPrepareMarker.expectedTickDriver -ne "executeDelay" -or $healthPlayerStateWatchPrepareMarker.expectedMode -ne "active") {
  throw "health playerstate watch prepare marker did not record the expected prepared run contract."
}

New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null
$healthPlayerStateWatchBuildCommit = Get-TestBuildInfoValue -ScriptsRoot $scriptsRoot -Key "git_commit"
Write-TestSessionManifest -ResultsRoot $resultsRoot -SessionId "watch" -GitCommit $healthPlayerStateWatchBuildCommit -ProbeSet "health-playerstate-watch" -TickDriver "executeDelay"
Set-Content -LiteralPath (Join-Path $TestGameBin "UE4SS.log") -Encoding ASCII -Value @(
  "[CrabRuntimeProbe] boot phase: config loaded",
  "[CrabRuntimeProbe] started session=watch mode=active",
  "[CrabRuntimeProbe] build git_commit = $healthPlayerStateWatchBuildCommit",
  "[CrabRuntimeProbe] tickDriver=executeDelay",
  "[CrabRuntimeProbe] tick driver register begin: executeDelay",
  "[CrabRuntimeProbe] tick source registered: executeDelay",
  "[CrabRuntimeProbe] boot phase: startup complete",
  "[CrabRuntimeProbe] tick heartbeat tick=100 mode=active"
)
Set-Content -LiteralPath (Join-Path $resultsRoot "probe_results_health_playerstate_watch.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-04T00:00:01Z","sessionId":"watch","event":"Debug.StartupSmoke","probeId":"Debug.StartupSmoke","probeName":"Debug.StartupSmoke","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:02Z","sessionId":"watch","event":"Debug.WriterSelfTest","probeId":"Debug.WriterSelfTest","probeName":"Debug.WriterSelfTest","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:03Z","sessionId":"watch","probeId":"Health.PlayerState.Sample","probeName":"Health.PlayerState.Sample","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"currentHealth=250 currentMaxHealth=250 baseMaxHealth=250 maxHealthMultiplier=1","currentHealth":250,"currentMaxHealth":250,"baseMaxHealth":250,"maxHealthMultiplier":1,"sampleIndex":1}',
  '{"timestamp":"2026-05-04T00:00:04Z","sessionId":"watch","probeId":"Health.PlayerState.Sample","probeName":"Health.PlayerState.Sample","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"currentHealth=225 currentMaxHealth=275 baseMaxHealth=250 maxHealthMultiplier=1.1","currentHealth":225,"currentMaxHealth":275,"baseMaxHealth":250,"maxHealthMultiplier":1.1,"sampleIndex":2}',
  '{"timestamp":"2026-05-04T00:00:05Z","sessionId":"watch","probeId":"Health.PlayerState.Sample","probeName":"Health.PlayerState.Sample","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"currentHealth=275 currentMaxHealth=275 baseMaxHealth=250 maxHealthMultiplier=1.1","currentHealth":275,"currentMaxHealth":275,"baseMaxHealth":250,"maxHealthMultiplier":1.1,"sampleIndex":3}'
)
Set-Content -LiteralPath (Join-Path $resultsRoot "access_evidence_watch.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-04T00:00:03Z","sessionId":"watch","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"Health.PlayerState.Sample","probeName":"Health.PlayerState.Sample","probeSet":"health-playerstate-watch","category":"health","symbol":"CrabPS.HealthInfo","owner":"CrabPS","member":"HealthInfo","accessMethod":"PlayerStateHealthSample","accessKind":"health","mode":"active","tickDriver":"executeDelay","tick":100,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"health_sample","valueSummary":"currentHealth=250 currentMaxHealth=250 baseMaxHealth=250 maxHealthMultiplier=1","currentHealth":250,"currentMaxHealth":250,"baseMaxHealth":250,"maxHealthMultiplier":1,"sampleIndex":1,"sourceScope":"player_state_scoped","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":true,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}'
)
& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -CollectHealthPlayerStateWatch

$playerStateHealthWatchSummary = Get-Content -Raw -LiteralPath $summaryPath
foreach ($required in @(
  "probeSet = health-playerstate-watch",
  "allowHealthProbes = true",
  "playerstate_health_watch_probe_ran = True",
  "ambiguous_crabhc_detected = False",
  "crab_hc_touched = False",
  "health_playerstate_watch_sample_count = 3",
  "health_playerstate_watch_currentHealth_first = 250",
  "health_playerstate_watch_currentHealth_last = 275",
  "health_playerstate_watch_currentHealth_min = 225",
  "health_playerstate_watch_currentHealth_max = 275",
  "health_playerstate_watch_currentMaxHealth_first = 250",
  "health_playerstate_watch_currentMaxHealth_last = 275",
  "health_playerstate_watch_currentMaxHealth_min = 250",
  "health_playerstate_watch_currentMaxHealth_max = 275",
  "health_playerstate_watch_baseMaxHealth_first = 250",
  "health_playerstate_watch_baseMaxHealth_last = 250",
  "health_playerstate_watch_baseMaxHealth_min = 250",
  "health_playerstate_watch_baseMaxHealth_max = 250",
  "health_playerstate_watch_maxHealthMultiplier_first = 1",
  "health_playerstate_watch_maxHealthMultiplier_last = 1.1",
  "health_playerstate_watch_maxHealthMultiplier_min = 1",
  "health_playerstate_watch_maxHealthMultiplier_max = 1.1",
  "failures:",
  " - none"
)) {
  if ($playerStateHealthWatchSummary -notmatch [regex]::Escape($required)) {
    throw "health playerstate watch diagnostic_summary.txt missing expected content: $required"
  }
}

& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "validate-latest-crash-bundle.ps1") -GameBin $TestGameBin -ExpectedProbeSet "health-playerstate-watch" -ExpectedTickDriver "executeDelay" -ExpectedMode "active" -RequirePreparedRun | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw "validate-latest-crash-bundle.ps1 must pass for a clean health-playerstate-watch bundle."
}

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareHealthPlayerState
New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null
$healthPlayerStateCrabHcBuildCommit = Get-TestBuildInfoValue -ScriptsRoot $scriptsRoot -Key "git_commit"
Write-TestSessionManifest -ResultsRoot $resultsRoot -SessionId "test" -GitCommit $healthPlayerStateCrabHcBuildCommit -ProbeSet "health-playerstate-read" -TickDriver "executeDelay"
Set-Content -LiteralPath (Join-Path $TestGameBin "UE4SS.log") -Encoding ASCII -Value @(
  "[CrabRuntimeProbe] boot phase: config loaded",
  "[CrabRuntimeProbe] started session=test mode=active",
  "[CrabRuntimeProbe] build git_commit = $healthPlayerStateCrabHcBuildCommit",
  "[CrabRuntimeProbe] tickDriver=executeDelay",
  "[CrabRuntimeProbe] tick driver register begin: executeDelay",
  "[CrabRuntimeProbe] tick source registered: executeDelay",
  "[CrabRuntimeProbe] boot phase: startup complete"
)
Set-Content -LiteralPath (Join-Path $resultsRoot "probe_results_health_playerstate_crabhc_fail.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-04T00:00:01Z","event":"Debug.StartupSmoke","probeId":"Debug.StartupSmoke","probeName":"Debug.StartupSmoke","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:02Z","event":"Debug.WriterSelfTest","probeId":"Debug.WriterSelfTest","probeName":"Debug.WriterSelfTest","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:03Z","probeId":"FindFirstOf.CrabHC","probeName":"FindFirstOf.CrabHC","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"CrabHC found"}',
  '{"timestamp":"2026-05-04T00:00:04Z","probeId":"CrabPS.GetPropertyValue.HealthInfo","probeName":"CrabPS.GetPropertyValue.HealthInfo","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"HealthInfo obtained"}',
  '{"timestamp":"2026-05-04T00:00:05Z","probeId":"CrabPS.HealthInfo.CurrentHealth","probeName":"CrabPS.HealthInfo.CurrentHealth","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"250.0"}',
  '{"timestamp":"2026-05-04T00:00:06Z","probeId":"CrabPS.HealthInfo.CurrentMaxHealth","probeName":"CrabPS.HealthInfo.CurrentMaxHealth","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"250.0"}',
  '{"timestamp":"2026-05-04T00:00:07Z","probeId":"CrabPS.GetPropertyValue.BaseMaxHealth","probeName":"CrabPS.GetPropertyValue.BaseMaxHealth","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"250.0"}',
  '{"timestamp":"2026-05-04T00:00:08Z","probeId":"CrabPS.GetPropertyValue.MaxHealthMultiplier","probeName":"CrabPS.GetPropertyValue.MaxHealthMultiplier","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"1.0"}'
)
& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -CollectHealthPlayerState | Out-Host
if ($LASTEXITCODE -eq 0) {
  throw "health playerstate collection must fail when FindFirstOf.CrabHC evidence appears."
}

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareHealthPlayerState
New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null
$staleBaselineBuildCommit = Get-TestBuildInfoValue -ScriptsRoot $scriptsRoot -Key "git_commit"
Write-TestSessionManifest -ResultsRoot $resultsRoot -SessionId "stale_baseline" -GitCommit $staleBaselineBuildCommit -ProbeSet "health-baseline-read" -TickDriver "executeDelay"
Set-Content -LiteralPath (Join-Path $TestGameBin "UE4SS.log") -Encoding ASCII -Value @(
  "[CrabRuntimeProbe] boot phase: config loaded",
  "[CrabRuntimeProbe] started session=stale_baseline mode=active",
  "[CrabRuntimeProbe] build git_commit = $staleBaselineBuildCommit",
  "[CrabRuntimeProbe] tickDriver=executeDelay",
  "[CrabRuntimeProbe] tick driver register begin: executeDelay",
  "[CrabRuntimeProbe] tick source registered: executeDelay",
  "[CrabRuntimeProbe] boot phase: startup complete"
)
Set-Content -LiteralPath (Join-Path $resultsRoot "probe_results_stale_baseline.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-04T00:00:01Z","sessionId":"stale_baseline","event":"Debug.StartupSmoke","probeId":"Debug.StartupSmoke","probeName":"Debug.StartupSmoke","result":"ok"}',
  '{"timestamp":"2026-05-04T00:00:02Z","sessionId":"stale_baseline","probeId":"CrabPS.GetPropertyValue.HealthInfo","probeName":"CrabPS.GetPropertyValue.HealthInfo","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"HealthInfo obtained"}',
  '{"timestamp":"2026-05-04T00:00:03Z","sessionId":"stale_baseline","probeId":"CrabPS.HealthInfo.CurrentHealth","probeName":"CrabPS.HealthInfo.CurrentHealth","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"250.0"}',
  '{"timestamp":"2026-05-04T00:00:04Z","sessionId":"stale_baseline","probeId":"CrabPS.HealthInfo.CurrentMaxHealth","probeName":"CrabPS.HealthInfo.CurrentMaxHealth","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"250.0"}',
  '{"timestamp":"2026-05-04T00:00:05Z","sessionId":"stale_baseline","probeId":"CrabPS.GetPropertyValue.BaseMaxHealth","probeName":"CrabPS.GetPropertyValue.BaseMaxHealth","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"250.0"}',
  '{"timestamp":"2026-05-04T00:00:06Z","sessionId":"stale_baseline","probeId":"CrabPS.GetPropertyValue.MaxHealthMultiplier","probeName":"CrabPS.GetPropertyValue.MaxHealthMultiplier","category":"health","result":"ok","context":"solo","role":"solo-or-host","lifecycleState":"stable","valueSummary":"1.0"}'
)
& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -CollectHealthPlayerState | Out-Host
if ($LASTEXITCODE -eq 0) {
  throw "health playerstate collection must fail when latest manifest says health-baseline-read."
}
$staleBaselineSummary = Get-Content -Raw -LiteralPath $summaryPath
if ($staleBaselineSummary -notmatch [regex]::Escape("Stale baseline artifact detected: expected health-playerstate-read but latest manifest says health-baseline-read.")) {
  throw "health playerstate stale-baseline summary did not call out the stale health-baseline manifest."
}

& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "validate-latest-crash-bundle.ps1") -GameBin $TestGameBin -ExpectedProbeSet "health-playerstate-read" -ExpectedTickDriver "executeDelay" -ExpectedMode "active" -RequirePreparedRun | Out-Host
if ($LASTEXITCODE -eq 0) {
  throw "validate-latest-crash-bundle.ps1 must fail when latest manifest says health-baseline-read for health-playerstate."
}

Write-Host "CrabRuntimeProbe packaging checks passed."
