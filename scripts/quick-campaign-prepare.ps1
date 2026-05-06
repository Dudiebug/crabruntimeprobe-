[CmdletBinding()]
param(
  [string]$GameBin = "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

function Read-JsonFile {
  param([string]$Path)
  return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -ErrorAction Stop)
}

function Set-CrabRuntimeProbeCampaignConfigValue {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$Key,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $pattern = "^\s*$([regex]::Escape($Key))\s*="
  $found = $false
  $updated = foreach ($line in @(Get-Content -LiteralPath $ConfigPath)) {
    if ($line -match $pattern) {
      $found = $true
      "$Key = $Value"
    } else {
      $line
    }
  }
  if (-not $found) { throw "Cannot set missing config key '$Key' in $ConfigPath" }
  Set-Content -LiteralPath $ConfigPath -Value $updated -Encoding ASCII
}

function Get-CampaignPhaseIds {
  param([object[]]$Entries)
  return @($Entries | ForEach-Object {
    if ($_.PSObject.Properties.Name -contains "phaseId") { [string]$_.phaseId } else { [string]$_ }
  })
}

function Select-NextCampaignPhase {
  param(
    [Parameter(Mandatory = $true)][object]$Plan,
    [Parameter(Mandatory = $true)][object]$State
  )

  $completed = @(Get-CampaignPhaseIds -Entries @($State.completedPhases))
  $failed = @(Get-CampaignPhaseIds -Entries @($State.failedPhases))
  $blocked = @(Get-CampaignPhaseIds -Entries @($State.blockedPhases))
  $advanceablePartial = @($State.partialPhases | Where-Object { $_.status -eq "remote_resources_partial" -or $_.status -eq "crash_suspect_local_inventory_shape_visible" -or $_.status -eq "perk_da_catalog_not_found" -or $_.status -eq "perk_da_catalog_candidates_rejected" } | ForEach-Object { [string]$_.phaseId })

  foreach ($phase in @($Plan.phases)) {
    if ($completed -contains $phase.phaseId) { continue }
    if ($failed -contains $phase.phaseId) { continue }
    if ($blocked -contains $phase.phaseId) { continue }
    if ($advanceablePartial -contains $phase.phaseId) { continue }
    if ($phase.implemented -ne $true) { continue }
    return $phase
  }
  return $null
}

