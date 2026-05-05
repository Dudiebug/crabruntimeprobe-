[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$GameBin,
  [switch]$Prepare,
  [switch]$PrepareSmoke,
  [switch]$CollectSmoke,
  [ValidateSet("none", "registerTick", "executeDelay", "loopAsync", "hud")]
  [string]$PrepareTickDriver,
  [switch]$PrepareEquipmentProperty,
  [switch]$PrepareHealthBaseline,
  [switch]$PrepareHealthPlayerState,
  [switch]$Collect,
  [switch]$CollectEquipmentProperty,
  [switch]$CollectHealthBaseline,
  [switch]$CollectHealthPlayerState,
  [switch]$ExpectObserveContext,
  [switch]$NoDiagnosticDebug
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

function Get-CycleMode {
  $modes = @()
  if ($Prepare) { $modes += "PrepareSmoke" }
  if ($PrepareSmoke) { $modes += "PrepareSmoke" }
  if ($CollectSmoke) { $modes += "CollectSmoke" }
  if (-not [string]::IsNullOrWhiteSpace($PrepareTickDriver)) { $modes += "PrepareTickDriver" }
  if ($PrepareEquipmentProperty) { $modes += "PrepareEquipmentProperty" }
  if ($PrepareHealthBaseline) { $modes += "PrepareHealthBaseline" }
  if ($PrepareHealthPlayerState) { $modes += "PrepareHealthPlayerState" }
  if ($Collect) { $modes += "Collect" }
  if ($CollectEquipmentProperty) { $modes += "CollectEquipmentProperty" }
  if ($CollectHealthBaseline) { $modes += "CollectHealthBaseline" }
  if ($CollectHealthPlayerState) { $modes += "CollectHealthPlayerState" }

  $unique = @($modes | Sort-Object -Unique)
  if ($unique.Count -ne 1) {
    throw "Choose exactly one mode: -PrepareSmoke, -CollectSmoke, -PrepareTickDriver <driver>, -PrepareEquipmentProperty, -PrepareHealthBaseline, -PrepareHealthPlayerState, -Collect, -CollectEquipmentProperty, -CollectHealthBaseline, or -CollectHealthPlayerState."
  }

  return $unique[0]
}

function Set-CrabRuntimeProbeConfigValue {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$Key,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $lines = $null
  for ($attempt = 1; $attempt -le 50; $attempt++) {
    try {
      $lines = @(Get-Content -LiteralPath $ConfigPath -ErrorAction Stop)
      break
    } catch {
      if ($attempt -eq 50) { throw }
      Start-Sleep -Milliseconds 200
    }
  }
  $pattern = "^\s*$([regex]::Escape($Key))\s*="
  $found = $false
  $updated = foreach ($line in $lines) {
    if ($line -match $pattern) {
      $found = $true
      "$Key = $Value"
    } else {
      $line
    }
  }

  if (-not $found) {
    throw "Cannot set missing config key '$Key' in $ConfigPath"
  }

  for ($attempt = 1; $attempt -le 50; $attempt++) {
    try {
      Set-Content -LiteralPath $ConfigPath -Value $updated -Encoding ASCII -ErrorAction Stop
      break
    } catch {
      if ($attempt -eq 50) { throw }
      Start-Sleep -Milliseconds 200
    }
  }
}

function Get-CrabRuntimeProbeConfigValueOrMissing {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$Key
  )

  if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    return "missing config"
  }

  $value = Get-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key $Key
  if ($null -eq $value) { return "missing" }
  return $value
}

