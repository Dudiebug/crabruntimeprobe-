[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$DefaultGameBin = "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"
$PowerShellExe = (Get-Process -Id $PID).Path
$ResultsRoot = Join-Path $DefaultGameBin "Mods\CrabRuntimeProbe\Scripts\results"
$SummaryPath = Join-Path $DefaultGameBin "Mods\CrabRuntimeProbe\Scripts\diagnostic_summary.txt"

& $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $DefaultGameBin -CollectMaxSafePlayRecorder
$collectExit = $LASTEXITCODE

& $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "validate-latest-crash-bundle.ps1") -GameBin $DefaultGameBin -ExpectedProbeSet "max-safe-play-recorder" -ExpectedTickDriver "executeDelay" -ExpectedMode "active" -RequirePreparedRun
$validatorExit = $LASTEXITCODE

$classification = "not found"
$sampleCount = "not found"
$catalogSnapshots = "not found"
$entryCount = "not found"
$rejectedCount = "not found"
$topRejectionReasons = "not found"
if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) {
  foreach ($line in @(Get-Content -LiteralPath $SummaryPath)) {
    if ($line -match "^\s*max_safe_play_classification\s*=\s*(.*?)\s*$") { $classification = $matches[1].Trim() }
    if ($line -match "^\s*max_safe_play_scalar_sample_count\s*=\s*(.*?)\s*$") { $sampleCount = $matches[1].Trim() }
    if ($line -match "^\s*max_safe_play_perk_catalog_snapshot_count\s*=\s*(.*?)\s*$") { $catalogSnapshots = $matches[1].Trim() }
    if ($line -match "^\s*max_safe_play_perk_da_entry_count\s*=\s*(.*?)\s*$") { $entryCount = $matches[1].Trim() }
    if ($line -match "^\s*max_safe_play_perk_da_rejected_candidate_count\s*=\s*(.*?)\s*$") { $rejectedCount = $matches[1].Trim() }
    if ($line -match "^\s*max_safe_play_perk_da_top_rejection_reasons\s*=\s*(.*?)\s*$") { $topRejectionReasons = $matches[1].Trim() }
  }
}

if ($collectExit -eq 0 -and $validatorExit -eq 0) {
  & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "import-latest-runtime-evidence.ps1") -From $ResultsRoot
}

Write-Host "phaseResult = $classification"
Write-Host "summary = max_safe_play_scalar_sample_count $sampleCount; max_safe_play_perk_catalog_snapshot_count $catalogSnapshots; max_safe_play_perk_da_entry_count $entryCount; max_safe_play_perk_da_rejected_candidate_count $rejectedCount; max_safe_play_perk_da_top_rejection_reasons $topRejectionReasons"
if ($classification -eq "max_safe_play_no_playerstate_samples") {
  Write-Host "remediation = No PlayerState-present samples collected. Launch into a stable world/run and play for at least 1 to 5 minutes before collecting."
}

if ($collectExit -ne 0 -or $validatorExit -ne 0) {
  exit 1
}

exit 0
