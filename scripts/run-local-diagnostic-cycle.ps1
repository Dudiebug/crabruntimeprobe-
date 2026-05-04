[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$GameBin,
  [switch]$Prepare,
  [switch]$Collect,
  [switch]$NoDiagnosticDebug
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

function Assert-OneCycleMode {
  if (($Prepare -and $Collect) -or (-not $Prepare -and -not $Collect)) {
    throw "Choose exactly one mode: -Prepare or -Collect."
  }
}

function Set-CrabRuntimeProbeConfigValue {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$Key,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $lines = @(Get-Content -LiteralPath $ConfigPath)
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

  Set-Content -LiteralPath $ConfigPath -Value $updated -Encoding ASCII
}

function Test-CrabRuntimeProbeInstalledSafety {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath
  )

  $errors = New-Object System.Collections.Generic.List[string]
  if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    $errors.Add("installed config is missing: $ConfigPath") | Out-Null
    return $errors
  }

  $requiredFalse = @(
    "allowHudTickHook",
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
      if (-not [string]::Equals($value, "false", [System.StringComparison]::OrdinalIgnoreCase)) {
        $errors.Add("$key must be false, got '$value'") | Out-Null
      }
    }
  }

  return $errors
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

function Assert-CrabRuntimeProbeInstalledSafety {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath
  )

  $errors = Test-CrabRuntimeProbeInstalledSafety -ConfigPath $ConfigPath
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
      $_.Name -match '\.jsonl$' -or $_.Name -match '^(push|recv).*\.json$'
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
    $files += @(Get-ChildItem -LiteralPath $resultsDir -Filter "*.jsonl" -File -Force -ErrorAction SilentlyContinue)
  }
  if (Test-Path -LiteralPath $ScriptsRoot -PathType Container) {
    $files += @(Get-ChildItem -LiteralPath $ScriptsRoot -Filter "*.jsonl" -File -Force -ErrorAction SilentlyContinue)
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

function Write-DiagnosticSummary {
  param(
    [Parameter(Mandatory = $true)][string]$SummaryPath,
    [string[]]$Lines
  )

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $SummaryPath) | Out-Null
  Set-Content -LiteralPath $SummaryPath -Value $Lines -Encoding ASCII
}

Assert-OneCycleMode

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$GameBinFull = [System.IO.Path]::GetFullPath($GameBin)
$SourceModRoot = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe"
$SourceConfigPath = Join-Path $SourceModRoot "Scripts\config.txt"
$InstallModRoot = Join-Path $GameBinFull "Mods\CrabRuntimeProbe"
$InstallScriptsRoot = Join-Path $InstallModRoot "Scripts"
$InstalledConfigPath = Join-Path $InstallScriptsRoot "config.txt"
$SummaryPath = Join-Path $InstallScriptsRoot "diagnostic_summary.txt"
$Ue4ssLogPath = Join-Path $GameBinFull "UE4SS.log"

Assert-CrabRuntimeProbeModLayout -ModRoot $SourceModRoot -Label "source CrabRuntimeProbe mod"
Assert-CrabRuntimeProbeConfig -ConfigPath $SourceConfigPath -Label "source config"

if (-not (Test-Path -LiteralPath $GameBinFull -PathType Container)) {
  throw "Game bin path does not exist: $GameBinFull"
}

if ($Prepare) {
  & (Join-Path $PSScriptRoot "install-client-to-game.ps1") $GameBinFull
  & (Join-Path $PSScriptRoot "verify-installed-client.ps1") $GameBinFull

  if (-not $NoDiagnosticDebug) {
    Set-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "debugTickHeartbeat" -Value "true"
    Set-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "debugWriterSelfTest" -Value "true"
  }

  foreach ($key in @(
    "allowHudTickHook",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowHealthProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )) {
    Set-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key $key -Value "false"
  }

  Assert-CrabRuntimeProbeInstalledSafety -ConfigPath $InstalledConfigPath
  $removed = Clear-CrabRuntimeProbeRuntimeFiles -GameBinFull $GameBinFull -ScriptsRoot $InstallScriptsRoot

  Write-Host "CrabRuntimeProbe diagnostic prepare passed."
  Write-Host "Source repo path: $RepoRoot"
  Write-Host "Game bin path: $GameBinFull"
  Write-Host "Installed config path: $InstalledConfigPath"
  Write-Host "allowHudTickHook = $(Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "allowHudTickHook")"
  Write-Host "debugTickHeartbeat = $(Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "debugTickHeartbeat")"
  Write-Host "debugWriterSelfTest = $(Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "debugWriterSelfTest")"
  Write-Host "Cleared old runtime files: $($removed.Count)"
  Write-Host ""
  Write-Host "Next human action:"
  Write-Host " 1. Launch Crab Champions."
  Write-Host " 2. Sit at the menu for 20 to 30 seconds."
  Write-Host " 3. Quit the game."
  Write-Host " 4. Run: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-local-diagnostic-cycle.ps1 -GameBin `"$GameBinFull`" -Collect"
  exit 0
}

$safetyErrors = Test-CrabRuntimeProbeInstalledSafety -ConfigPath $InstalledConfigPath
$logText = ""
$logLines = @()
if (Test-Path -LiteralPath $Ue4ssLogPath -PathType Leaf) {
  $logText = Get-Content -Raw -LiteralPath $Ue4ssLogPath
  $logLines = @(Get-Content -LiteralPath $Ue4ssLogPath)
}

$jsonlFiles = @(Get-CrabRuntimeProbeJsonlFiles -ScriptsRoot $InstallScriptsRoot | Where-Object { $_.Length -gt 0 })
$jsonlText = ""
foreach ($file in $jsonlFiles) {
  $jsonlText += "`n# $($file.FullName)`n"
  $jsonlText += Get-Content -Raw -LiteralPath $file.FullName
}

