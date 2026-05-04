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
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowHealthProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )) {
    Assert-ConfigValue -ConfigPath $ConfigPath -Key $key -Expected "false"
  }
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
Assert-UnsafeGatesFalse -ConfigPath $SourceConfigPath

& (Join-Path $PSScriptRoot "export-client-folder.ps1") -OutputPath $ExportRoot

Assert-CrabRuntimeProbeModLayout -ModRoot $ExportedModRoot -Label "exported CrabRuntimeProbe mod"
Assert-CrabRuntimeProbeConfig -ConfigPath $ExportedConfigPath -Label "exported config"
Assert-ConfigValue -ConfigPath $ExportedConfigPath -Key "tickDriver" -Expected "none"
Assert-UnsafeGatesFalse -ConfigPath $ExportedConfigPath

New-Item -ItemType Directory -Force -Path $TestGameBin | Out-Null
& (Join-Path $PSScriptRoot "install-client-to-game.ps1") $TestGameBin
& (Join-Path $PSScriptRoot "verify-installed-client.ps1") $TestGameBin
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "none"
Assert-UnsafeGatesFalse -ConfigPath $InstalledConfigPath

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareSmoke
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "none"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "debugWriterSelfTest" -Expected "true"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "debugTickHeartbeat" -Expected "false"
Assert-UnsafeGatesFalse -ConfigPath $InstalledConfigPath

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareTickDriver "executeDelay"
Assert-ConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver" -Expected "executeDelay"
Assert-UnsafeGatesFalse -ConfigPath $InstalledConfigPath

$gameplayPrepareScript = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "quick-gameplay-observe-prepare.ps1")
if ($gameplayPrepareScript -notmatch 'PrepareTickDriver executeDelay') {
  throw "quick-gameplay-observe-prepare.ps1 must prepare executeDelay explicitly."
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

Write-Host "CrabRuntimeProbe packaging checks passed."
