[CmdletBinding()]
param(
  [string]$GameBin = "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

function Read-JsonFileOrNull {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -ErrorAction Stop)
}

function Get-CampaignPhase {
  param(
    [object]$Plan,
    [string]$PhaseId
  )

  foreach ($phase in @($Plan.phases)) {
    if ($phase.phaseId -eq $PhaseId) { return $phase }
  }
  return $null
}

function Get-LatestFile {
  param(
    [string]$Directory,
    [string]$Filter
  )

  if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return $null }
  return @(Get-ChildItem -LiteralPath $Directory -Filter $Filter -File -Force -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc, Name -Descending |
    Select-Object -First 1)
}

function Find-LatestCrashFolder {
  param([string]$GameBinFull)

  $candidates = @()
  $savedCrashPath = [System.IO.Path]::GetFullPath((Join-Path $GameBinFull "..\..\Saved\Crashes"))
  $localAppData = [Environment]::GetFolderPath("LocalApplicationData")
  if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
    $candidates += Join-Path $localAppData "CrabChampions\Saved\Crashes"
    $candidates += Join-Path $localAppData "Crab Champions\Saved\Crashes"
  }
  $candidates += $savedCrashPath

  $folders = @()
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Container) {
      $folders += @(Get-ChildItem -LiteralPath $candidate -Directory -Force -ErrorAction SilentlyContinue)
    }
  }

  if ($folders.Count -eq 0) { return $null }
  return @($folders | Sort-Object LastWriteTimeUtc, FullName -Descending | Select-Object -First 1)
}

function Invoke-CampaignCollect {
  param(
    [string]$PhaseId,
    [string]$GameBinFull
  )

  $cycle = Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1"
  if ($PhaseId -eq "smoke-startup") {
    & $cycle -GameBin $GameBinFull -CollectSmoke
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "executeDelay") {
    & $cycle -GameBin $GameBinFull -Collect
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "observe-context") {
    & $cycle -GameBin $GameBinFull -Collect -ExpectObserveContext
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "equipment-property-read") {
    & $cycle -GameBin $GameBinFull -CollectEquipmentProperty
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "health-playerstate-read") {
    & $cycle -GameBin $GameBinFull -CollectHealthPlayerState
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "health-playerstate-watch" -or $PhaseId -eq "multiplayer-health-playerstate-watch") {
    & $cycle -GameBin $GameBinFull -CollectHealthPlayerStateWatch
    return $LASTEXITCODE
  }
  throw "Campaign phase '$PhaseId' is not implemented and cannot be collected."
}

function Read-ManifestCommit {
  param([object]$Manifest)
  if ($null -ne $Manifest -and ($Manifest.PSObject.Properties.Name -contains "buildInfo") -and ($Manifest.buildInfo.PSObject.Properties.Name -contains "git_commit")) {
    return [string]$Manifest.buildInfo.git_commit
  }
  return ""
}

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$GameBinFull = [System.IO.Path]::GetFullPath($GameBin)
$PlanPath = Join-Path $RepoRoot "campaign\campaign_plan.crabruntimeprobe-read-map.json"
$InstallScriptsRoot = Join-Path $GameBinFull "Mods\CrabRuntimeProbe\Scripts"
$ResultsRoot = Join-Path $InstallScriptsRoot "results"
$InstalledStatePath = Join-Path $ResultsRoot "campaign_state.json"
$RepoStatePath = Join-Path $RepoRoot "evidence\campaign_state.json"
$PrepareMarkerPath = Join-Path $ResultsRoot "prepare_marker.json"

$plan = Read-JsonFileOrNull -Path $PlanPath
$state = Read-JsonFileOrNull -Path $InstalledStatePath
$marker = Read-JsonFileOrNull -Path $PrepareMarkerPath

if ($null -eq $plan) { throw "Missing campaign plan: $PlanPath" }
if ($null -eq $state) { throw "Missing campaign_state.json. Run scripts\quick-campaign-prepare.ps1 first." }
if ($null -eq $marker) { throw "Missing prepare_marker.json. Run scripts\quick-campaign-prepare.ps1 first." }
if ($marker.campaign -ne $plan.campaign) { throw "Prepare marker campaign '$($marker.campaign)' does not match plan '$($plan.campaign)'." }

$phase = Get-CampaignPhase -Plan $plan -PhaseId ([string]$marker.phaseId)
if ($null -eq $phase) { throw "Prepare marker phase '$($marker.phaseId)' is not in the campaign plan." }

$collectExit = 1
$validatorExit = 1
$status = "failed"
$reason = ""
$latestSessionId = ""
$latestCommit = ""
$latestSummaryPath = ""