$started = Get-TextPresence -Text $logText -Pattern '\[CrabRuntimeProbe\] started'
$tickSourceLine = @($logLines | Where-Object { $_ -match '\[CrabRuntimeProbe\] tick source registered:' } | Select-Object -Last 1)
$tickSource = "not found"
if ($tickSourceLine.Count -gt 0 -and $tickSourceLine[0] -match 'tick source registered:\s*(.+)$') {
  $tickSource = $matches[1].Trim()
}

$hudUsed = ($tickSource -match 'HUD ReceiveDrawHUD') -or (Get-TextPresence -Text $logText -Pattern 'HUD ReceiveDrawHUD')
$writerSelfTest = (Get-TextPresence -Text $logText -Pattern 'Debug\.WriterSelfTest') -or (Get-TextPresence -Text $jsonlText -Pattern 'Debug\.WriterSelfTest')
$observeContext = (Get-TextPresence -Text $jsonlText -Pattern 'Observe\.Context')
$crabInventorySync = Get-TextPresence -Text $logText -Pattern 'CrabInventorySync|CrabInvSync'
$errorLines = @($logLines | Where-Object { $_ -match 'CrabRuntimeProbe' -and $_ -match 'ERROR' })

$failures = New-Object System.Collections.Generic.List[string]
foreach ($err in $safetyErrors) { $failures.Add($err) | Out-Null }
if ($hudUsed) { $failures.Add("HUD ReceiveDrawHUD was used; keep allowHudTickHook = false and reinstall/prepare again.") | Out-Null }
if (-not $started) { $failures.Add("CrabRuntimeProbe did not print its startup line in UE4SS.log.") | Out-Null }
if ($jsonlFiles.Count -eq 0) { $failures.Add("No CrabRuntimeProbe JSONL output exists after collection.") | Out-Null }

$summaryLines = @(
  "CrabRuntimeProbe diagnostic summary",
  "timestamp = $((Get-Date).ToString('o'))",
  "source_repo_path = $RepoRoot",
  "game_bin_path = $GameBinFull",
  "installed_mod_path = $InstallModRoot",
  "installed_config_path = $InstalledConfigPath",
  "ue4ss_log_path = $Ue4ssLogPath",
  "jsonl_file_count = $($jsonlFiles.Count)",
  "crabruntimeprobe_started = $started",
  "tick_source_registered = $tickSource",
  "hud_receive_draw_hud_used = $hudUsed",
  "writer_self_test_appeared = $writerSelfTest",
  "observe_context_appeared = $observeContext",
  "crabinventorysync_appeared_unexpectedly = $crabInventorySync",
  "allowHudTickHook = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowHudTickHook")",
  "allowDeepArrayProbes = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowDeepArrayProbes")",
  "allowInventoryInfoProbes = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowInventoryInfoProbes")",
  "allowHealthProbes = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowHealthProbes")",
  "allowWriteProbes = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowWriteProbes")",
  "allowRpcProbes = $(Get-CrabRuntimeProbeConfigValueOrMissing -ConfigPath $InstalledConfigPath -Key "allowRpcProbes")",
  "",
  "jsonl_files:"
)

if ($jsonlFiles.Count -eq 0) {
  $summaryLines += " - none"
} else {
  foreach ($file in $jsonlFiles) {
    $summaryLines += " - $($file.FullName) ($($file.Length) bytes)"
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
  $summaryLines += " - Run scripts\quick-install-and-prepare.ps1 from the real Git checkout."
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