function Assert-CampaignPhaseSafety {
  param([Parameter(Mandatory = $true)][object]$Phase)

  $required = @{}
  if ($null -ne $Phase.requiredGates) {
    foreach ($prop in $Phase.requiredGates.PSObject.Properties) {
      $required[$prop.Name] = [bool]$prop.Value
    }
  }

  foreach ($gate in @("allowHudTickHook", "allowWriteProbes", "allowRpcProbes")) {
    if ($required.ContainsKey($gate) -and $required[$gate]) {
      throw "Campaign phase $($Phase.phaseId) may not enable $gate."
    }
  }
  if (($required.ContainsKey("allowHealthProbes") -and $required["allowHealthProbes"]) -and ($Phase.phaseId -notmatch '^(health-|multiplayer-health-)')) {
    if ($Phase.phaseId -ne "multiplayer-resource-visibility-read") {
      throw "Campaign phase $($Phase.phaseId) may not enable allowHealthProbes."
    }
  }
  if (($required.ContainsKey("allowIdentityProbes") -and $required["allowIdentityProbes"]) -and $Phase.phaseId -ne "multiplayer-roster-read" -and $Phase.phaseId -ne "multiplayer-resource-visibility-read") {
    throw "Campaign phase $($Phase.phaseId) may not enable allowIdentityProbes."
  }
  if (($required.ContainsKey("allowResourceVisibilityProbes") -and $required["allowResourceVisibilityProbes"]) -and $Phase.phaseId -ne "multiplayer-resource-visibility-read") {
    throw "Campaign phase $($Phase.phaseId) may not enable allowResourceVisibilityProbes."
  }
  if (($required.ContainsKey("allowCrystalsReadProbes") -and $required["allowCrystalsReadProbes"]) -and $Phase.phaseId -ne "crystals-read") {
    throw "Campaign phase $($Phase.phaseId) may not enable allowCrystalsReadProbes."
  }
  if (($required.ContainsKey("allowSlotsReadProbes") -and $required["allowSlotsReadProbes"]) -and $Phase.phaseId -ne "slots-read") {
    throw "Campaign phase $($Phase.phaseId) may not enable allowSlotsReadProbes."
  }
  if (($required.ContainsKey("allowSafeScalarWatchProbes") -and $required["allowSafeScalarWatchProbes"]) -and $Phase.phaseId -ne "safe-scalar-watch") {
    throw "Campaign phase $($Phase.phaseId) may not enable allowSafeScalarWatchProbes."
  }
  if (($required.ContainsKey("allowPerkDataAssetCatalogProbes") -and $required["allowPerkDataAssetCatalogProbes"]) -and $Phase.phaseId -ne "perk-da-catalog-read") {
    throw "Campaign phase $($Phase.phaseId) may not enable allowPerkDataAssetCatalogProbes."
  }
  if (($required.ContainsKey("allowInventoryArrayShallowProbes") -and $required["allowInventoryArrayShallowProbes"]) -and $Phase.phaseId -ne "local-inventory-array-shallow-read") {
    throw "Campaign phase $($Phase.phaseId) may not enable allowInventoryArrayShallowProbes."
  }
  if (($required.ContainsKey("allowInventoryArrayShapeConfirmProbes") -and $required["allowInventoryArrayShapeConfirmProbes"]) -and $Phase.phaseId -ne "local-inventory-array-shape-confirm") {
    throw "Campaign phase $($Phase.phaseId) may not enable allowInventoryArrayShapeConfirmProbes."
  }
  if (($required.ContainsKey("allowInventoryUserdataIntrospectionProbes") -and $required["allowInventoryUserdataIntrospectionProbes"]) -and $Phase.phaseId -ne "local-inventory-userdata-introspection") {
    throw "Campaign phase $($Phase.phaseId) may not enable allowInventoryUserdataIntrospectionProbes."
  }
  if ($required.ContainsKey("allowRawIdentityEvidence") -and $required["allowRawIdentityEvidence"]) {
    throw "Campaign phase $($Phase.phaseId) may not enable allowRawIdentityEvidence by default."
  }
  if (($required.ContainsKey("allowInventoryInfoProbes") -and $required["allowInventoryInfoProbes"]) -and $Phase.phaseId -ne "inventoryinfo-scalar-read") {
    throw "Campaign phase $($Phase.phaseId) may not enable allowInventoryInfoProbes."
  }
  if (($required.ContainsKey("allowDeepArrayProbes") -and $required["allowDeepArrayProbes"]) -and $Phase.phaseId -notmatch 'deep|inventory-element-da-read') {
    throw "Campaign phase $($Phase.phaseId) may not enable allowDeepArrayProbes."
  }
}

function Set-CampaignPhaseConfig {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][object]$Phase
  )

  Assert-CampaignPhaseSafety -Phase $Phase

  Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key "enabled" -Value "true"
  Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key "mode" -Value ([string]$Phase.mode)
  Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key "tickDriver" -Value ([string]$Phase.tickDriver)
  Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key "probeSet" -Value ([string]$Phase.probeSet)
  Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key "debugTickHeartbeat" -Value ($(if ($Phase.tickDriver -eq "none") { "false" } else { "true" }))
  Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key "debugWriterSelfTest" -Value "true"
  Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key "repeatProbeSet" -Value ($(if ($Phase.phaseId -match 'watch') { "true" } else { "false" }))
  Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key "maxProbesPerSession" -Value ($(if ($Phase.phaseId -eq "safe-scalar-watch") { "240" } elseif ($Phase.phaseId -match 'watch') { "180" } else { "100" }))
  Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key "safeScalarWatchIntervalSeconds" -Value "5"
  Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key "safeScalarWatchHeartbeatSeconds" -Value "60"
  Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key "safeScalarWatchMaxSamples" -Value "240"

  foreach ($key in @(
    "allowHudTickHook",
    "allowUnknownRoleProbes",
    "allowJoinedClientDeepProbes",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowHealthProbes",
    "allowIdentityProbes",
    "allowRawIdentityEvidence",
    "allowResourceVisibilityProbes",
    "allowCrystalsReadProbes",
    "allowSlotsReadProbes",
    "allowSafeScalarWatchProbes",
    "allowPerkDataAssetCatalogProbes",
    "allowInventoryArrayShallowProbes",
    "allowInventoryArrayShapeConfirmProbes",
    "allowInventoryUserdataIntrospectionProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )) {
    Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key $key -Value "false"
  }

  if ($null -ne $Phase.requiredGates) {
    foreach ($prop in $Phase.requiredGates.PSObject.Properties) {
      if ($prop.Value -eq $true) {
        Set-CrabRuntimeProbeCampaignConfigValue -ConfigPath $ConfigPath -Key $prop.Name -Value "true"
      }
    }
  }
}

