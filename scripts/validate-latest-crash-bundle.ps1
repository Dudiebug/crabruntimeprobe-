[CmdletBinding()]
param(
  [string]$GameBin = "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64",
  [string]$ExpectedProbeSet = "",
  [string]$ExpectedTickDriver = "",
  [string]$ExpectedMode = "",
  [switch]$RequirePreparedRun
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

function Read-KeyValueFile {
  param([string]$Path)

  $values = @{}
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $values }
  foreach ($line in @(Get-Content -LiteralPath $Path)) {
    if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$') {
      $values[$matches[1]] = $matches[2].Trim()
    }
  }
  return $values
}

function Read-JsonFileOrNull {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try {
    return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -ErrorAction Stop)
  } catch {
    return $null
  }
}

function Get-FirstRecordValue {
  param(
    [object[]]$Files,
    [string[]]$Names
  )

  foreach ($file in $Files) {
    foreach ($line in @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      try {
        $record = $line | ConvertFrom-Json -ErrorAction Stop
      } catch {
        continue
      }
      foreach ($name in $Names) {
        if ($record.PSObject.Properties.Name -contains $name) {
          $value = [string]$record.$name
          if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        }
      }
    }
  }
  return ""
}

function Test-JsonlAllRecordsMatch {
  param(
    [object[]]$Files,
    [string]$Name,
    [string]$Expected
  )

  if ([string]::IsNullOrWhiteSpace($Expected)) { return "not checked" }
  if ($Files.Count -eq 0) { return "no files" }

  $seen = 0
  foreach ($file in $Files) {
    foreach ($line in @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      try {
        $record = $line | ConvertFrom-Json -ErrorAction Stop
      } catch {
        continue
      }
      if ($record.PSObject.Properties.Name -contains $Name) {
        $seen += 1
        if ([string]$record.$Name -ne $Expected) { return "false" }
      }
    }
  }

  if ($seen -eq 0) { return "no $Name records" }
  return "true"
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

$GameBinFull = [System.IO.Path]::GetFullPath($GameBin)
$ScriptsRoot = Join-Path $GameBinFull "Mods\CrabRuntimeProbe\Scripts"
$ResultsRoot = Join-Path $ScriptsRoot "results"
$BuildInfoPath = Join-Path $ScriptsRoot "build_info.txt"
$ConfigPath = Join-Path $ScriptsRoot "config.txt"
$PrepareMarkerPath = Join-Path $ResultsRoot "prepare_marker.json"
$Ue4ssLogPath = Join-Path $GameBinFull "UE4SS.log"

$buildInfo = Read-KeyValueFile -Path $BuildInfoPath
$installedCommit = if ($buildInfo.ContainsKey("git_commit")) { $buildInfo["git_commit"] } else { "missing" }
$installedProbeSet = Get-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "probeSet"
$installedTickDriver = Get-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "tickDriver"
$installedMode = Get-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "mode"
if ($null -eq $installedProbeSet) { $installedProbeSet = "missing" }
if ($null -eq $installedTickDriver) { $installedTickDriver = "missing" }
if ($null -eq $installedMode) { $installedMode = "missing" }

$prepareMarker = Read-JsonFileOrNull -Path $PrepareMarkerPath
$prepareFound = $null -ne $prepareMarker
$expectedCommit = if ($prepareFound -and ($prepareMarker.PSObject.Properties.Name -contains "expectedGitCommit")) { [string]$prepareMarker.expectedGitCommit } else { $installedCommit }
$expectedProbeSetFromMarker = if ($prepareFound -and ($prepareMarker.PSObject.Properties.Name -contains "expectedProbeSet")) { [string]$prepareMarker.expectedProbeSet } else { $ExpectedProbeSet }
$expectedTickDriverFromMarker = if ($prepareFound -and ($prepareMarker.PSObject.Properties.Name -contains "expectedTickDriver")) { [string]$prepareMarker.expectedTickDriver } else { $ExpectedTickDriver }
$expectedModeFromMarker = if ($prepareFound -and ($prepareMarker.PSObject.Properties.Name -contains "expectedMode")) { [string]$prepareMarker.expectedMode } else { $ExpectedMode }

$latestManifestFile = Get-LatestFile -Directory $ResultsRoot -Filter "session_manifest_*.json"
$latestProbeFile = Get-LatestFile -Directory $ResultsRoot -Filter "probe_results_*.jsonl"
$latestEvidenceFile = Get-LatestFile -Directory $ResultsRoot -Filter "access_evidence_*.jsonl"
$latestManifest = if ($null -ne $latestManifestFile) { Read-JsonFileOrNull -Path $latestManifestFile.FullName } else { $null }

$manifestSessionId = if ($null -ne $latestManifest -and ($latestManifest.PSObject.Properties.Name -contains "sessionId")) { [string]$latestManifest.sessionId } else { "not found" }
$manifestCommit = if ($null -ne $latestManifest -and ($latestManifest.PSObject.Properties.Name -contains "buildInfo") -and ($latestManifest.buildInfo.PSObject.Properties.Name -contains "git_commit")) { [string]$latestManifest.buildInfo.git_commit } else { "not found" }
$manifestProbeSet = if ($null -ne $latestManifest -and ($latestManifest.PSObject.Properties.Name -contains "probeSet")) { [string]$latestManifest.probeSet } else { "not found" }
$manifestTickDriver = if ($null -ne $latestManifest -and ($latestManifest.PSObject.Properties.Name -contains "tickDriver")) { [string]$latestManifest.tickDriver } else { "not found" }

$logText = if (Test-Path -LiteralPath $Ue4ssLogPath -PathType Leaf) { Get-Content -Raw -LiteralPath $Ue4ssLogPath } else { "" }
$logContainsSession = (-not [string]::IsNullOrWhiteSpace($manifestSessionId)) -and $manifestSessionId -ne "not found" -and $logText.Contains($manifestSessionId)
$logContainsCommit = (-not [string]::IsNullOrWhiteSpace($installedCommit)) -and $installedCommit -ne "missing" -and $logText.Contains($installedCommit)

$currentSessionFiles = @()
if ($null -ne $latestProbeFile) { $currentSessionFiles += $latestProbeFile }
if ($null -ne $latestEvidenceFile) { $currentSessionFiles += $latestEvidenceFile }
$evidenceSession = Get-FirstRecordValue -Files $currentSessionFiles -Names @("sessionId")
$evidenceProbeSetMatch = Test-JsonlAllRecordsMatch -Files @($latestEvidenceFile | Where-Object { $null -ne $_ }) -Name "probeSet" -Expected $installedProbeSet
$evidenceTickDriverMatch = Test-JsonlAllRecordsMatch -Files $currentSessionFiles -Name "tickDriver" -Expected $installedTickDriver
$evidenceSessionMatch = if ($manifestSessionId -eq "not found") { "not checked" } elseif ([string]::IsNullOrWhiteSpace($evidenceSession)) { "no records" } else { [string]($evidenceSession -eq $manifestSessionId) }
$evidenceMatchesInstalledConfigProbeSet = ($evidenceProbeSetMatch -in @("true", "no probeSet records", "no files")) -and ($evidenceTickDriverMatch -in @("true", "no tickDriver records", "no files")) -and ($evidenceSessionMatch -in @("True", "true", "no records", "not checked"))

$prepareTime = $null
if ($prepareFound -and ($prepareMarker.PSObject.Properties.Name -contains "preparedAt")) {
  $parsedPrepareTime = [datetime]::MinValue
  if ([datetime]::TryParse([string]$prepareMarker.preparedAt, [ref]$parsedPrepareTime)) {
    $prepareTime = $parsedPrepareTime
  }
}

$artifactOlderThanPrepare = $false
if ($null -ne $prepareTime) {
  foreach ($file in @($latestManifestFile, $latestProbeFile, $latestEvidenceFile)) {
    if ($null -ne $file -and $file.LastWriteTimeUtc -lt $prepareTime.ToUniversalTime().AddSeconds(-2)) {
      $artifactOlderThanPrepare = $true
    }
  }
}

$latestCrashFolder = Find-LatestCrashFolder -GameBinFull $GameBinFull

$failures = New-Object System.Collections.Generic.List[string]
if ($RequirePreparedRun -and -not $prepareFound) { $failures.Add("prepare_marker.json is missing for the expected prepared run.") | Out-Null }
if ($null -eq $latestManifestFile) { $failures.Add("No session_manifest_*.json exists for the current run.") | Out-Null }
if ($manifestCommit -ne "not found" -and $installedCommit -ne "missing" -and $manifestCommit -ne $installedCommit) { $failures.Add("Latest manifest commit '$manifestCommit' does not match installed build_info commit '$installedCommit'.") | Out-Null }
if ($manifestProbeSet -ne "not found" -and $manifestProbeSet -ne $installedProbeSet) { $failures.Add("Latest manifest probeSet '$manifestProbeSet' does not match installed config probeSet '$installedProbeSet'.") | Out-Null }
if ($manifestTickDriver -ne "not found" -and $manifestTickDriver -ne $installedTickDriver) { $failures.Add("Latest manifest tickDriver '$manifestTickDriver' does not match installed config tickDriver '$installedTickDriver'.") | Out-Null }
if (-not [string]::IsNullOrWhiteSpace($expectedCommit) -and $expectedCommit -ne "missing" -and $installedCommit -ne $expectedCommit) { $failures.Add("Installed commit '$installedCommit' does not match prepared expected commit '$expectedCommit'.") | Out-Null }
if (-not [string]::IsNullOrWhiteSpace($expectedProbeSetFromMarker) -and $manifestProbeSet -ne "not found" -and $manifestProbeSet -ne $expectedProbeSetFromMarker) { $failures.Add("Expected probeSet '$expectedProbeSetFromMarker' but latest manifest says '$manifestProbeSet'.") | Out-Null }
if (-not [string]::IsNullOrWhiteSpace($expectedTickDriverFromMarker) -and $manifestTickDriver -ne "not found" -and $manifestTickDriver -ne $expectedTickDriverFromMarker) { $failures.Add("Expected tickDriver '$expectedTickDriverFromMarker' but latest manifest says '$manifestTickDriver'.") | Out-Null }
if (-not [string]::IsNullOrWhiteSpace($expectedModeFromMarker) -and $installedMode -ne $expectedModeFromMarker) { $failures.Add("Expected installed mode '$expectedModeFromMarker' but config says '$installedMode'.") | Out-Null }
if ($ExpectedProbeSet -eq "health-playerstate-read" -and $manifestProbeSet -eq "health-baseline-read") { $failures.Add("Stale baseline artifact: expected health-playerstate-read but latest manifest says health-baseline-read.") | Out-Null }
if ($manifestSessionId -ne "not found" -and -not $logContainsSession) { $failures.Add("UE4SS.log does not contain latest sessionId '$manifestSessionId'.") | Out-Null }
if ($installedCommit -ne "missing" -and -not $logContainsCommit) { $failures.Add("UE4SS.log does not contain installed git commit '$installedCommit'.") | Out-Null }
if ($artifactOlderThanPrepare) { $failures.Add("Latest evidence appears older than prepare_marker.json preparedAt.") | Out-Null }
if (-not $evidenceMatchesInstalledConfigProbeSet) { $failures.Add("Latest evidence files do not match installed config/probeSet/session.") | Out-Null }

Write-Host "CrabRuntimeProbe crash/stale bundle validation"
Write-Host "game_bin_path = $GameBinFull"
Write-Host "installed_git_commit = $installedCommit"
Write-Host "installed_probeSet = $installedProbeSet"
Write-Host "installed_tickDriver = $installedTickDriver"
Write-Host "installed_mode = $installedMode"
Write-Host "prepare_marker_found = $prepareFound"
Write-Host "expected_git_commit = $expectedCommit"
Write-Host "expected_probeSet = $expectedProbeSetFromMarker"
Write-Host "expected_tickDriver = $expectedTickDriverFromMarker"
Write-Host "expected_mode = $expectedModeFromMarker"
Write-Host "latest_session_manifest = $(if ($null -ne $latestManifestFile) { $latestManifestFile.FullName } else { "not found" })"
Write-Host "latest_session_manifest_sessionId = $manifestSessionId"
Write-Host "latest_manifest_git_commit = $manifestCommit"
Write-Host "latest_manifest_probeSet = $manifestProbeSet"
Write-Host "latest_manifest_tickDriver = $manifestTickDriver"
Write-Host "latest_probe_results_file = $(if ($null -ne $latestProbeFile) { $latestProbeFile.FullName } else { "not found" })"
Write-Host "latest_access_evidence_file = $(if ($null -ne $latestEvidenceFile) { $latestEvidenceFile.FullName } else { "not found" })"
Write-Host "ue4ss_log_contains_latest_sessionId = $logContainsSession"
Write-Host "ue4ss_log_contains_installed_git_commit = $logContainsCommit"
Write-Host "evidence_probeSet_matches_installed_config = $evidenceProbeSetMatch"
Write-Host "evidence_tickDriver_matches_installed_config = $evidenceTickDriverMatch"
Write-Host "evidence_session_matches_manifest = $evidenceSessionMatch"
Write-Host "evidence_files_match_installed_config_probeSet = $evidenceMatchesInstalledConfigProbeSet"
Write-Host "latest_evidence_older_than_prepare = $artifactOlderThanPrepare"
Write-Host "latest_crash_folder = $(if ($null -ne $latestCrashFolder) { $latestCrashFolder.FullName } else { "not found" })"
Write-Host ""
Write-Host "files_to_upload:"
Write-Host " - $(Join-Path $ScriptsRoot "diagnostic_summary.txt")"
Write-Host " - $(if ($null -ne $latestManifestFile) { $latestManifestFile.FullName } else { "latest session_manifest_*.json not found" })"
Write-Host " - $(if ($null -ne $latestProbeFile) { $latestProbeFile.FullName } else { "latest probe_results_*.jsonl not found" })"
Write-Host " - $(if ($null -ne $latestEvidenceFile) { $latestEvidenceFile.FullName } else { "latest access_evidence_*.jsonl not found" })"
Write-Host " - $Ue4ssLogPath"
Write-Host " - crash files only if a crash happened"
Write-Host ""
Write-Host "failures:"
if ($failures.Count -eq 0) {
  Write-Host " - none"
  exit 0
}

foreach ($failure in $failures) {
  Write-Host " - $failure"
}
exit 1