try {
  Invoke-CampaignCollect -PhaseId $phase.phaseId -GameBinFull $GameBinFull
  $collectExit = $LASTEXITCODE
} catch {
  $reason = $_.Exception.Message
  $collectExit = 1
}

$PowerShellExe = (Get-Process -Id $PID).Path
& $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "validate-latest-crash-bundle.ps1") `
  -GameBin $GameBinFull `
  -ExpectedProbeSet ([string]$phase.probeSet) `
  -ExpectedTickDriver ([string]$phase.tickDriver) `
  -ExpectedMode ([string]$phase.mode) `
  -RequirePreparedRun
$validatorExit = $LASTEXITCODE

$latestManifestFile = Get-LatestFile -Directory $ResultsRoot -Filter "session_manifest_*.json"
$latestProbeFile = Get-LatestFile -Directory $ResultsRoot -Filter "probe_results_*.jsonl"
$latestSummaryFile = Get-LatestFile -Directory $ResultsRoot -Filter "diagnostic_summary.txt"
if ($null -eq $latestSummaryFile) {
  $candidateSummary = Join-Path $InstallScriptsRoot "diagnostic_summary.txt"
  if (Test-Path -LiteralPath $candidateSummary -PathType Leaf) {
    $latestSummaryFile = Get-Item -LiteralPath $candidateSummary
  }
}
$latestManifest = if ($null -ne $latestManifestFile) { Read-JsonFileOrNull -Path $latestManifestFile.FullName } else { $null }
if ($null -ne $latestManifest -and ($latestManifest.PSObject.Properties.Name -contains "sessionId")) {
  $latestSessionId = [string]$latestManifest.sessionId
}
$latestCommit = Read-ManifestCommit -Manifest $latestManifest

$prepareTime = $null
if ($marker.PSObject.Properties.Name -contains "preparedAt") {
  $parsedPrepareTime = [datetime]::MinValue
  if ([datetime]::TryParse([string]$marker.preparedAt, [ref]$parsedPrepareTime)) {
    $prepareTime = $parsedPrepareTime.ToUniversalTime()
  }
}

$latestCrashFolder = Find-LatestCrashFolder -GameBinFull $GameBinFull
$crashAfterPrepare = $false
if ($null -ne $prepareTime -and $null -ne $latestCrashFolder -and $latestCrashFolder.LastWriteTimeUtc -gt $prepareTime.AddSeconds(-2)) {
  $crashAfterPrepare = $true
}

if ($collectExit -eq 0 -and $validatorExit -eq 0 -and $null -ne $latestManifestFile -and $null -ne $latestProbeFile) {
  $status = "passed"
} elseif ($crashAfterPrepare) {
  $status = "crashed"
  if ([string]::IsNullOrWhiteSpace($reason)) { $reason = "Crash folder was updated after campaign prepare." }
} elseif ($null -eq $latestManifestFile -or $null -eq $latestProbeFile) {
  $status = "no_evidence"
  if ([string]::IsNullOrWhiteSpace($reason)) { $reason = "No fresh session manifest or probe_results JSONL was found." }
} else {
  $status = "failed"
  if ([string]::IsNullOrWhiteSpace($reason)) { $reason = "Collection or stale-artifact validation failed." }
}

if ($null -ne $latestManifestFile) {
  try {
    & (Join-Path $PSScriptRoot "import-latest-runtime-evidence.ps1") -From $ResultsRoot
  } catch {
    if ($status -eq "passed") {
      $status = "failed"
      $reason = "Evidence import/docs/wiki generation failed: $($_.Exception.Message)"
    }
  }
}

if (-not [string]::IsNullOrWhiteSpace($latestSessionId)) {
  $latestSummaryPath = "evidence/runtime/$latestSessionId/diagnostic_summary.txt"
} elseif ($null -ne $latestSummaryFile) {
  $latestSummaryPath = $latestSummaryFile.FullName
}

Push-Location $RepoRoot
try {
  node tools/update_campaign_state.js collect --state $InstalledStatePath --phase $phase.phaseId --status $status --reason $reason --latest-session $latestSessionId --latest-commit $latestCommit --latest-summary $latestSummaryPath | Out-Null
  Copy-Item -LiteralPath $InstalledStatePath -Destination $RepoStatePath -Force
  node tools/generate_campaign_docs.js --state $RepoStatePath --write-state --quiet | Out-Null
} finally {
  Pop-Location
}

$updatedState = Read-JsonFileOrNull -Path $RepoStatePath
Write-Host "phaseResult = $status"
Write-Host "phaseId = $($phase.phaseId)"
Write-Host "nextRecommendedPhase = $($updatedState.nextRecommendedPhase)"

if ($status -ne "passed") {
  exit 1
}
