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

function Read-JsonLines {
  param([string[]]$Paths)

  $rows = @()
  foreach ($path in @($Paths)) {
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    foreach ($line in Get-Content -LiteralPath $path) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $rows += @($line | ConvertFrom-Json -ErrorAction Stop)
    }
  }
  return $rows
}

function Test-NonEmptyRawIdentityValue {
  param([object]$Value)

  if ($null -eq $Value) { return $false }
  if ($Value -is [string]) { return -not [string]::IsNullOrWhiteSpace($Value) }
  if ($Value -is [System.Collections.IEnumerable]) {
    foreach ($item in $Value) {
      if (Test-NonEmptyRawIdentityValue -Value $item) { return $true }
    }
    return $false
  }
  if ($Value.PSObject -and $Value.PSObject.Properties.Count -gt 0) {
    foreach ($property in $Value.PSObject.Properties) {
      if (Test-NonEmptyRawIdentityValue -Value $property.Value) { return $true }
    }
    return $false
  }
  return $false
}

function Test-IdentityRow {
  param([object]$Row)

  $name = ""
  foreach ($field in @("probeName", "probeId", "event")) {
    if ($Row.PSObject.Properties.Name -contains $field) {
      $name = [string]$Row.$field
      if (-not [string]::IsNullOrWhiteSpace($name)) { break }
    }
  }
  return $name -match "^Identity\."
}

function Get-RosterEvidenceClassification {
  param([object[]]$Rows)

  $identityRows = @($Rows | Where-Object { Test-IdentityRow -Row $_ })
  $rawIdentityLeak = $false
  $localIdentityConfirmed = $false
  $visibleRosterConfirmed = $false

  foreach ($row in $identityRows) {
    $rowAllowsRaw = $false
    if (($row.PSObject.Properties.Name -contains "allowRawIdentityEvidence") -and $row.allowRawIdentityEvidence -eq $true) {
      $rowAllowsRaw = $true
    }
    if (($row.PSObject.Properties.Name -contains "safetyGates") -and $null -ne $row.safetyGates -and
        ($row.safetyGates.PSObject.Properties.Name -contains "allowRawIdentityEvidence") -and
        $row.safetyGates.allowRawIdentityEvidence -eq $true) {
      $rowAllowsRaw = $true
    }

    if (-not $rowAllowsRaw) {
      if (($row.PSObject.Properties.Name -contains "rawIdentityEvidence") -and $row.rawIdentityEvidence -eq $true) {
        $rawIdentityLeak = $true
      }
      if (($row.PSObject.Properties.Name -contains "rawDisplayNames") -and (Test-NonEmptyRawIdentityValue -Value $row.rawDisplayNames)) {
        $rawIdentityLeak = $true
      }
      if (($row.PSObject.Properties.Name -contains "rawStableIds") -and (Test-NonEmptyRawIdentityValue -Value $row.rawStableIds)) {
        $rawIdentityLeak = $true
      }
    }

    $name = ""
    foreach ($field in @("probeName", "probeId", "event")) {
      if ($row.PSObject.Properties.Name -contains $field) {
        $name = [string]$row.$field
        if (-not [string]::IsNullOrWhiteSpace($name)) { break }
      }
    }
    if (($name -eq "Identity.LocalPlayer.Sample" -or $name -eq "Identity.PlayerState.Sample") -and
        ($row.result -eq "ok" -or $row.localPlayerPresent -eq $true) -and
        ($row.localPlayerPresent -eq $true -or
          (Test-NonEmptyRawIdentityValue -Value $row.displayNameFingerprints) -or
          (Test-NonEmptyRawIdentityValue -Value $row.stableIdFingerprints))) {
      $localIdentityConfirmed = $true
    }

    $visibleCount = 0
    $hasVisibleCount = [int]::TryParse([string]$row.visiblePlayerCount, [ref]$visibleCount)
    if ($hasVisibleCount -and $visibleCount -gt 1) {
      $visibleRosterConfirmed = $true
    }
    if (($row.PSObject.Properties.Name -contains "rosterSourceResolved") -and $row.rosterSourceResolved -eq $true) {
      $visibleRosterConfirmed = $true
    }
    if ($name -eq "Identity.VisiblePlayers.Sample" -and $row.result -eq "ok" -and $row.sourceScope -eq "runtime_roster" -and
        ($row.PSObject.Properties.Name -contains "playerArrayValueKind") -and $row.playerArrayValueKind -eq "table" -and
        $hasVisibleCount -and $visibleCount -gt 1) {
      $visibleRosterConfirmed = $true
    }
  }

  return [pscustomobject]@{
    identityEvidenceFound = $identityRows.Count -gt 0
    rawIdentityLeak = $rawIdentityLeak
    localIdentityConfirmed = $localIdentityConfirmed
    visibleRosterConfirmed = $visibleRosterConfirmed
  }
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
  if ($PhaseId -eq "multiplayer-roster-read") {
    & $cycle -GameBin $GameBinFull -Collect -AllowIdentityProbes
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
$latestAccessFile = Get-LatestFile -Directory $ResultsRoot -Filter "access_evidence_*.jsonl"
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

if ($status -eq "passed" -and $phase.phaseId -eq "multiplayer-roster-read") {
  $rows = Read-JsonLines -Paths @(
    $(if ($null -ne $latestProbeFile) { $latestProbeFile.FullName } else { "" }),
    $(if ($null -ne $latestAccessFile) { $latestAccessFile.FullName } else { "" })
  )
  $roster = Get-RosterEvidenceClassification -Rows $rows
  if (-not $roster.identityEvidenceFound) {
    $status = "no_evidence"
    $reason = "No multiplayer roster identity probe evidence was found."
  } elseif ($roster.rawIdentityLeak) {
    $status = "failed"
    $reason = "Raw identity evidence appeared even though allowRawIdentityEvidence should be false."
  } elseif ($roster.visibleRosterConfirmed) {
    $status = "passed"
  } elseif ($roster.localIdentityConfirmed) {
    $status = "roster_source_unresolved"
    $reason = "Local PlayerState identity read confirmed; roster source candidates did not expose a visible multiplayer roster."
  } else {
    $status = "no_evidence"
    $reason = "Roster probes ran but did not confirm local identity or visible roster evidence."
  }
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

if ($status -ne "passed" -and $status -ne "local_identity_confirmed" -and $status -ne "roster_source_unresolved") {
  exit 1
}