function Test-CrabRuntimeProbeInstalledSafety {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [switch]$AllowHealthProbes
  )

  $errors = New-Object System.Collections.Generic.List[string]
  if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    $errors.Add("installed config is missing: $ConfigPath") | Out-Null
    return $errors
  }

  $tickDriver = Get-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "tickDriver"
  if ($null -eq $tickDriver) {
    $errors.Add("tickDriver is missing") | Out-Null
  } elseif ($script:CrabRuntimeProbeAllowedTickDrivers -notcontains $tickDriver) {
    $errors.Add("tickDriver has invalid value '$tickDriver'") | Out-Null
  }

  $requiredFalse = @(
    "allowHudTickHook",
    "allowUnknownRoleProbes",
    "allowJoinedClientDeepProbes",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowHealthProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )

  foreach ($key in $requiredFalse) {
    $values = @(Get-CrabRuntimeProbeConfigMatches -ConfigPath $ConfigPath -Key $key)
    if ($values.Count -eq 0) {
      $errors.Add("$key is missing") | Out-Null
      continue
    }
    foreach ($value in $values) {
      if ($AllowHealthProbes -and $key -eq "allowHealthProbes" -and [string]::Equals($value, "true", [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
      }
      if (-not [string]::Equals($value, "false", [System.StringComparison]::OrdinalIgnoreCase)) {
        $errors.Add("$key must be false, got '$value'") | Out-Null
      }
    }
  }

  return $errors
}

function Assert-CrabRuntimeProbeInstalledSafety {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [switch]$AllowHealthProbes
  )

  $errors = Test-CrabRuntimeProbeInstalledSafety -ConfigPath $ConfigPath -AllowHealthProbes:$AllowHealthProbes
  if ($errors.Count -gt 0) {
    throw "Installed config safety validation failed at $ConfigPath`n$((($errors | ForEach-Object { " - $_" }) -join "`n"))"
  }
}

function Clear-CrabRuntimeProbeRuntimeFiles {
  param(
    [Parameter(Mandatory = $true)][string]$GameBinFull,
    [Parameter(Mandatory = $true)][string]$ScriptsRoot
  )

  $removed = New-Object System.Collections.Generic.List[string]
  $ue4ssLog = Join-Path $GameBinFull "UE4SS.log"
  $summary = Join-Path $ScriptsRoot "diagnostic_summary.txt"

  foreach ($path in @($ue4ssLog, $summary)) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      Remove-Item -LiteralPath $path -Force
      $removed.Add($path) | Out-Null
    }
  }

  $candidateFiles = @()
  $resultsDir = Join-Path $ScriptsRoot "results"
  if (Test-Path -LiteralPath $resultsDir -PathType Container) {
    $candidateFiles += @(Get-ChildItem -LiteralPath $resultsDir -File -Force -ErrorAction SilentlyContinue)
  }
  if (Test-Path -LiteralPath $ScriptsRoot -PathType Container) {
    $candidateFiles += @(Get-ChildItem -LiteralPath $ScriptsRoot -File -Force -ErrorAction SilentlyContinue | Where-Object {
      $_.Name -match '\.jsonl$' -or $_.Name -match '^session_manifest_.*\.json$' -or $_.Name -match '^(push|recv).*\.json$'
    })
  }

  foreach ($file in $candidateFiles) {
    Remove-Item -LiteralPath $file.FullName -Force
    $removed.Add($file.FullName) | Out-Null
  }

  return $removed
}

function Get-CrabRuntimeProbeJsonlFiles {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptsRoot
  )

  $files = @()
  $resultsDir = Join-Path $ScriptsRoot "results"
  if (Test-Path -LiteralPath $resultsDir -PathType Container) {
    $files += @(Get-ChildItem -LiteralPath $resultsDir -Filter "probe_results_*.jsonl" -File -Force -ErrorAction SilentlyContinue)
  }
  if (Test-Path -LiteralPath $ScriptsRoot -PathType Container) {
    $files += @(Get-ChildItem -LiteralPath $ScriptsRoot -Filter "probe_results_*.jsonl" -File -Force -ErrorAction SilentlyContinue)
  }

  return @($files | Sort-Object FullName -Unique)
}

function Get-CrabRuntimeProbeAccessEvidenceFiles {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptsRoot
  )

  $files = @()
  $resultsDir = Join-Path $ScriptsRoot "results"
  if (Test-Path -LiteralPath $resultsDir -PathType Container) {
    $files += @(Get-ChildItem -LiteralPath $resultsDir -Filter "access_evidence_*.jsonl" -File -Force -ErrorAction SilentlyContinue)
  }
  if (Test-Path -LiteralPath $ScriptsRoot -PathType Container) {
    $files += @(Get-ChildItem -LiteralPath $ScriptsRoot -Filter "access_evidence_*.jsonl" -File -Force -ErrorAction SilentlyContinue)
  }

  return @($files | Sort-Object FullName -Unique)
}

function Get-CrabRuntimeProbeSessionManifestFiles {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptsRoot
  )

  $files = @()
  $resultsDir = Join-Path $ScriptsRoot "results"
  if (Test-Path -LiteralPath $resultsDir -PathType Container) {
    $files += @(Get-ChildItem -LiteralPath $resultsDir -Filter "session_manifest_*.json" -File -Force -ErrorAction SilentlyContinue)
  }
  if (Test-Path -LiteralPath $ScriptsRoot -PathType Container) {
    $files += @(Get-ChildItem -LiteralPath $ScriptsRoot -Filter "session_manifest_*.json" -File -Force -ErrorAction SilentlyContinue)
  }

  return @($files | Sort-Object FullName -Unique)
}

function Get-TextPresence {
  param(
    [string]$Text,
    [string]$Pattern
  )

  if ([string]::IsNullOrEmpty($Text)) { return $false }
  return ($Text -match $Pattern)
}

function Read-TextFileOrEmpty {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    return (Get-Content -Raw -LiteralPath $Path)
  }
  return ""
}

function Convert-CrabRuntimeProbeJsonlRecords {
  param([object[]]$JsonlFiles)

  $records = @()
  foreach ($file in $JsonlFiles) {
    $lineNumber = 0
    foreach ($line in @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
      $lineNumber += 1
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      try {
        $record = $line | ConvertFrom-Json -ErrorAction Stop
        $record | Add-Member -NotePropertyName "_sourceFile" -NotePropertyValue $file.FullName -Force
        $record | Add-Member -NotePropertyName "_lineNumber" -NotePropertyValue $lineNumber -Force
        $records += $record
      } catch {
        $bad = [pscustomobject]@{
          event = "Invalid.Jsonl"
          probeName = "Invalid.Jsonl"
          probeId = "Invalid.Jsonl"
          result = "parse_error"
          error = $_.Exception.Message
          _sourceFile = $file.FullName
          _lineNumber = $lineNumber
        }
        $records += $bad
      }
    }
  }
  return @($records)
}

function Get-RecordEventName {
  param([object]$Record)

  foreach ($name in @("event", "probeName", "probeId")) {
    if ($Record.PSObject.Properties.Name -contains $name) {
      $value = [string]$Record.$name
      if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
  }
  return "Unknown"
}

function Get-RecordValue {
  param(
    [object]$Record,
    [string[]]$Names
  )

  foreach ($name in $Names) {
    if ($Record.PSObject.Properties.Name -contains $name) {
      $value = [string]$Record.$name
      if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
  }
  return ""
}

function Format-JsonlEventSummary {
  param([object]$Record)

  $eventName = Get-RecordEventName -Record $Record
  $timestamp = Get-RecordValue -Record $Record -Names @("timestamp")
  $tick = Get-RecordValue -Record $Record -Names @("tick")
  $result = Get-RecordValue -Record $Record -Names @("result")
  $context = Get-RecordValue -Record $Record -Names @("context")
  $role = Get-RecordValue -Record $Record -Names @("role")
  $summary = Get-RecordValue -Record $Record -Names @("valueSummary", "error")

  $parts = @()
  if ($timestamp) { $parts += "ts=$timestamp" }
  if ($tick) { $parts += "tick=$tick" }
  $parts += "event=$eventName"
  if ($result) { $parts += "result=$result" }
  if ($context) { $parts += "context=$context" }
  if ($role) { $parts += "role=$role" }
  if ($summary) { $parts += "summary=$summary" }
  return ($parts -join " ")
}

function Format-EvidenceSummary {
  param([object]$Record)

  $timestamp = Get-RecordValue -Record $Record -Names @("timestamp")
  $symbol = Get-RecordValue -Record $Record -Names @("symbol")
  $accessMethod = Get-RecordValue -Record $Record -Names @("accessMethod")
  $status = Get-RecordValue -Record $Record -Names @("runtimeStatus", "result")
  $context = Get-RecordValue -Record $Record -Names @("context")
  $role = Get-RecordValue -Record $Record -Names @("role")
  $summary = Get-RecordValue -Record $Record -Names @("valueSummary", "error")

  $parts = @()
  if ($timestamp) { $parts += "ts=$timestamp" }
  if ($symbol) { $parts += "symbol=$symbol" }
  if ($accessMethod) { $parts += "accessMethod=$accessMethod" }
  if ($status) { $parts += "status=$status" }
  if ($context) { $parts += "context=$context" }
  if ($role) { $parts += "role=$role" }
  if ($summary) { $parts += "summary=$summary" }
  return ($parts -join " ")
}

function Add-CountLines {
  param(
    [string[]]$Lines,
    [string]$Header,
    [object[]]$Groups
  )

  $Lines += ""
  $Lines += $Header
  if ($Groups.Count -eq 0) {
    $Lines += " - none"
  } else {
    foreach ($group in $Groups) {
      $Lines += " - $($group.Name): $($group.Count)"
    }
  }
  return $Lines
}

function Write-DiagnosticSummary {
  param(
    [Parameter(Mandatory = $true)][string]$SummaryPath,
    [string[]]$Lines
  )

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $SummaryPath) | Out-Null
  Set-Content -LiteralPath $SummaryPath -Value $Lines -Encoding ASCII
}

function Set-InstalledSmokeConfig {
  param([string]$ConfigPath)

  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "tickDriver" -Value "none"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "debugTickHeartbeat" -Value "false"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "debugWriterSelfTest" -Value "true"
  foreach ($key in @(
    "allowHudTickHook",
    "allowUnknownRoleProbes",
    "allowJoinedClientDeepProbes",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowHealthProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )) {
    Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key $key -Value "false"
  }
}

function Set-InstalledTickDriverConfig {
  param(
    [string]$ConfigPath,
    [string]$TickDriver,
    [switch]$NoDebug
  )

  if ($TickDriver -eq "hud") {
    throw "Refusing tickDriver = hud because allowHudTickHook is false by default. This helper does not enable the unsafe HUD fallback."
  }

  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "tickDriver" -Value $TickDriver
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "mode" -Value "observe"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "debugTickHeartbeat" -Value ($(if ($NoDebug) { "false" } else { "true" }))
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "debugWriterSelfTest" -Value ($(if ($NoDebug) { "false" } else { "true" }))
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "probeSet" -Value "shallow-core"
  foreach ($key in @(
    "allowHudTickHook",
    "allowUnknownRoleProbes",
    "allowJoinedClientDeepProbes",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowHealthProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )) {
    Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key $key -Value "false"
  }
}

function Set-InstalledEquipmentPropertyConfig {
  param([string]$ConfigPath)

  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "tickDriver" -Value "executeDelay"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "mode" -Value "active"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "probeSet" -Value "equipment-property-read"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "debugTickHeartbeat" -Value "true"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "debugWriterSelfTest" -Value "true"
  foreach ($key in @(
    "allowHudTickHook",
    "allowUnknownRoleProbes",
    "allowJoinedClientDeepProbes",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowHealthProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )) {
    Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key $key -Value "false"
  }
}

function Set-InstalledHealthBaselineConfig {
  param([string]$ConfigPath)

  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "tickDriver" -Value "executeDelay"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "mode" -Value "active"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "probeSet" -Value "health-baseline-read"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "debugTickHeartbeat" -Value "true"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "debugWriterSelfTest" -Value "true"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "allowHealthProbes" -Value "true"
  foreach ($key in @(
    "allowHudTickHook",
    "allowUnknownRoleProbes",
    "allowJoinedClientDeepProbes",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )) {
    Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key $key -Value "false"
  }
}

function Set-InstalledHealthPlayerStateConfig {
  param([string]$ConfigPath)

  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "tickDriver" -Value "executeDelay"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "mode" -Value "active"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "probeSet" -Value "health-playerstate-read"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "debugTickHeartbeat" -Value "true"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "debugWriterSelfTest" -Value "true"
  Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "allowHealthProbes" -Value "true"
  foreach ($key in @(
    "allowHudTickHook",
    "allowUnknownRoleProbes",
    "allowJoinedClientDeepProbes",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )) {
    Set-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key $key -Value "false"
  }
}

$Mode = Get-CycleMode
$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$GameBinFull = [System.IO.Path]::GetFullPath($GameBin)
$SourceModRoot = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe"
$SourceConfigPath = Join-Path $SourceModRoot "Scripts\config.txt"
$InstallModRoot = Join-Path $GameBinFull "Mods\CrabRuntimeProbe"
$InstallScriptsRoot = Join-Path $InstallModRoot "Scripts"
$InstalledConfigPath = Join-Path $InstallScriptsRoot "config.txt"
$BuildInfoPath = Join-Path $InstallScriptsRoot "build_info.txt"
$SummaryPath = Join-Path $InstallScriptsRoot "diagnostic_summary.txt"
$Ue4ssLogPath = Join-Path $GameBinFull "UE4SS.log"

Assert-CrabRuntimeProbeModLayout -ModRoot $SourceModRoot -Label "source CrabRuntimeProbe mod"
Assert-CrabRuntimeProbeConfig -ConfigPath $SourceConfigPath -Label "source config"

if (-not (Test-Path -LiteralPath $GameBinFull -PathType Container)) {
  throw "Game bin path does not exist: $GameBinFull"
}

if ($Mode -eq "PrepareSmoke" -or $Mode -eq "PrepareTickDriver" -or $Mode -eq "PrepareEquipmentProperty" -or $Mode -eq "PrepareHealthBaseline" -or $Mode -eq "PrepareHealthPlayerState") {
  & (Join-Path $PSScriptRoot "install-client-to-game.ps1") $GameBinFull
  & (Join-Path $PSScriptRoot "verify-installed-client.ps1") $GameBinFull

  if ($Mode -eq "PrepareSmoke") {
    Set-InstalledSmokeConfig -ConfigPath $InstalledConfigPath
  } elseif ($Mode -eq "PrepareEquipmentProperty") {
    Set-InstalledEquipmentPropertyConfig -ConfigPath $InstalledConfigPath
  } elseif ($Mode -eq "PrepareHealthBaseline") {
    Set-InstalledHealthBaselineConfig -ConfigPath $InstalledConfigPath
  } elseif ($Mode -eq "PrepareHealthPlayerState") {
    Set-InstalledHealthPlayerStateConfig -ConfigPath $InstalledConfigPath
  } else {
    Set-InstalledTickDriverConfig -ConfigPath $InstalledConfigPath -TickDriver $PrepareTickDriver -NoDebug:$NoDiagnosticDebug
  }

  Assert-CrabRuntimeProbeInstalledSafety -ConfigPath $InstalledConfigPath -AllowHealthProbes:($Mode -eq "PrepareHealthBaseline" -or $Mode -eq "PrepareHealthPlayerState")
  $removed = Clear-CrabRuntimeProbeRuntimeFiles -GameBinFull $GameBinFull -ScriptsRoot $InstallScriptsRoot

  Write-Host "CrabRuntimeProbe diagnostic prepare passed."
  Write-Host "Mode: $Mode"
  Write-Host "Source repo path: $RepoRoot"
  Write-Host "Game bin path: $GameBinFull"
  Write-Host "Installed config path: $InstalledConfigPath"
  Write-Host "mode = $(Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "mode")"
  Write-Host "tickDriver = $(Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "tickDriver")"
  Write-Host "probeSet = $(Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "probeSet")"
  Write-Host "allowHudTickHook = $(Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "allowHudTickHook")"
  Write-Host "debugTickHeartbeat = $(Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "debugTickHeartbeat")"
  Write-Host "debugWriterSelfTest = $(Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "debugWriterSelfTest")"
  Write-Host "Cleared old runtime files: $($removed.Count)"
  Write-Host ""
  Write-Host "Next human action:"
  Write-Host " 1. Launch Crab Champions."
  if ($Mode -eq "PrepareSmoke") {
    Write-Host " 2. Sit at the menu for 20 to 30 seconds."
    Write-Host " 3. Quit the game."
    Write-Host " 4. Run: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-smoke-collect.ps1"
  } elseif ($Mode -eq "PrepareEquipmentProperty") {
    Write-Host " 2. Start a solo run and stay alive/in world for 30 to 60 seconds."
    Write-Host " 3. Quit the game."
    Write-Host " 4. Run: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-equipment-property-collect.ps1"
  } elseif ($Mode -eq "PrepareHealthBaseline") {
    Write-Host " 2. Start a solo run, note current/max health if visible, and stay alive/in world for 30 to 60 seconds."
    Write-Host " 3. Quit the game."
    Write-Host " 4. Run: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-health-baseline-collect.ps1"
  } elseif ($Mode -eq "PrepareHealthPlayerState") {
    Write-Host " 2. Start a solo run, note current/max health if visible, and stay alive/in world for 30 to 60 seconds."
    Write-Host " 3. Quit the game."
    Write-Host " 4. Run: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-health-playerstate-collect.ps1"
  } else {
    Write-Host " 2. Sit at the menu for 20 to 30 seconds."
    Write-Host " 3. Quit the game."
    Write-Host " 4. Run: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-tickdriver-collect.ps1"
  }
  exit 0
}

$safetyErrors = Test-CrabRuntimeProbeInstalledSafety -ConfigPath $InstalledConfigPath -AllowHealthProbes:($Mode -eq "CollectHealthBaseline" -or $Mode -eq "CollectHealthPlayerState")
$logText = Read-TextFileOrEmpty -Path $Ue4ssLogPath
$logLines = @()
if (Test-Path -LiteralPath $Ue4ssLogPath -PathType Leaf) {
  $logLines = @(Get-Content -LiteralPath $Ue4ssLogPath)
}

$jsonlFiles = @(Get-CrabRuntimeProbeJsonlFiles -ScriptsRoot $InstallScriptsRoot | Where-Object { $_.Length -gt 0 })
$jsonlText = ""
foreach ($file in $jsonlFiles) {
  $jsonlText += "`n# $($file.FullName)`n"
  $jsonlText += Get-Content -Raw -LiteralPath $file.FullName
}
$jsonlRecords = @(Convert-CrabRuntimeProbeJsonlRecords -JsonlFiles $jsonlFiles)
$accessEvidenceFiles = @(Get-CrabRuntimeProbeAccessEvidenceFiles -ScriptsRoot $InstallScriptsRoot)
$sessionManifestFiles = @(Get-CrabRuntimeProbeSessionManifestFiles -ScriptsRoot $InstallScriptsRoot | Where-Object { $_.Length -gt 0 })
$accessEvidenceRecords = @(Convert-CrabRuntimeProbeJsonlRecords -JsonlFiles $accessEvidenceFiles)
$evidenceSymbolMethodGroups = @($accessEvidenceRecords | ForEach-Object {
  $symbol = Get-RecordValue -Record $_ -Names @("symbol")
  $accessMethod = Get-RecordValue -Record $_ -Names @("accessMethod")
  if ([string]::IsNullOrWhiteSpace($symbol)) { $symbol = "Unknown" }
  if ([string]::IsNullOrWhiteSpace($accessMethod)) { $accessMethod = "Unknown" }
  "$symbol / $accessMethod"
} | Group-Object | Sort-Object Name)
$eventGroups = @($jsonlRecords | ForEach-Object { Get-RecordEventName -Record $_ } | Group-Object | Sort-Object Name)
$probeGroups = @($jsonlRecords | Where-Object { $_.PSObject.Properties.Name -contains "probeName" -and -not [string]::IsNullOrWhiteSpace([string]$_.probeName) } | Group-Object -Property probeName | Sort-Object Name)
$timestampValues = @($jsonlRecords | ForEach-Object { Get-RecordValue -Record $_ -Names @("timestamp") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$firstJsonlTimestamp = if ($timestampValues.Count -gt 0) { $timestampValues[0] } else { "not found" }
$lastJsonlTimestamp = if ($timestampValues.Count -gt 0) { $timestampValues[-1] } else { "not found" }
$observeContextRecords = @($jsonlRecords | Where-Object { (Get-RecordEventName -Record $_) -eq "Observe.Context" })
$startupSmokeCount = @($jsonlRecords | Where-Object { (Get-RecordEventName -Record $_) -eq "Debug.StartupSmoke" }).Count
$writerSelfTestCount = @($jsonlRecords | Where-Object { (Get-RecordEventName -Record $_) -eq "Debug.WriterSelfTest" }).Count
$observeContextCount = $observeContextRecords.Count
$lastObserveContext = if ($observeContextRecords.Count -gt 0) { $observeContextRecords[-1] } else { $null }
$contextValues = @($jsonlRecords | ForEach-Object { Get-RecordValue -Record $_ -Names @("context") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$roleValues = @($jsonlRecords | ForEach-Object { Get-RecordValue -Record $_ -Names @("role") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$uniqueContexts = @($contextValues | Sort-Object -Unique)
$uniqueRoles = @($roleValues | Sort-Object -Unique)
$firstContext = if ($contextValues.Count -gt 0) { $contextValues[0] } else { "not found" }
$lastContext = if ($contextValues.Count -gt 0) { $contextValues[-1] } else { "not found" }
$activeContextStabilityRecords = @($jsonlRecords | Where-Object {
  (Get-RecordValue -Record $_ -Names @("lifecycleState")) -eq "stable" -and
  (Get-RecordValue -Record $_ -Names @("context")) -notin @("", "unknown", "startup", "unstable", "traveling", "dead-or-respawning")
})
$stableSoloOrHostRecords = @($activeContextStabilityRecords | Where-Object {
  (Get-RecordValue -Record $_ -Names @("context")) -eq "solo" -or
  (Get-RecordValue -Record $_ -Names @("role")) -in @("solo-or-host", "host")
})
$equipmentPropertyProbeNames = @(
  "CrabPS.GetPropertyValue.WeaponDA",
  "CrabPS.GetPropertyValue.AbilityDA",
  "CrabPS.GetPropertyValue.MeleeDA"
)
$equipmentDirectFieldProbeNames = @(
  "CrabPS.DirectField.WeaponDA",
  "CrabPS.DirectField.AbilityDA",
  "CrabPS.DirectField.MeleeDA"
)
$equipmentPropertyRecords = @($jsonlRecords | Where-Object { $equipmentPropertyProbeNames -contains (Get-RecordValue -Record $_ -Names @("probeName", "probeId", "event")) })
$equipmentDirectFieldRecords = @($jsonlRecords | Where-Object { $equipmentDirectFieldProbeNames -contains (Get-RecordValue -Record $_ -Names @("probeName", "probeId", "event")) })
$equipmentPropertyWeaponRecords = @($jsonlRecords | Where-Object { (Get-RecordValue -Record $_ -Names @("probeName", "probeId", "event")) -eq "CrabPS.GetPropertyValue.WeaponDA" })
$equipmentPropertyAbilityRecords = @($jsonlRecords | Where-Object { (Get-RecordValue -Record $_ -Names @("probeName", "probeId", "event")) -eq "CrabPS.GetPropertyValue.AbilityDA" })
$equipmentPropertyMeleeRecords = @($jsonlRecords | Where-Object { (Get-RecordValue -Record $_ -Names @("probeName", "probeId", "event")) -eq "CrabPS.GetPropertyValue.MeleeDA" })
$latestWeaponSummary = if ($equipmentPropertyWeaponRecords.Count -gt 0) { Get-RecordValue -Record $equipmentPropertyWeaponRecords[-1] -Names @("valueSummary", "error", "result") } else { "not found" }
$latestAbilitySummary = if ($equipmentPropertyAbilityRecords.Count -gt 0) { Get-RecordValue -Record $equipmentPropertyAbilityRecords[-1] -Names @("valueSummary", "error", "result") } else { "not found" }
$latestMeleeSummary = if ($equipmentPropertyMeleeRecords.Count -gt 0) { Get-RecordValue -Record $equipmentPropertyMeleeRecords[-1] -Names @("valueSummary", "error", "result") } else { "not found" }
$healthProbeRecords = @($jsonlRecords | Where-Object {
  (Get-RecordValue -Record $_ -Names @("category")) -eq "health" -or
  (Get-RecordValue -Record $_ -Names @("probeName", "probeId", "event")) -match '^(FindFirstOf\.CrabHC|CrabHC\.|CrabPS\.(HealthInfo|GetPropertyValue\.(HealthInfo|BaseMaxHealth|MaxHealthMultiplier)))'
})
$playerStateHealthProbeNames = @(
  "CrabPS.GetPropertyValue.HealthInfo",
  "CrabPS.HealthInfo.CurrentHealth",
  "CrabPS.HealthInfo.CurrentMaxHealth",
  "CrabPS.GetPropertyValue.BaseMaxHealth",
  "CrabPS.GetPropertyValue.MaxHealthMultiplier"
)
$playerStateHealthRecords = @($jsonlRecords | Where-Object { $playerStateHealthProbeNames -contains (Get-RecordValue -Record $_ -Names @("probeName", "probeId", "event")) })
$findFirstCrabHCRecords = @($jsonlRecords | Where-Object { (Get-RecordValue -Record $_ -Names @("probeName", "probeId", "event")) -eq "FindFirstOf.CrabHC" })
function Get-LatestProbeSummary {
  param(
    [object[]]$Records,
    [string]$ProbeName
  )

  $matches = @($Records | Where-Object { (Get-RecordValue -Record $_ -Names @("probeName", "probeId", "event")) -eq $ProbeName })
  if ($matches.Count -eq 0) { return "not found" }
  return Get-RecordValue -Record $matches[-1] -Names @("valueSummary", "error", "result")
}
$latestCrabHCCurrentHealth = Get-LatestProbeSummary -Records $jsonlRecords -ProbeName "CrabHC.HealthInfo.CurrentHealth"
$latestCrabHCCurrentMaxHealth = Get-LatestProbeSummary -Records $jsonlRecords -ProbeName "CrabHC.HealthInfo.CurrentMaxHealth"
$latestCrabHCBaseMaxHealth = Get-LatestProbeSummary -Records $jsonlRecords -ProbeName "CrabHC.GetPropertyValue.BaseMaxHealth"
$latestCrabPSCurrentHealth = Get-LatestProbeSummary -Records $jsonlRecords -ProbeName "CrabPS.HealthInfo.CurrentHealth"
$latestCrabPSCurrentMaxHealth = Get-LatestProbeSummary -Records $jsonlRecords -ProbeName "CrabPS.HealthInfo.CurrentMaxHealth"
$latestCrabPSBaseMaxHealth = Get-LatestProbeSummary -Records $jsonlRecords -ProbeName "CrabPS.GetPropertyValue.BaseMaxHealth"
$latestCrabPSMaxHealthMultiplier = Get-LatestProbeSummary -Records $jsonlRecords -ProbeName "CrabPS.GetPropertyValue.MaxHealthMultiplier"
$unscopedCrabHCFullName = Get-LatestProbeSummary -Records $jsonlRecords -ProbeName "CrabHC.GetFullName"
if ($unscopedCrabHCFullName -eq "not found") {
  $unscopedCrabHCFullName = Get-LatestProbeSummary -Records $accessEvidenceRecords -ProbeName "CrabHC.GetFullName"
}
$ambiguousCrabHCDetected = ($findFirstCrabHCRecords.Count -gt 0) -or ($unscopedCrabHCFullName -ne "not found")
$unscopedCrabHCAppearsNonPlayer = $unscopedCrabHCFullName -match 'Destructible|Barrel|ChaoticBarrel'
$possibleBaseHealthModel = if (($latestCrabPSCurrentMaxHealth -match '(^|[^0-9])250(\.0+)?([^0-9]|$)') -or ($latestCrabPSBaseMaxHealth -match '(^|[^0-9])250(\.0+)?([^0-9]|$)')) {
  if ($unscopedCrabHCAppearsNonPlayer) {
    "solo player CrabPS base appears 250; unscoped CrabHC appears non-player/destructible, do not use as player health"
  } else {
    "solo player CrabPS base appears 250"
  }
} else {
  "unknown"
}

$started = Get-TextPresence -Text $logText -Pattern '\[CrabRuntimeProbe\] started'
$startupSmoke = Get-TextPresence -Text $jsonlText -Pattern 'Debug\.StartupSmoke'
$writerSelfTest = (Get-TextPresence -Text $logText -Pattern 'Debug\.WriterSelfTest') -or (Get-TextPresence -Text $jsonlText -Pattern 'Debug\.WriterSelfTest')
$observeContext = Get-TextPresence -Text $jsonlText -Pattern 'Observe\.Context'
$tickSourceLine = @($logLines | Where-Object { $_ -match '\[CrabRuntimeProbe\] tick source registered:' } | Select-Object -Last 1)
$tickSource = "not found"
if ($tickSourceLine.Count -gt 0 -and $tickSourceLine[0] -match 'tick source registered:\s*(.+)$') {
  $tickSource = $matches[1].Trim()
}
$hudUsed = ($tickSource -match 'hud|HUD ReceiveDrawHUD') -or (Get-TextPresence -Text $logText -Pattern 'HUD ReceiveDrawHUD')
$crabInventorySync = Get-TextPresence -Text $logText -Pattern 'CrabInventorySync|CrabInvSync'
$errorLines = @($logLines | Where-Object { $_ -match 'CrabRuntimeProbe' -and $_ -match 'ERROR' })
$lastCrabRuntimeProbeLogLine = @($logLines | Where-Object { $_ -match 'CrabRuntimeProbe' } | Select-Object -Last 1)
if ($lastCrabRuntimeProbeLogLine.Count -eq 0) {
  $lastCrabRuntimeProbeLogLine = @("not found")
}

$tickDriver = Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "tickDriver"
$installedMode = Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "mode"
$probeSet = Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "probeSet"
$debugWriterSelfTest = Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "debugWriterSelfTest"
$buildInfo = Read-TextFileOrEmpty -Path $BuildInfoPath
$failures = New-Object System.Collections.Generic.List[string]
foreach ($err in $safetyErrors) { $failures.Add($err) | Out-Null }

if ($Mode -eq "CollectSmoke") {
  if ($tickDriver -ne "none") { $failures.Add("Smoke collect expected tickDriver = none, got '$tickDriver'.") | Out-Null }
  if (-not $started) { $failures.Add("CrabRuntimeProbe did not print its startup line in UE4SS.log.") | Out-Null }
  if (-not $startupSmoke) { $failures.Add("Debug.StartupSmoke did not appear in JSONL output.") | Out-Null }
  if ($debugWriterSelfTest -eq "true" -and -not $writerSelfTest) { $failures.Add("Debug.WriterSelfTest was enabled but did not appear.") | Out-Null }
  if ($tickSource -ne "not found") { $failures.Add("Smoke run registered a tick source unexpectedly: $tickSource") | Out-Null }
  if ($hudUsed) { $failures.Add("HUD registration appeared during smoke run.") | Out-Null }
  if ($crabInventorySync) { $failures.Add("CrabInventorySync appeared unexpectedly in UE4SS.log.") | Out-Null }
  if ($errorLines.Count -gt 0) { $failures.Add("CrabRuntimeProbe ERROR lines appeared in UE4SS.log.") | Out-Null }
  if ($jsonlFiles.Count -eq 0) { $failures.Add("No CrabRuntimeProbe JSONL output exists after collection.") | Out-Null }
} else {
  if ($tickDriver -eq "none") { $failures.Add("Tick-driver collect expected a selected tickDriver, got none.") | Out-Null }
  if (-not $started) { $failures.Add("CrabRuntimeProbe did not print its startup line in UE4SS.log.") | Out-Null }
  if (-not $startupSmoke) { $failures.Add("Debug.StartupSmoke did not appear before tick registration.") | Out-Null }
  if ($hudUsed) { $failures.Add("HUD ReceiveDrawHUD was used; keep allowHudTickHook = false and do not test hud by default.") | Out-Null }
  if ($crabInventorySync) { $failures.Add("CrabInventorySync appeared unexpectedly in UE4SS.log.") | Out-Null }
  if ($jsonlFiles.Count -eq 0) { $failures.Add("No CrabRuntimeProbe JSONL output exists after collection.") | Out-Null }
  if ($ExpectObserveContext -and -not $observeContext) { $failures.Add("Expected Observe.Context during gameplay observe collection, but it did not appear.") | Out-Null }
}

if ($Mode -eq "CollectEquipmentProperty") {
  if ($installedMode -ne "active") { $failures.Add("Equipment property collect expected mode = active, got '$installedMode'.") | Out-Null }
  if ($tickDriver -ne "executeDelay") { $failures.Add("Equipment property collect expected tickDriver = executeDelay, got '$tickDriver'.") | Out-Null }
  if ($probeSet -ne "equipment-property-read") { $failures.Add("Equipment property collect expected probeSet = equipment-property-read, got '$probeSet'.") | Out-Null }
  if (-not $observeContext -and $activeContextStabilityRecords.Count -eq 0) {
    $failures.Add("Expected Observe.Context or active context stability evidence during equipment property collection.") | Out-Null
  }
  if ($equipmentDirectFieldRecords.Count -gt 0) {
    $failures.Add("DirectField equipment probe appeared during property-only collection.") | Out-Null
  }
  if ($equipmentPropertyWeaponRecords.Count -eq 0) { $failures.Add("Expected CrabPS.GetPropertyValue.WeaponDA during equipment property collection, but it did not run.") | Out-Null }
  if ($equipmentPropertyAbilityRecords.Count -eq 0) { $failures.Add("Expected CrabPS.GetPropertyValue.AbilityDA during equipment property collection, but it did not run.") | Out-Null }
  if ($equipmentPropertyMeleeRecords.Count -eq 0) { $failures.Add("Expected CrabPS.GetPropertyValue.MeleeDA during equipment property collection, but it did not run.") | Out-Null }
}

if ($Mode -eq "CollectHealthBaseline") {
  if ($installedMode -ne "active") { $failures.Add("Health baseline collect expected mode = active, got '$installedMode'.") | Out-Null }
  if ($tickDriver -ne "executeDelay") { $failures.Add("Health baseline collect expected tickDriver = executeDelay, got '$tickDriver'.") | Out-Null }
  if ($probeSet -ne "health-baseline-read") { $failures.Add("Health baseline collect expected probeSet = health-baseline-read, got '$probeSet'.") | Out-Null }
  if ((Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowHealthProbes") -ne "true") {
    $failures.Add("Health baseline collect expected allowHealthProbes = true for this explicit phase.") | Out-Null
  }
  if ($healthProbeRecords.Count -eq 0) {
    $failures.Add("Expected health baseline probes to run, but no health probe evidence appeared.") | Out-Null
  }
}

if ($Mode -eq "CollectHealthPlayerState") {
  if ($installedMode -ne "active") { $failures.Add("Health playerstate collect expected mode = active, got '$installedMode'.") | Out-Null }
  if ($tickDriver -ne "executeDelay") { $failures.Add("Health playerstate collect expected tickDriver = executeDelay, got '$tickDriver'.") | Out-Null }
  if ($probeSet -ne "health-playerstate-read") { $failures.Add("Health playerstate collect expected probeSet = health-playerstate-read, got '$probeSet'.") | Out-Null }
  if ((Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowHealthProbes") -ne "true") {
    $failures.Add("Health playerstate collect expected allowHealthProbes = true for this explicit phase.") | Out-Null
  }
  if ($findFirstCrabHCRecords.Count -gt 0) {
    $failures.Add("FindFirstOf.CrabHC appeared during playerstate-only health collection.") | Out-Null
  }
  foreach ($probeName in $playerStateHealthProbeNames) {
    if (@($playerStateHealthRecords | Where-Object { (Get-RecordValue -Record $_ -Names @("probeName", "probeId", "event")) -eq $probeName }).Count -eq 0) {
      $failures.Add("Expected $probeName during health playerstate collection, but it did not run.") | Out-Null
    }
  }
}

$crashSuspicion = "none"
if (-not $startupSmoke) {
  $crashSuspicion = "startup smoke missing; crash likely occurred before or during pure file-I/O startup smoke write"
} elseif ($tickDriver -ne "none" -and $tickSource -eq "not found") {
  $crashSuspicion = "startup smoke present but selected tick source did not register; inspect last CrabRuntimeProbe log line for risky driver phase"
}

$summaryLines = @(
  "CrabRuntimeProbe diagnostic summary",
  "timestamp = $((Get-Date).ToString('o'))",
  "collection_mode = $Mode",
  "source_repo_path = $RepoRoot",
  "game_bin_path = $GameBinFull",
  "installed_mod_path = $InstallModRoot",
  "installed_config_path = $InstalledConfigPath",
  "ue4ss_log_path = $Ue4ssLogPath",
  "jsonl_file_count = $($jsonlFiles.Count)",
  "jsonl_event_count = $($jsonlRecords.Count)",
  "access_evidence_file_count = $($accessEvidenceFiles.Count)",
  "access_evidence_event_count = $($accessEvidenceRecords.Count)",
  "session_manifest_file_count = $($sessionManifestFiles.Count)",
  "jsonl_first_timestamp = $firstJsonlTimestamp",
  "jsonl_last_timestamp = $lastJsonlTimestamp",
  "observe_context_count = $observeContextCount",
  "debug_startup_smoke_count = $startupSmokeCount",
  "debug_writer_self_test_count = $writerSelfTestCount",
  "tickDriver = $tickDriver",
  "mode = $installedMode",
  "probeSet = $probeSet",
  "direct_field_probe_ran = $($equipmentDirectFieldRecords.Count -gt 0)",
  "equipment_property_probe_ran = $($equipmentPropertyRecords.Count -gt 0)",
  "equipment_property_weapon_count = $($equipmentPropertyWeaponRecords.Count)",
  "equipment_property_ability_count = $($equipmentPropertyAbilityRecords.Count)",
  "equipment_property_melee_count = $($equipmentPropertyMeleeRecords.Count)",
  "latest_WeaponDA_value_summary = $latestWeaponSummary",
  "latest_AbilityDA_value_summary = $latestAbilitySummary",
  "latest_MeleeDA_value_summary = $latestMeleeSummary",
  "health_probe_ran = $($healthProbeRecords.Count -gt 0)",
  "latest_CrabHC_CurrentHealth = $latestCrabHCCurrentHealth",
  "latest_CrabHC_CurrentMaxHealth = $latestCrabHCCurrentMaxHealth",
  "latest_CrabHC_BaseMaxHealth = $latestCrabHCBaseMaxHealth",
  "latest_CrabPS_CurrentHealth = $latestCrabPSCurrentHealth",
  "latest_CrabPS_CurrentMaxHealth = $latestCrabPSCurrentMaxHealth",
  "latest_CrabPS_BaseMaxHealth = $latestCrabPSBaseMaxHealth",
  "latest_CrabPS_MaxHealthMultiplier = $latestCrabPSMaxHealthMultiplier",
  "playerstate_health_probe_ran = $($playerStateHealthRecords.Count -gt 0)",
  "ambiguous_crabhc_detected = $ambiguousCrabHCDetected",
  "unscoped_crabhc_fullName = $unscopedCrabHCFullName",
  "playerstate_current_health = $latestCrabPSCurrentHealth",
  "playerstate_current_max_health = $latestCrabPSCurrentMaxHealth",
  "playerstate_base_max_health = $latestCrabPSBaseMaxHealth",
  "playerstate_max_health_multiplier = $latestCrabPSMaxHealthMultiplier",
  "possible_base_health_model = $possibleBaseHealthModel",
  "unique_contexts_seen = $(if ($uniqueContexts.Count -gt 0) { $uniqueContexts -join ', ' } else { "none" })",
  "unique_roles_seen = $(if ($uniqueRoles.Count -gt 0) { $uniqueRoles -join ', ' } else { "none" })",
  "first_context = $firstContext",
  "last_context = $lastContext",
  "crabruntimeprobe_started = $started",
  "startup_smoke_appeared = $startupSmoke",
  "writer_self_test_appeared = $writerSelfTest",
  "observe_context_appeared = $observeContext",
  "tick_source_registered = $tickSource",
  "hud_receive_draw_hud_used = $hudUsed",
  "crabinventorysync_appeared_unexpectedly = $crabInventorySync",
  "last_crabruntimeprobe_log_line = $($lastCrabRuntimeProbeLogLine[0])",
  "crash_suspicion = $crashSuspicion",
  "allowHudTickHook = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowHudTickHook")",
  "allowUnknownRoleProbes = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowUnknownRoleProbes")",
  "allowJoinedClientDeepProbes = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowJoinedClientDeepProbes")",
  "allowDeepArrayProbes = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowDeepArrayProbes")",
  "allowInventoryInfoProbes = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowInventoryInfoProbes")",
  "allowHealthProbes = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowHealthProbes")",
  "allowWriteProbes = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowWriteProbes")",
  "allowRpcProbes = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowRpcProbes")",
  "observe_context_latest_context = $(if ($null -ne $lastObserveContext) { Get-RecordValue -Record $lastObserveContext -Names @("context") } else { "not found" })",
  "observe_context_latest_role = $(if ($null -ne $lastObserveContext) { Get-RecordValue -Record $lastObserveContext -Names @("role") } else { "not found" })",
  "observe_context_latest_lifecycle = $(if ($null -ne $lastObserveContext) { Get-RecordValue -Record $lastObserveContext -Names @("lifecycleState") } else { "not found" })",
  "observe_context_latest_world = $(if ($null -ne $lastObserveContext) { Get-RecordValue -Record $lastObserveContext -Names @("world", "worldName", "worldPath") } else { "not found" })",
  "observe_context_latest_map = $(if ($null -ne $lastObserveContext) { Get-RecordValue -Record $lastObserveContext -Names @("map", "mapName", "levelName") } else { "not found" })",
  "observe_context_latest_player = $(if ($null -ne $lastObserveContext) { Get-RecordValue -Record $lastObserveContext -Names @("player", "playerName", "playerStateExists", "crabPcExists") } else { "not found" })",
  "",
  "installed_build_info:"
)

if ([string]::IsNullOrWhiteSpace($buildInfo)) {
  $summaryLines += " - missing"
} else {
  foreach ($line in @($buildInfo -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    $summaryLines += " - $line"
  }
}

$summaryLines = Add-CountLines -Lines $summaryLines -Header "jsonl_event_type_counts:" -Groups $eventGroups
$summaryLines = Add-CountLines -Lines $summaryLines -Header "probe_result_counts_by_probe_name:" -Groups $probeGroups
$summaryLines = Add-CountLines -Lines $summaryLines -Header "access_evidence_counts_by_symbol_accessMethod:" -Groups $evidenceSymbolMethodGroups

$summaryLines += ""
$summaryLines += "jsonl_files:"
if ($jsonlFiles.Count -eq 0) {
  $summaryLines += " - none"
} else {
  foreach ($file in $jsonlFiles) {
    $summaryLines += " - $($file.FullName) ($($file.Length) bytes)"
  }
}

$summaryLines += ""
$summaryLines += "access_evidence_files:"
if ($accessEvidenceFiles.Count -eq 0) {
  $summaryLines += " - none"
} else {
  foreach ($file in $accessEvidenceFiles) {
    $summaryLines += " - $($file.FullName) ($($file.Length) bytes)"
  }
}

$summaryLines += ""
$summaryLines += "session_manifest_files:"
if ($sessionManifestFiles.Count -eq 0) {
  $summaryLines += " - none"
} else {
  foreach ($file in $sessionManifestFiles) {
    $summaryLines += " - $($file.FullName) ($($file.Length) bytes)"
  }
}

$summaryLines += ""
$summaryLines += "last_5_crabruntimeprobe_log_lines:"
$lastFiveLogLines = @($logLines | Where-Object { $_ -match 'CrabRuntimeProbe' } | Select-Object -Last 5)
if ($lastFiveLogLines.Count -eq 0) {
  $summaryLines += " - none"
} else {
  foreach ($line in $lastFiveLogLines) {
    $summaryLines += " - $line"
  }
}

$summaryLines += ""
$summaryLines += "last_5_jsonl_events:"
$lastFiveJsonl = @($jsonlRecords | Select-Object -Last 5)
if ($lastFiveJsonl.Count -eq 0) {
  $summaryLines += " - none"
} else {
  foreach ($record in $lastFiveJsonl) {
    $summaryLines += " - $(Format-JsonlEventSummary -Record $record)"
  }
}

$summaryLines += ""
$summaryLines += "latest_5_access_evidence_rows:"
$lastFiveEvidence = @($accessEvidenceRecords | Select-Object -Last 5)
if ($lastFiveEvidence.Count -eq 0) {
  $summaryLines += " - none"
} else {
  foreach ($record in $lastFiveEvidence) {
    $summaryLines += " - $(Format-EvidenceSummary -Record $record)"
  }
}

$summaryLines += ""
$summaryLines += "crabruntimeprobe_error_lines:"
if ($errorLines.Count -eq 0) {
  $summaryLines += " - none"
} else {
  foreach ($line in $errorLines) {
    $summaryLines += " - $line"
  }
}

$summaryLines += ""
$summaryLines += "failures:"
if ($failures.Count -eq 0) {
  $summaryLines += " - none"
} else {
  foreach ($failure in $failures) {
    $summaryLines += " - $failure"
  }
  $summaryLines += ""
  $summaryLines += "remediation:"
  $summaryLines += " - Run scripts\quick-smoke-prepare.ps1 from the real Git checkout before any tick-driver test."
  $summaryLines += " - Launch Crab Champions, sit at the menu for 20 to 30 seconds, quit, then collect again."
  $summaryLines += " - Keep allowHudTickHook and all unsafe probe gates false."
  $summaryLines += " - Disable CrabInventorySync during this diagnostic pass if it appears in the log."
}

Write-DiagnosticSummary -SummaryPath $SummaryPath -Lines $summaryLines

foreach ($line in $summaryLines) {
  Write-Host $line
}

if ($failures.Count -gt 0) {
  exit 1
}

exit 0
