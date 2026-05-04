[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$GameBinPath
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

function Copy-CrabRuntimeProbeCleanDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "Missing required directory: $Source"
  }

  New-Item -ItemType Directory -Force -Path $Destination | Out-Null

  $sourceFull = [System.IO.Path]::GetFullPath($Source).TrimEnd('\') + '\'
  Get-ChildItem -LiteralPath $Source -Recurse -Force | ForEach-Object {
    $itemFull = [System.IO.Path]::GetFullPath($_.FullName)
    if (-not $itemFull.StartsWith($sourceFull, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to copy path outside $Source`: $itemFull"
    }

    $relative = $itemFull.Substring($sourceFull.Length)
    if ([string]::IsNullOrWhiteSpace($relative)) { return }

    $segments = $relative -split '[\\/]'
    $name = $_.Name
    if ($segments -contains ".git") { return }
    if ($segments -contains "node_modules") { return }
    if ($segments -contains "results") { return }
    if ($segments -contains "objectdump") { return }
    if ($name -match '\.(dmp|jsonl|log)$') { return }
    if ($name -match '^(push|recv).*\.json$') { return }

    $target = Join-Path $Destination $relative
    if ($_.PSIsContainer) {
      New-Item -ItemType Directory -Force -Path $target | Out-Null
    } else {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
      Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
  }
}

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$GameBinFull = [System.IO.Path]::GetFullPath($GameBinPath)
$SourceModRoot = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe"
$SourceConfigPath = Join-Path $SourceModRoot "Scripts\config.txt"
$ModsRoot = Join-Path $GameBinFull "Mods"
$InstallModRoot = Join-Path $ModsRoot "CrabRuntimeProbe"
$ModsTxt = Join-Path $ModsRoot "mods.txt"

Assert-CrabRuntimeProbeModLayout -ModRoot $SourceModRoot -Label "source CrabRuntimeProbe mod"
Assert-CrabRuntimeProbeConfig -ConfigPath $SourceConfigPath -Label "source config"

if (-not (Test-Path -LiteralPath $GameBinFull -PathType Container)) {
  throw "Game bin path does not exist: $GameBinFull"
}

New-Item -ItemType Directory -Force -Path $ModsRoot | Out-Null
Assert-CrabRuntimeProbeInsidePath -Parent $ModsRoot -Child $InstallModRoot

if (Test-Path -LiteralPath $InstallModRoot) {
  Remove-Item -LiteralPath $InstallModRoot -Recurse -Force
}

Copy-CrabRuntimeProbeCleanDirectory -Source $SourceModRoot -Destination $InstallModRoot
$BuildInfoPath = Write-CrabRuntimeProbeBuildInfo -RepoRoot $RepoRoot -ModRoot $InstallModRoot -Action "install"

$InstalledConfigPath = Join-Path $InstallModRoot "Scripts\config.txt"
Assert-CrabRuntimeProbeModLayout -ModRoot $InstallModRoot -Label "installed CrabRuntimeProbe mod"
Assert-CrabRuntimeProbeConfig -ConfigPath $InstalledConfigPath -Label "installed config"

$existingLines = @()
if (Test-Path -LiteralPath $ModsTxt -PathType Leaf) {
  $existingLines = @(Get-Content -LiteralPath $ModsTxt)
}

$hasCrabRuntimeProbe = $false
$updatedLines = foreach ($line in $existingLines) {
  if ($line -match '^\s*CrabRuntimeProbe\s*:') {
    $hasCrabRuntimeProbe = $true
    'CrabRuntimeProbe : 1'
  } else {
    $line
  }
}

if (-not $hasCrabRuntimeProbe) {
  $updatedLines = @($updatedLines) + 'CrabRuntimeProbe : 1'
}

Set-Content -LiteralPath $ModsTxt -Value $updatedLines -Encoding ASCII

$allowHudTickHook = Get-CrabRuntimeProbeConfigValue -ConfigPath $InstalledConfigPath -Key "allowHudTickHook"

Write-Host "CrabRuntimeProbe install passed."
Write-Host "Source repo path: $RepoRoot"
Write-Host "Game bin path: $GameBinFull"
Write-Host "Installed mod path: $InstallModRoot"
Write-Host "Installed config path: $InstalledConfigPath"
Write-Host "Build info path: $BuildInfoPath"
Write-Host "allowHudTickHook = $allowHudTickHook"
Write-Host "Ensured Mods\mods.txt contains: CrabRuntimeProbe : 1"
