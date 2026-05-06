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
  if ($PhaseId -eq "multiplayer-resource-visibility-read") {
    & $cycle -GameBin $GameBinFull -CollectResourceVisibility
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "crystals-read") {
    & $cycle -GameBin $GameBinFull -CollectCrystalsRead
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "slots-read") {
    & $cycle -GameBin $GameBinFull -CollectSlotsRead
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "safe-scalar-watch") {
    & $cycle -GameBin $GameBinFull -CollectSafeScalarWatch
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "perk-da-catalog-read") {
    & $cycle -GameBin $GameBinFull -CollectPerkDataAssetCatalog
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "local-inventory-array-shallow-read") {
    & $cycle -GameBin $GameBinFull -CollectLocalInventoryArrayShallow
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "local-inventory-array-shape-confirm") {
    & $cycle -GameBin $GameBinFull -CollectLocalInventoryArrayShapeConfirm
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "local-inventory-userdata-introspection") {
    & $cycle -GameBin $GameBinFull -CollectLocalInventoryUserdataIntrospection
    return $LASTEXITCODE
  }
  if ($PhaseId -eq "inventory-array-count-read") {
    & $cycle -GameBin $GameBinFull -CollectInventoryArrayCountRead
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

if ($collectExit -eq 0 -and $validatorExit -eq 0 -and $null -ne $latestManifestFile -and $null -ne $latestProbeFile -and -not $crashAfterPrepare) {
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

if ($status -eq "passed" -and $phase.phaseId -eq "multiplayer-resource-visibility-read") {
  $rows = Read-JsonLines -Paths @(
    $(if ($null -ne $latestProbeFile) { $latestProbeFile.FullName } else { "" }),
    $(if ($null -ne $latestAccessFile) { $latestAccessFile.FullName } else { "" })
  )
  $resourceRows = @($rows | Where-Object {
    $name = ""
    foreach ($field in @("probeName", "probeId", "event")) {
      if ($_.PSObject.Properties.Name -contains $field) {
        $name = [string]$_.$field
        if (-not [string]::IsNullOrWhiteSpace($name)) { break }
      }
    }
    $name -match "^ResourceVisibility\."
  })
  $sampled = 0
  $readableCrystals = 0
  $readableSlots = 0
  $readableEquipment = 0
  $readableInventoryArrays = 0
  $fieldsVisibleAcrossMultiple = 0
  $rawIdentityLeak = $false
  foreach ($row in $resourceRows) {
    $n = 0
    if ([int]::TryParse([string]$row.sampledPlayerStateCount, [ref]$n) -and $n -gt $sampled) { $sampled = $n }
    if ([int]::TryParse([string]$row.readableCrystalsCount, [ref]$n) -and $n -gt $readableCrystals) { $readableCrystals = $n }
    if ([int]::TryParse([string]$row.readableSlotsCount, [ref]$n) -and $n -gt $readableSlots) { $readableSlots = $n }
    if ([int]::TryParse([string]$row.readableEquipmentCount, [ref]$n) -and $n -gt $readableEquipment) { $readableEquipment = $n }
    if ([int]::TryParse([string]$row.readableInventoryArrayCount, [ref]$n) -and $n -gt $readableInventoryArrays) { $readableInventoryArrays = $n }
    if (($row.PSObject.Properties.Name -contains "fieldsVisibleAcrossMultiple") -and $null -ne $row.fieldsVisibleAcrossMultiple) {
      $fieldsVisibleAcrossMultiple = @($row.fieldsVisibleAcrossMultiple).Count
    }
    if (($row.PSObject.Properties.Name -contains "rawIdentityEvidence") -and $row.rawIdentityEvidence -eq $true) {
      $rawIdentityLeak = $true
    }
  }
  $anyResource = ($readableCrystals -gt 0 -or $readableSlots -gt 0 -or $readableEquipment -gt 0 -or $readableInventoryArrays -gt 0)
  if ($resourceRows.Count -eq 0) {
    $status = "no_evidence"
    $reason = "No multiplayer resource visibility probe evidence was found."
  } elseif ($rawIdentityLeak) {
    $status = "failed"
    $reason = "Raw identity evidence appeared during resource visibility even though allowRawIdentityEvidence should be false."
  } elseif ($sampled -lt 2 -and -not $anyResource) {
    $status = "needs_multiplayer"
    $reason = "Only one or zero PlayerState candidates were sampled; run with at least two visible players."
  } elseif ($sampled -lt 2) {
    $status = "local_only_evidence"
    $reason = "Only one PlayerState candidate was sampled, so resource visibility is local-only evidence."
  } elseif ($readableCrystals -gt 1 -and $readableSlots -gt 1 -and $readableEquipment -gt 1 -and $readableInventoryArrays -gt 1) {
    $status = "passed"
  } elseif ($readableCrystals -gt 1 -or $readableSlots -gt 1 -or $readableEquipment -gt 1 -or $readableInventoryArrays -gt 1 -or $fieldsVisibleAcrossMultiple -gt 0) {
    $status = "remote_resources_partial"
    $reason = "Multiple PlayerState candidates were sampled and some resource fields were visible remotely, but visibility was partial."
  } else {
    $status = "remote_resources_unresolved"
    $reason = "Multiple PlayerState candidates were sampled, but resource fields did not establish remote visibility."
  }
}

if (($status -eq "passed" -or $status -eq "crashed") -and $phase.phaseId -eq "local-inventory-array-shallow-read") {
  $rows = Read-JsonLines -Paths @(
    $(if ($null -ne $latestProbeFile) { $latestProbeFile.FullName } else { "" }),
    $(if ($null -ne $latestAccessFile) { $latestAccessFile.FullName } else { "" })
  )
  $inventoryRows = @($rows | Where-Object {
    $name = ""
    foreach ($field in @("probeName", "probeId", "event")) {
      if ($_.PSObject.Properties.Name -contains $field) {
        $name = [string]$_.$field
        if (-not [string]::IsNullOrWhiteSpace($name)) { break }
      }
    }
    $name -match "^Inventory\.Local(Arrays|Slots)\."
  })

  $hasCountOrShape = $false
  $safetyViolation = $false
  foreach ($row in $inventoryRows) {
    if (($row.PSObject.Properties.Name -contains "noElementDereference") -and $row.noElementDereference -eq $false) {
      $safetyViolation = $true
    }
    if (($row.PSObject.Properties.Name -contains "safetyGates") -and $null -ne $row.safetyGates) {
      foreach ($gate in @("allowDeepArrayProbes", "allowInventoryInfoProbes", "allowWriteProbes", "allowRpcProbes", "allowHudTickHook", "allowRawIdentityEvidence")) {
        if (($row.safetyGates.PSObject.Properties.Name -contains $gate) -and $row.safetyGates.$gate -eq $true) {
          $safetyViolation = $true
        }
      }
    }
    if (($row.PSObject.Properties.Name -contains "fieldsReadable") -and @($row.fieldsReadable).Count -gt 0) {
      $hasCountOrShape = $true
    }
    if (($row.PSObject.Properties.Name -contains "arrayCounts") -and $null -ne $row.arrayCounts) {
      foreach ($property in $row.arrayCounts.PSObject.Properties) {
        $n = 0
        if ([int]::TryParse([string]$property.Value, [ref]$n)) { $hasCountOrShape = $true }
      }
    }
    if (($row.PSObject.Properties.Name -contains "arrayValueKinds") -and $null -ne $row.arrayValueKinds) {
      foreach ($property in $row.arrayValueKinds.PSObject.Properties) {
        if ($property.Value -eq "table" -or $property.Value -eq "userdata") { $hasCountOrShape = $true }
      }
    }
  }

  if ($inventoryRows.Count -eq 0) {
    $status = "no_evidence"
    $reason = "No local inventory array shallow probe evidence was found."
  } elseif ($safetyViolation) {
    $status = "failed"
    $reason = "Local inventory array shallow evidence violated safety gates or dereferenced an array element."
  } elseif ($hasCountOrShape) {
    if ($crashAfterPrepare) {
      $status = "crash_suspect_local_inventory_shape_visible"
      $reason = "Local inventory array fields were visible as shallow userdata shapes, but a crash dump/folder was updated after campaign prepare/run."
    } else {
      $status = "passed"
    }
  } else {
    $status = "local_inventory_unresolved"
    $reason = "Local inventory array fields were nil or unsupported in shallow reads."
  }
}

if (($status -eq "passed" -or $status -eq "crashed") -and $phase.phaseId -eq "local-inventory-array-shape-confirm") {
  $rows = Read-JsonLines -Paths @(
    $(if ($null -ne $latestProbeFile) { $latestProbeFile.FullName } else { "" }),
    $(if ($null -ne $latestAccessFile) { $latestAccessFile.FullName } else { "" })
  )
  $confirmRows = @($rows | Where-Object {
    $name = ""
    foreach ($field in @("probeName", "probeId", "event")) {
      if ($_.PSObject.Properties.Name -contains $field) {
        $name = [string]$_.$field
        if (-not [string]::IsNullOrWhiteSpace($name)) { break }
      }
    }
    $name -eq "Inventory.LocalArrays.ShapeConfirm"
  })

  $hasShapeEvidence = $false
  $safetyViolation = $false
  foreach ($row in $confirmRows) {
    foreach ($flag in @("noElementDereference", "noArrayCount", "noArrayTraversal", "noInventoryInfo", "noEnhancements")) {
      if (-not ($row.PSObject.Properties.Name -contains $flag) -or $row.$flag -ne $true) {
        $safetyViolation = $true
      }
    }
    if (($row.PSObject.Properties.Name -contains "safetyGates") -and $null -ne $row.safetyGates) {
      foreach ($gate in @("allowInventoryArrayShallowProbes", "allowInventoryUserdataIntrospectionProbes", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowWriteProbes", "allowRpcProbes", "allowHudTickHook", "allowRawIdentityEvidence", "allowHealthProbes", "allowIdentityProbes", "allowResourceVisibilityProbes", "allowCrystalsReadProbes", "allowSlotsReadProbes", "allowUnknownRoleProbes", "allowJoinedClientDeepProbes")) {
        if (($row.safetyGates.PSObject.Properties.Name -contains $gate) -and $row.safetyGates.$gate -eq $true) {
          $safetyViolation = $true
        }
      }
    }
    if (($row.PSObject.Properties.Name -contains "localPlayerStatePresent") -and $row.localPlayerStatePresent -eq $true) {
      $hasShapeEvidence = $true
    }
    if (($row.PSObject.Properties.Name -contains "fieldsReadable") -and @($row.fieldsReadable).Count -gt 0) {
      $hasShapeEvidence = $true
    }
    if (($row.PSObject.Properties.Name -contains "arrayValueKinds") -and $null -ne $row.arrayValueKinds) {
      foreach ($property in $row.arrayValueKinds.PSObject.Properties) {
        if ($property.Value -in @("nil", "userdata", "table", "other")) { $hasShapeEvidence = $true }
      }
    }
    if (($row.PSObject.Properties.Name -contains "arrayPropertiesPresent") -and $null -ne $row.arrayPropertiesPresent) {
      $hasShapeEvidence = $true
    }
  }

  if ($confirmRows.Count -eq 0) {
    $status = "no_evidence"
    $reason = "No local inventory array shape-confirm probe evidence was found."
  } elseif ($safetyViolation) {
    $status = "failed"
    $reason = "Local inventory array shape-confirm evidence violated safety gates or attempted count, traversal, element dereference, InventoryInfo, or Enhancements."
  } elseif ($hasShapeEvidence) {
    if ($crashAfterPrepare) {
      $status = "crash_suspect_local_inventory_shape_confirmed"
      $reason = "Local inventory array fields were confirmed as property shapes with no count/traversal/element dereference, but a crash dump/folder was updated after campaign prepare/run."
    } else {
      $status = "local_inventory_shape_confirmed"
    }
  } else {
    $status = "no_evidence"
    $reason = "Shape-confirm probes ran but did not produce local inventory shape evidence."
  }
}

if (($status -eq "passed" -or $status -eq "crashed") -and $phase.phaseId -eq "local-inventory-userdata-introspection") {
  $rows = Read-JsonLines -Paths @(
    $(if ($null -ne $latestProbeFile) { $latestProbeFile.FullName } else { "" }),
    $(if ($null -ne $latestAccessFile) { $latestAccessFile.FullName } else { "" })
  )
  $introspectionRows = @($rows | Where-Object {
    $name = ""
    foreach ($field in @("probeName", "probeId", "event")) {
      if ($_.PSObject.Properties.Name -contains $field) {
        $name = [string]$_.$field
        if (-not [string]::IsNullOrWhiteSpace($name)) { break }
      }
    }
    $name -eq "Inventory.LocalArrays.UserdataIntrospection"
  })

  $hasMetadataEvidence = $false
  $safetyViolation = $false
  foreach ($row in $introspectionRows) {
    foreach ($flag in @("noElementDereference", "noArrayTraversal", "noInventoryInfo", "noEnhancements", "noWrites", "noRpcs", "noHud", "noDeepArrays")) {
      if (-not ($row.PSObject.Properties.Name -contains $flag) -or $row.$flag -ne $true) {
        $safetyViolation = $true
      }
    }
    if (($row.PSObject.Properties.Name -contains "safetyGates") -and $null -ne $row.safetyGates) {
      foreach ($gate in @("allowInventoryArrayShapeConfirmProbes", "allowInventoryArrayShallowProbes", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowWriteProbes", "allowRpcProbes", "allowHudTickHook", "allowRawIdentityEvidence", "allowHealthProbes", "allowIdentityProbes", "allowResourceVisibilityProbes", "allowCrystalsReadProbes", "allowSlotsReadProbes", "allowUnknownRoleProbes", "allowJoinedClientDeepProbes")) {
        if (($row.safetyGates.PSObject.Properties.Name -contains $gate) -and $row.safetyGates.$gate -eq $true) {
          $safetyViolation = $true
        }
      }
    }
    foreach ($field in @("valueKinds", "tostringKinds", "metatableKinds", "lenOperatorAttempted")) {
      if (($row.PSObject.Properties.Name -contains $field) -and $null -ne $row.$field) {
        $hasMetadataEvidence = $true
      }
    }
    if (($row.PSObject.Properties.Name -contains "localPlayerStatePresent") -and $row.localPlayerStatePresent -eq $true) {
      $hasMetadataEvidence = $true
    }
  }

  if ($introspectionRows.Count -eq 0) {
    $status = "no_evidence"
    $reason = "No local inventory userdata introspection probe evidence was found."
  } elseif ($safetyViolation) {
    $status = "failed"
    $reason = "Local inventory userdata introspection evidence violated safety gates or attempted traversal, element dereference, InventoryInfo, Enhancements, writes, or RPCs."
  } elseif ($hasMetadataEvidence) {
    if ($crashAfterPrepare) {
      $status = "crash_suspect_local_inventory_userdata_introspection"
      $reason = "Local inventory userdata wrapper metadata was collected without traversal or element dereference, but a crash dump/folder was updated after campaign prepare/run."
    } else {
      $status = "local_inventory_userdata_introspection_confirmed"
    }
  } else {
    $status = "no_evidence"
    $reason = "Userdata introspection probes ran but did not produce local inventory wrapper metadata."
  }
}

if (($status -eq "passed" -or $status -eq "crashed") -and $phase.phaseId -eq "inventory-array-count-read") {
  $rows = Read-JsonLines -Paths @(
    $(if ($null -ne $latestProbeFile) { $latestProbeFile.FullName } else { "" }),
    $(if ($null -ne $latestAccessFile) { $latestAccessFile.FullName } else { "" })
  )
  $countRows = @($rows | Where-Object {
    $name = ""
    foreach ($field in @("probeName", "probeId", "event")) {
      if ($_.PSObject.Properties.Name -contains $field) {
        $name = [string]$_.$field
        if (-not [string]::IsNullOrWhiteSpace($name)) { break }
      }
    }
    $name -eq "Inventory.LocalArrays.CountRead"
  })

  $localPlayerStatePresent = $false
  $propertyClassifiedCount = 0
  $countResultCount = 0
  $safetyViolation = $false
  foreach ($row in $countRows) {
    if (($row.PSObject.Properties.Name -contains "localPlayerStatePresent") -and $row.localPlayerStatePresent -eq $true) {
      $localPlayerStatePresent = $true
    }
    if (($row.PSObject.Properties.Name -contains "fieldResults") -and $null -ne $row.fieldResults) {
      $propertyClassifiedCount = [Math]::Max($propertyClassifiedCount, @($row.fieldResults.PSObject.Properties).Count)
    }
    if (($row.PSObject.Properties.Name -contains "countResults") -and $null -ne $row.countResults) {
      $countResultCount = [Math]::Max($countResultCount, @($row.countResults.PSObject.Properties).Count)
    }
    foreach ($flag in @("noWrites", "noRpcs", "noHud", "noDeepArrays", "noInventoryTraversal", "noArrayTraversal", "noElementDereference", "noItemDataAssetRead", "noInventoryInfo", "noEnhancements", "noDataAssetMutation", "passiveOnly")) {
      if (-not ($row.PSObject.Properties.Name -contains $flag) -or $row.$flag -ne $true) {
        $safetyViolation = $true
      }
    }
    if (($row.PSObject.Properties.Name -contains "safetyGates") -and $null -ne $row.safetyGates) {
      foreach ($gate in @("allowInventoryArrayShapeConfirmProbes", "allowInventoryArrayShallowProbes", "allowInventoryUserdataIntrospectionProbes", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowWriteProbes", "allowRpcProbes", "allowHudTickHook", "allowRawIdentityEvidence", "allowHealthProbes", "allowIdentityProbes", "allowResourceVisibilityProbes", "allowCrystalsReadProbes", "allowSlotsReadProbes", "allowSafeScalarWatchProbes", "allowPerkDataAssetCatalogProbes", "allowMaxSafePlayRecorderProbes", "allowUnknownRoleProbes", "allowJoinedClientDeepProbes")) {
        if (($row.safetyGates.PSObject.Properties.Name -contains $gate) -and $row.safetyGates.$gate -eq $true) {
          $safetyViolation = $true
        }
      }
    }
  }

  if ($countRows.Count -eq 0) {
    $status = "no_evidence"
    $reason = "No inventory array count-read probe evidence was found."
  } elseif ($safetyViolation) {
    $status = "failed"
    $reason = "Inventory array count-read evidence violated safety gates or touched traversal, elements, item DataAssets, InventoryInfo, Enhancements, writes, RPCs, HUD, or deep arrays."
  } elseif ($crashAfterPrepare) {
    $status = "crash_suspect_inventory_array_count"
    $reason = "Inventory array count metadata was attempted read-only, but a crash dump/folder was updated after campaign prepare/run."
  } elseif (-not $localPlayerStatePresent -or $propertyClassifiedCount -eq 0) {
    $status = "inventory_array_count_not_found"
    $reason = "Inventory array count-read ran but did not find local PlayerState inventory array properties."
  } elseif ($propertyClassifiedCount -ge 5 -and $countResultCount -gt 0) {
    $status = "inventory_array_count_confirmed"
  } elseif ($propertyClassifiedCount -ge 5) {
    $status = "inventory_array_count_unsupported"
    $reason = "Inventory array properties were visible, but count metadata was unsupported for all arrays."
  } else {
    $status = "inventory_array_count_not_found"
    $reason = "Inventory array count-read did not classify all expected local inventory array properties."
  }
}

if (($status -eq "passed" -or $status -eq "crashed") -and $phase.phaseId -eq "crystals-read") {
  $rows = Read-JsonLines -Paths @(
    $(if ($null -ne $latestProbeFile) { $latestProbeFile.FullName } else { "" }),
    $(if ($null -ne $latestAccessFile) { $latestAccessFile.FullName } else { "" })
  )
  $crystalRows = @($rows | Where-Object {
    $name = ""
    foreach ($field in @("probeName", "probeId", "event")) {
      if ($_.PSObject.Properties.Name -contains $field) {
        $name = [string]$_.$field
        if (-not [string]::IsNullOrWhiteSpace($name)) { break }
      }
    }
    $name -eq "Resource.Crystals.Read"
  })

  $localPlayerStatePresent = $false
  $crystalsReadAttempted = $false
  $valueIntegerLike = $true
  $safetyViolation = $false
  foreach ($row in $crystalRows) {
    if (($row.PSObject.Properties.Name -contains "localPlayerStatePresent") -and $row.localPlayerStatePresent -eq $true) {
      $localPlayerStatePresent = $true
    }
    if (($row.PSObject.Properties.Name -contains "crystalsReadAttempted") -and $row.crystalsReadAttempted -eq $true) {
      $crystalsReadAttempted = $true
    }
    if (($row.PSObject.Properties.Name -contains "crystalsPresent") -and $row.crystalsPresent -eq $true) {
      if (-not (($row.PSObject.Properties.Name -contains "crystalsIntegerLike") -and $row.crystalsIntegerLike -eq $true)) {
        $valueIntegerLike = $false
      }
    }
    foreach ($flag in @("noElementDereference", "noArrayTraversal", "noInventoryInfo", "noEnhancements", "noWrites", "noRpcs", "noHud", "noDeepArrays")) {
      if (-not ($row.PSObject.Properties.Name -contains $flag) -or $row.$flag -ne $true) {
        $safetyViolation = $true
      }
    }
    if (($row.PSObject.Properties.Name -contains "safetyGates") -and $null -ne $row.safetyGates) {
      foreach ($gate in @("allowHudTickHook", "allowUnknownRoleProbes", "allowJoinedClientDeepProbes", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowHealthProbes", "allowIdentityProbes", "allowRawIdentityEvidence", "allowResourceVisibilityProbes", "allowSlotsReadProbes", "allowInventoryArrayShallowProbes", "allowInventoryArrayShapeConfirmProbes", "allowInventoryUserdataIntrospectionProbes", "allowWriteProbes", "allowRpcProbes")) {
        if (($row.safetyGates.PSObject.Properties.Name -contains $gate) -and $row.safetyGates.$gate -eq $true) {
          $safetyViolation = $true
        }
      }
    }
  }

  if ($crystalRows.Count -eq 0) {
    $status = "no_evidence"
    $reason = "No local PlayerState Crystals read probe evidence was found."
  } elseif ($safetyViolation) {
    $status = "failed"
    $reason = "Crystals read evidence violated safety gates or touched HUD, writes, RPCs, deep arrays, inventory arrays, InventoryInfo, or Enhancements."
  } elseif (-not $localPlayerStatePresent) {
    $status = "no_evidence"
    $reason = "Crystals read ran but did not confirm local PlayerState present."
  } elseif (-not $crystalsReadAttempted) {
    $status = "no_evidence"
    $reason = "Crystals read ran but did not attempt the Crystals scalar read."
  } elseif (-not $valueIntegerLike) {
    $status = "failed"
    $reason = "Crystals read value was not finite/integer-like when present."
  } elseif ($crashAfterPrepare) {
    $status = "crash_suspect_crystals_read"
    $reason = "Local PlayerState Crystals scalar was read without forbidden probes, but a crash dump/folder was updated after campaign prepare/run."
  } else {
    $status = "crystals_read_confirmed"
  }
}

if (($status -eq "passed" -or $status -eq "crashed") -and $phase.phaseId -eq "slots-read") {
  $rows = Read-JsonLines -Paths @(
    $(if ($null -ne $latestProbeFile) { $latestProbeFile.FullName } else { "" }),
    $(if ($null -ne $latestAccessFile) { $latestAccessFile.FullName } else { "" })
  )
  $slotRows = @($rows | Where-Object {
    $name = ""
    foreach ($field in @("probeName", "probeId", "event")) {
      if ($_.PSObject.Properties.Name -contains $field) {
        $name = [string]$_.$field
        if (-not [string]::IsNullOrWhiteSpace($name)) { break }
      }
    }
    $name -eq "Resource.Slots.Read"
  })

  $localPlayerStatePresent = $false
  $slotsReadAttempted = $false
  $valuesIntegerLike = $true
  $valuesInByteRange = $true
  $safetyViolation = $false
  foreach ($row in $slotRows) {
    if (($row.PSObject.Properties.Name -contains "localPlayerStatePresent") -and $row.localPlayerStatePresent -eq $true) {
      $localPlayerStatePresent = $true
    }
    if (($row.PSObject.Properties.Name -contains "slotsReadAttempted") -and $row.slotsReadAttempted -eq $true) {
      $slotsReadAttempted = $true
    }
    if (($row.PSObject.Properties.Name -contains "slotIntegerLike") -and $null -ne $row.slotIntegerLike) {
      foreach ($property in $row.slotIntegerLike.PSObject.Properties) {
        if ($property.Value -ne $true) { $valuesIntegerLike = $false }
      }
    }
    if (($row.PSObject.Properties.Name -contains "slotValuesInByteRange") -and $null -ne $row.slotValuesInByteRange) {
      foreach ($property in $row.slotValuesInByteRange.PSObject.Properties) {
        if ($property.Value -ne $true) { $valuesInByteRange = $false }
      }
    }
    foreach ($flag in @("noElementDereference", "noArrayCount", "noArrayTraversal", "noInventoryInfo", "noEnhancements", "noWrites", "noRpcs", "noHud", "noDeepArrays")) {
      if (-not ($row.PSObject.Properties.Name -contains $flag) -or $row.$flag -ne $true) {
        $safetyViolation = $true
      }
    }
    if (($row.PSObject.Properties.Name -contains "safetyGates") -and $null -ne $row.safetyGates) {
      foreach ($gate in @("allowHudTickHook", "allowUnknownRoleProbes", "allowJoinedClientDeepProbes", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowHealthProbes", "allowIdentityProbes", "allowRawIdentityEvidence", "allowResourceVisibilityProbes", "allowCrystalsReadProbes", "allowInventoryArrayShallowProbes", "allowInventoryArrayShapeConfirmProbes", "allowInventoryUserdataIntrospectionProbes", "allowWriteProbes", "allowRpcProbes")) {
        if (($row.safetyGates.PSObject.Properties.Name -contains $gate) -and $row.safetyGates.$gate -eq $true) {
          $safetyViolation = $true
        }
      }
    }
  }

  if ($slotRows.Count -eq 0) {
    $status = "no_evidence"
    $reason = "No local PlayerState slots read probe evidence was found."
  } elseif ($safetyViolation) {
    $status = "failed"
    $reason = "Slots read evidence violated safety gates or touched HUD, writes, RPCs, deep arrays, inventory arrays, InventoryInfo, or Enhancements."
  } elseif (-not $localPlayerStatePresent) {
    $status = "no_evidence"
    $reason = "Slots read ran but did not confirm local PlayerState present."
  } elseif (-not $slotsReadAttempted) {
    $status = "no_evidence"
    $reason = "Slots read ran but did not attempt the slot scalar reads."
  } elseif (-not $valuesIntegerLike) {
    $status = "failed"
    $reason = "A present slot scalar was not finite/integer-like."
  } elseif (-not $valuesInByteRange) {
    $status = "failed"
    $reason = "A present slot scalar was outside the documented ByteProperty range 0..255."
  } elseif ($crashAfterPrepare) {
    $status = "crash_suspect_slots_read"
    $reason = "Local PlayerState slot scalars were read without forbidden probes, but a crash dump/folder was updated after campaign prepare/run."
  } else {
    $status = "slots_read_confirmed"
  }
}

if (($status -eq "passed" -or $status -eq "crashed") -and $phase.phaseId -eq "safe-scalar-watch") {
  $rows = Read-JsonLines -Paths @(
    $(if ($null -ne $latestProbeFile) { $latestProbeFile.FullName } else { "" }),
    $(if ($null -ne $latestAccessFile) { $latestAccessFile.FullName } else { "" })
  )
  $watchRows = @($rows | Where-Object {
    $name = ""
    foreach ($field in @("probeName", "probeId", "event")) {
      if ($_.PSObject.Properties.Name -contains $field) {
        $name = [string]$_.$field
        if (-not [string]::IsNullOrWhiteSpace($name)) { break }
      }
    }
    $name -eq "SafeWatch.Scalar.Sample" -or $name -eq "Runtime.SafeScalarWatch.Sample"
  })

  $usableSamples = 0
  $sampleCount = 0
  $changedFields = 0
  $safetyViolation = $false
  foreach ($row in $watchRows) {
    if (($row.PSObject.Properties.Name -contains "playerStatePresent") -and $row.playerStatePresent -eq $true) {
      $usableSamples += 1
    }
    if (($row.PSObject.Properties.Name -contains "safeWatchSampleCount")) {
      $n = 0
      if ([int]::TryParse([string]$row.safeWatchSampleCount, [ref]$n) -and $n -gt $sampleCount) { $sampleCount = $n }
    }
    if (($row.PSObject.Properties.Name -contains "safeWatchChangedFields") -and $null -ne $row.safeWatchChangedFields) {
      $changedFields = [Math]::Max($changedFields, @($row.safeWatchChangedFields | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count)
    }
    foreach ($flag in @("noElementDereference", "noArrayCount", "noArrayTraversal", "noInventoryInfo", "noEnhancements", "noWrites", "noRpcs", "noHud", "noDeepArrays")) {
      if (-not ($row.PSObject.Properties.Name -contains $flag) -or $row.$flag -ne $true) {
        $safetyViolation = $true
      }
    }
    if (($row.PSObject.Properties.Name -contains "safetyGates") -and $null -ne $row.safetyGates) {
      foreach ($gate in @("allowHudTickHook", "allowUnknownRoleProbes", "allowJoinedClientDeepProbes", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowHealthProbes", "allowIdentityProbes", "allowRawIdentityEvidence", "allowResourceVisibilityProbes", "allowCrystalsReadProbes", "allowSlotsReadProbes", "allowInventoryArrayShallowProbes", "allowInventoryArrayShapeConfirmProbes", "allowInventoryUserdataIntrospectionProbes", "allowWriteProbes", "allowRpcProbes")) {
        if (($row.safetyGates.PSObject.Properties.Name -contains $gate) -and $row.safetyGates.$gate -eq $true) {
          $safetyViolation = $true
        }
      }
    }
  }

  if ($watchRows.Count -eq 0) {
    $status = "no_evidence"
    $reason = "No safe scalar watch evidence was found."
  } elseif ($safetyViolation) {
    $status = "failed"
    $reason = "Safe scalar watch evidence violated safety gates or touched arrays, InventoryInfo, Enhancements, writes, RPCs, HUD, or deep arrays."
  } elseif ($usableSamples -eq 0) {
    $status = "no_evidence"
    $reason = "Safe scalar watch ran but did not collect any usable PlayerState-present samples."
  } elseif ($crashAfterPrepare) {
    $status = "crash_suspect_safe_scalar_watch"
    $reason = "Safe scalar watch collected proven-safe scalar values, but a crash dump/folder was updated after campaign prepare/run."
  } elseif ($changedFields -gt 0) {
    $status = "safe_scalar_watch_observed_change"
  } elseif ($sampleCount -gt 1) {
    $status = "safe_scalar_watch_confirmed_no_change"
  } else {
    $status = "no_evidence"
    $reason = "Safe scalar watch needs multiple samples or a changed-value row to classify."
  }
}

if (($status -eq "passed" -or $status -eq "crashed") -and $phase.phaseId -eq "perk-da-catalog-read") {
  $rows = Read-JsonLines -Paths @(
    $(if ($null -ne $latestProbeFile) { $latestProbeFile.FullName } else { "" }),
    $(if ($null -ne $latestAccessFile) { $latestAccessFile.FullName } else { "" })
  )
  $catalogRows = @($rows | Where-Object {
    $name = ""
    foreach ($field in @("probeName", "probeId", "event")) {
      if ($_.PSObject.Properties.Name -contains $field) {
        $name = [string]$_.$field
        if (-not [string]::IsNullOrWhiteSpace($name)) { break }
      }
    }
    $name -eq "DataAsset.Perks.CatalogRead"
  })

  $discoveryAttempted = $false
  $catalogFound = $false
  $catalogEntryCount = 0
  $catalogCandidateCount = 0
  $catalogRejectedCandidateCount = 0
  $safetyViolation = $false
  foreach ($row in $catalogRows) {
    if (($row.PSObject.Properties.Name -contains "discoveryAttempted") -and $row.discoveryAttempted -eq $true) {
      $discoveryAttempted = $true
    }
    if (($row.PSObject.Properties.Name -contains "catalogFound") -and $row.catalogFound -eq $true) {
      $catalogFound = $true
    }
    if (($row.PSObject.Properties.Name -contains "catalogEntryCount")) {
      $n = 0
      if ([int]::TryParse([string]$row.catalogEntryCount, [ref]$n) -and $n -gt $catalogEntryCount) { $catalogEntryCount = $n }
    }
    if (($row.PSObject.Properties.Name -contains "catalogCandidateCount")) {
      $n = 0
      if ([int]::TryParse([string]$row.catalogCandidateCount, [ref]$n) -and $n -gt $catalogCandidateCount) { $catalogCandidateCount = $n }
    }
    if (($row.PSObject.Properties.Name -contains "catalogRejectedCandidateCount")) {
      $n = 0
      if ([int]::TryParse([string]$row.catalogRejectedCandidateCount, [ref]$n) -and $n -gt $catalogRejectedCandidateCount) { $catalogRejectedCandidateCount = $n }
    }
    foreach ($flag in @("noWrites", "noRpcs", "noHud", "noDeepArrays", "noInventoryArrays", "noArrayCount", "noArrayTraversal", "noElementDereference", "noInventoryInfo", "noEnhancements", "noDataAssetMutation", "noFunctionCalls", "passiveOnly")) {
      if (-not ($row.PSObject.Properties.Name -contains $flag) -or $row.$flag -ne $true) {
        $safetyViolation = $true
      }
    }
    if (($row.PSObject.Properties.Name -contains "safetyGates") -and $null -ne $row.safetyGates) {
      if (-not ($row.safetyGates.PSObject.Properties.Name -contains "allowPerkDataAssetCatalogProbes") -or $row.safetyGates.allowPerkDataAssetCatalogProbes -ne $true) {
        $safetyViolation = $true
      }
      foreach ($gate in @("allowHudTickHook", "allowUnknownRoleProbes", "allowJoinedClientDeepProbes", "allowDeepArrayProbes", "allowInventoryInfoProbes", "allowHealthProbes", "allowIdentityProbes", "allowRawIdentityEvidence", "allowResourceVisibilityProbes", "allowCrystalsReadProbes", "allowSlotsReadProbes", "allowSafeScalarWatchProbes", "allowInventoryArrayShallowProbes", "allowInventoryArrayShapeConfirmProbes", "allowInventoryUserdataIntrospectionProbes", "allowWriteProbes", "allowRpcProbes")) {
        if (($row.safetyGates.PSObject.Properties.Name -contains $gate) -and $row.safetyGates.$gate -eq $true) {
          $safetyViolation = $true
        }
      }
    }
  }

  if ($catalogRows.Count -eq 0) {
    $status = "no_evidence"
    $reason = "No perk DataAsset catalog evidence was found."
  } elseif ($safetyViolation) {
    $status = "failed"
    $reason = "Perk DataAsset catalog evidence violated safety gates or touched writes, RPCs, HUD, deep arrays, inventory arrays, InventoryInfo, Enhancements, DataAsset mutation, or function calls."
  } elseif (-not $discoveryAttempted) {
    $status = "no_evidence"
    $reason = "Perk DataAsset catalog evidence did not attempt curated discovery."
  } elseif ($crashAfterPrepare) {
    $status = "perk_da_catalog_crash_suspect"
    $reason = "Perk DataAsset catalog discovery ran read-only, but a crash dump/folder was updated after campaign prepare/run."
  } elseif ($catalogFound -or $catalogEntryCount -gt 0) {
    $status = "perk_da_catalog_confirmed"
  } elseif ($catalogCandidateCount -gt 0 -and $catalogRejectedCandidateCount -gt 0) {
    $status = "perk_da_catalog_candidates_rejected"
    $reason = "Perk DataAsset catalog discovery ran safely, but candidates were rejected by capped class/name/identity filters."
  } else {
    $status = "perk_da_catalog_not_found"
    $reason = "Perk DataAsset catalog discovery ran safely but found no matching perk DataAssets."
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

if ($status -ne "passed" -and $status -ne "local_identity_confirmed" -and $status -ne "roster_source_unresolved" -and $status -ne "needs_multiplayer" -and $status -ne "local_only_evidence" -and $status -ne "remote_resources_unresolved" -and $status -ne "remote_resources_partial" -and $status -ne "local_inventory_unresolved" -and $status -ne "crash_suspect_local_inventory_shape_visible" -and $status -ne "local_inventory_shape_confirmed" -and $status -ne "crash_suspect_local_inventory_shape_confirmed" -and $status -ne "local_inventory_userdata_introspection_confirmed" -and $status -ne "crash_suspect_local_inventory_userdata_introspection" -and $status -ne "inventory_array_count_confirmed" -and $status -ne "inventory_array_count_unsupported" -and $status -ne "inventory_array_count_not_found" -and $status -ne "crash_suspect_inventory_array_count" -and $status -ne "crystals_read_confirmed" -and $status -ne "crash_suspect_crystals_read" -and $status -ne "slots_read_confirmed" -and $status -ne "crash_suspect_slots_read" -and $status -ne "safe_scalar_watch_confirmed_no_change" -and $status -ne "safe_scalar_watch_observed_change" -and $status -ne "crash_suspect_safe_scalar_watch" -and $status -ne "perk_da_catalog_confirmed" -and $status -ne "perk_da_catalog_not_found" -and $status -ne "perk_da_catalog_candidates_rejected" -and $status -ne "perk_da_catalog_crash_suspect" -and -not ($phase.phaseId -eq "local-inventory-array-shape-confirm" -and $status -eq "no_evidence") -and -not ($phase.phaseId -eq "local-inventory-userdata-introspection" -and $status -eq "no_evidence") -and -not ($phase.phaseId -eq "inventory-array-count-read" -and $status -eq "no_evidence") -and -not ($phase.phaseId -eq "crystals-read" -and $status -eq "no_evidence") -and -not ($phase.phaseId -eq "slots-read" -and $status -eq "no_evidence") -and -not ($phase.phaseId -eq "safe-scalar-watch" -and $status -eq "no_evidence") -and -not ($phase.phaseId -eq "perk-da-catalog-read" -and $status -eq "no_evidence")) {
  exit 1
}
