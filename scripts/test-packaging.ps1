[CmdletBinding()]
param(
  [string]$GameBinPath
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$SourceModRoot = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe"
$SourceConfigPath = Join-Path $SourceModRoot "Scripts\config.txt"
$ExportRoot = Join-Path $RepoRoot "dist\CrabRuntimeProbe-client"
$ExportedModRoot = Join-Path $ExportRoot "Mods\CrabRuntimeProbe"
$ExportedConfigPath = Join-Path $ExportedModRoot "Scripts\config.txt"

Assert-CrabRuntimeProbeModLayout -ModRoot $SourceModRoot -Label "source CrabRuntimeProbe mod"
Assert-CrabRuntimeProbeConfig -ConfigPath $SourceConfigPath -Label "source config"

& (Join-Path $PSScriptRoot "export-client-folder.ps1") -OutputPath $ExportRoot

Assert-CrabRuntimeProbeModLayout -ModRoot $ExportedModRoot -Label "exported CrabRuntimeProbe mod"
Assert-CrabRuntimeProbeConfig -ConfigPath $ExportedConfigPath -Label "exported config"

if (-not [string]::IsNullOrWhiteSpace($GameBinPath)) {
  & (Join-Path $PSScriptRoot "verify-installed-client.ps1") $GameBinPath
}

Write-Host "CrabRuntimeProbe packaging checks passed."