function Read-BuildInfoValue {
  param(
    [string]$Path,
    [string]$Key
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "not found" }
  foreach ($line in @(Get-Content -LiteralPath $Path)) {
    if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.*?)\s*$") {
      return $matches[1].Trim()
    }
  }
  return "not found"
}

function Assert-CampaignInstalledSafety {
  param(
    [string]$ConfigPath,
    [switch]$AllowHealthProbes,
    [switch]$AllowIdentityProbes,
    [switch]$AllowResourceVisibilityProbes,
    [switch]$AllowCrystalsReadProbes,
    [switch]$AllowSlotsReadProbes,
    [switch]$AllowSafeScalarWatchProbes,
    [switch]$AllowPerkDataAssetCatalogProbes,
    [switch]$AllowInventoryArrayShallowProbes,
    [switch]$AllowInventoryArrayShapeConfirmProbes,
    [switch]$AllowInventoryUserdataIntrospectionProbes,
    [switch]$AllowInventoryInfoProbes,
    [switch]$AllowDeepArrayProbes
  )

  $errors = New-Object System.Collections.Generic.List[string]
  foreach ($key in @(
    "allowHudTickHook",
    "allowUnknownRoleProbes",
    "allowJoinedClientDeepProbes",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowHealthProbes",
    "allowIdentityProbes",
    "allowRawIdentityEvidence",
    "allowResourceVisibilityProbes",
    "allowCrystalsReadProbes",
    "allowSlotsReadProbes",
    "allowInventoryArrayShallowProbes",
    "allowInventoryArrayShapeConfirmProbes",
    "allowInventoryUserdataIntrospectionProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )) {
    $value = Get-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key $key
    $allowed =
      ($AllowHealthProbes -and $key -eq "allowHealthProbes") -or
      ($AllowIdentityProbes -and $key -eq "allowIdentityProbes") -or
      ($AllowResourceVisibilityProbes -and $key -eq "allowResourceVisibilityProbes") -or
      ($AllowCrystalsReadProbes -and $key -eq "allowCrystalsReadProbes") -or
      ($AllowSlotsReadProbes -and $key -eq "allowSlotsReadProbes") -or
      ($AllowSafeScalarWatchProbes -and $key -eq "allowSafeScalarWatchProbes") -or
      ($AllowPerkDataAssetCatalogProbes -and $key -eq "allowPerkDataAssetCatalogProbes") -or
      ($AllowInventoryArrayShallowProbes -and $key -eq "allowInventoryArrayShallowProbes") -or
      ($AllowInventoryArrayShapeConfirmProbes -and $key -eq "allowInventoryArrayShapeConfirmProbes") -or
      ($AllowInventoryUserdataIntrospectionProbes -and $key -eq "allowInventoryUserdataIntrospectionProbes") -or
      ($AllowInventoryInfoProbes -and $key -eq "allowInventoryInfoProbes") -or
      ($AllowDeepArrayProbes -and $key -eq "allowDeepArrayProbes")
    if ($allowed -and $value -eq "true") { continue }
    if ($value -ne "false") { $errors.Add("$key must be false, got '$value'") | Out-Null }
  }
  if ($errors.Count -gt 0) {
    throw "Campaign installed config safety validation failed:`n$((($errors | ForEach-Object { " - $_" }) -join "`n"))"
  }
}

function Clear-CampaignRuntimeFiles {
  param([string]$ScriptsRoot)

  $results = Join-Path $ScriptsRoot "results"
  foreach ($path in @(
    (Join-Path $ScriptsRoot "diagnostic_summary.txt"),
    (Join-Path $results "diagnostic_summary.txt"),
    (Join-Path $results "prepare_marker.json")
  )) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      Remove-Item -LiteralPath $path -Force
    }
  }

  if (Test-Path -LiteralPath $results -PathType Container) {
    Get-ChildItem -LiteralPath $results -File -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^(probe_results_|access_evidence_|session_manifest_).*\.(jsonl|json)$' } |
      Remove-Item -Force
  }
}

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$GameBinFull = [System.IO.Path]::GetFullPath($GameBin)
$PlanPath = Join-Path $RepoRoot "campaign\campaign_plan.crabruntimeprobe-read-map.json"
$InstallScriptsRoot = Join-Path $GameBinFull "Mods\CrabRuntimeProbe\Scripts"
$InstalledConfigPath = Join-Path $InstallScriptsRoot "config.txt"
$ResultsRoot = Join-Path $InstallScriptsRoot "results"
$InstalledStatePath = Join-Path $ResultsRoot "campaign_state.json"
$RepoStatePath = Join-Path $RepoRoot "evidence\campaign_state.json"
$BuildInfoPath = Join-Path $InstallScriptsRoot "build_info.txt"

if (-not (Test-Path -LiteralPath $GameBinFull -PathType Container)) {
  New-Item -ItemType Directory -Force -Path $GameBinFull | Out-Null
}

& (Join-Path $PSScriptRoot "install-client-to-game.ps1") $GameBinFull 6>$null | Out-Null
& (Join-Path $PSScriptRoot "verify-installed-client.ps1") $GameBinFull 6>$null | Out-Null
New-Item -ItemType Directory -Force -Path $ResultsRoot | Out-Null

if (-not (Test-Path -LiteralPath $InstalledStatePath -PathType Leaf) -and (Test-Path -LiteralPath $RepoStatePath -PathType Leaf)) {
  Copy-Item -LiteralPath $RepoStatePath -Destination $InstalledStatePath -Force
}

Push-Location $RepoRoot
try {
  node tools/update_campaign_state.js init --state $InstalledStatePath | Out-Null
  node tools/generate_campaign_docs.js --state $InstalledStatePath --write-state --quiet | Out-Null
} finally {
  Pop-Location
}

$plan = Read-JsonFile -Path $PlanPath
$state = Read-JsonFile -Path $InstalledStatePath
$phase = Select-NextCampaignPhase -Plan $plan -State $state
if ($null -eq $phase) {
  throw "No pending implemented campaign phase is runnable. Check docs\CAMPAIGN_STATUS.md for blocked placeholders."
}

Set-CampaignPhaseConfig -ConfigPath $InstalledConfigPath -Phase $phase
Assert-CampaignInstalledSafety `
  -ConfigPath $InstalledConfigPath `
  -AllowHealthProbes:($phase.phaseId -match '^(health-|multiplayer-health-)' -or $phase.phaseId -eq "multiplayer-resource-visibility-read") `
  -AllowIdentityProbes:($phase.phaseId -eq "multiplayer-roster-read" -or $phase.phaseId -eq "multiplayer-resource-visibility-read") `
  -AllowResourceVisibilityProbes:($phase.phaseId -eq "multiplayer-resource-visibility-read") `
  -AllowCrystalsReadProbes:($phase.phaseId -eq "crystals-read") `
  -AllowSlotsReadProbes:($phase.phaseId -eq "slots-read") `
  -AllowSafeScalarWatchProbes:($phase.phaseId -eq "safe-scalar-watch") `
  -AllowPerkDataAssetCatalogProbes:($phase.phaseId -eq "perk-da-catalog-read") `
  -AllowInventoryArrayShallowProbes:($phase.phaseId -eq "local-inventory-array-shallow-read") `
  -AllowInventoryArrayShapeConfirmProbes:($phase.phaseId -eq "local-inventory-array-shape-confirm") `
  -AllowInventoryUserdataIntrospectionProbes:($phase.phaseId -eq "local-inventory-userdata-introspection") `
  -AllowInventoryInfoProbes:($phase.phaseId -eq "inventoryinfo-scalar-read") `
  -AllowDeepArrayProbes:($phase.phaseId -match 'deep|inventory-element-da-read')
Clear-CampaignRuntimeFiles -ScriptsRoot $InstallScriptsRoot

$expectedCommit = Read-BuildInfoValue -Path $BuildInfoPath -Key "git_commit"
$marker = [ordered]@{
  campaign = [string]$plan.campaign
  phaseId = [string]$phase.phaseId
  probeSet = [string]$phase.probeSet
  tickDriver = [string]$phase.tickDriver
  mode = [string]$phase.mode
  expectedGitCommit = $expectedCommit
  expectedProbeSet = [string]$phase.probeSet
  expectedTickDriver = [string]$phase.tickDriver
  expectedMode = [string]$phase.mode
  preparedAt = (Get-Date).ToUniversalTime().ToString("o")
}
Set-Content -LiteralPath (Join-Path $ResultsRoot "prepare_marker.json") -Value ($marker | ConvertTo-Json -Depth 6) -Encoding ASCII

Push-Location $RepoRoot
try {
  node tools/update_campaign_state.js prepare --state $InstalledStatePath --phase $phase.phaseId --commit $expectedCommit | Out-Null
  Copy-Item -LiteralPath $InstalledStatePath -Destination $RepoStatePath -Force
  node tools/generate_campaign_docs.js --state $RepoStatePath --write-state --quiet | Out-Null
} finally {
  Pop-Location
}

Write-Host "selectedPhase = $($phase.phaseId)"
Write-Host "humanAction = $($phase.humanInstructions)"
