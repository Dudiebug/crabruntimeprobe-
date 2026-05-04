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

$hudFailed = $false
try {
  & (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $TestGameBin -PrepareTickDriver "hud"
} catch {
  $hudFailed = $true
}
if (-not $hudFailed) {
  throw "Expected hud tick driver prepare to fail while allowHudTickHook is false."
}

Write-Host "CrabRuntimeProbe packaging checks passed."
