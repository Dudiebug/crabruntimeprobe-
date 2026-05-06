[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$DefaultGameBin = "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"
$PowerShellExe = (Get-Process -Id $PID).Path
$ResultsRoot = Join-Path $DefaultGameBin "Mods\CrabRuntimeProbe\Scripts\results"
$SummaryPath = Join-Path $DefaultGameBin "Mods\CrabRuntimeProbe\Scripts\diagnostic_summary.txt"

& $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $DefaultGameBin -CollectSafeScalarWatch
$collectExit = $LASTEXITCODE

& $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "validate-latest-crash-bundle.ps1") -GameBin $DefaultGameBin -ExpectedProbeSet "safe-scalar-watch" -ExpectedTickDriver "executeDelay" -ExpectedMode "active" -RequirePreparedRun
$validatorExit = $LASTEXITCODE

if ($collectExit -eq 0 -and $validatorExit -eq 0) {
  & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "import-latest-runtime-evidence.ps1") -From $ResultsRoot
  $classification = "not found"
  $sampleCount = "not found"
  if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) {
    foreach ($line in @(Get-Content -LiteralPath $SummaryPath)) {
      if ($line -match "^\s*safe_scalar_watch_classification\s*=\s*(.*?)\s*$") { $classification = $matches[1].Trim() }
      if ($line -match "^\s*safe_scalar_watch_sample_count\s*=\s*(.*?)\s*$") { $sampleCount = $matches[1].Trim() }
    }
  }
  Write-Host "phaseResult = $classification"
  Write-Host "summary = safe_scalar_watch_sample_count $sampleCount"
}

if ($collectExit -ne 0 -or $validatorExit -ne 0) {
  exit 1
}

exit 0
