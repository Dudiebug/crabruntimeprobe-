[CmdletBinding()]
param(
  [string]$OutputPath = "dist\CrabRuntimeProbe-client",
  [switch]$Zip
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
$SourceClientRoot = Join-Path $RepoRoot "client"
$SourceModRoot = Join-Path $SourceClientRoot "Mods\CrabRuntimeProbe"
$SourceConfigPath = Join-Path $SourceModRoot "Scripts\config.txt"

Assert-CrabRuntimeProbeModLayout -ModRoot $SourceModRoot -Label "source CrabRuntimeProbe mod"
Assert-CrabRuntimeProbeConfig -ConfigPath $SourceConfigPath -Label "source config"

$OutputFull = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
  [System.IO.Path]::GetFullPath($OutputPath)
} else {
  [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputPath))
}

Assert-CrabRuntimeProbeInsidePath -Parent $RepoRoot -Child $OutputFull

if (Test-Path -LiteralPath $OutputFull) {
  Remove-Item -LiteralPath $OutputFull -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $OutputFull | Out-Null

Copy-CrabRuntimeProbeCleanDirectory -Source $SourceClientRoot -Destination $OutputFull

$ExportedModRoot = Join-Path $OutputFull "Mods\CrabRuntimeProbe"
$ExportedConfigPath = Join-Path $ExportedModRoot "Scripts\config.txt"
$BuildInfoPath = Write-CrabRuntimeProbeBuildInfo -RepoRoot $RepoRoot -ModRoot $ExportedModRoot -Action "export"

Assert-CrabRuntimeProbeModLayout -ModRoot $ExportedModRoot -Label "exported CrabRuntimeProbe mod"
Assert-CrabRuntimeProbeConfig -ConfigPath $ExportedConfigPath -Label "exported config"

if ($Zip) {
  $ZipPath = "$OutputFull.zip"
  Assert-CrabRuntimeProbeInsidePath -Parent $RepoRoot -Child $ZipPath
  if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
  }
  Compress-Archive -Path (Join-Path $OutputFull "*") -DestinationPath $ZipPath -Force
  Write-Host "Wrote ZIP: $ZipPath"
}

$allowHudTickHook = Get-CrabRuntimeProbeConfigValue -ConfigPath $ExportedConfigPath -Key "allowHudTickHook"
$tickDriver = Get-CrabRuntimeProbeConfigValue -ConfigPath $ExportedConfigPath -Key "tickDriver"

Write-Host "CrabRuntimeProbe client export passed."
Write-Host "Source repo path: $RepoRoot"
Write-Host "Copy from: $OutputFull"
Write-Host "Manual mod folder source: $ExportedModRoot"
Write-Host "Exported config path: $ExportedConfigPath"
Write-Host "Build info path: $BuildInfoPath"
Write-Host "tickDriver = $tickDriver"
Write-Host "allowHudTickHook = $allowHudTickHook"
Write-Host "For a full manual UE4SS client copy, copy the contents of '$OutputFull' into the Crab Champions Win64 folder."
