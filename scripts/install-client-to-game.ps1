param(
  [Parameter(Mandatory = $true)]
  [string]$GameBinPath
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$GameBinFull = [System.IO.Path]::GetFullPath($GameBinPath)
$SourceModRoot = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe"
$ModsRoot = Join-Path $GameBinFull "Mods"
$InstallModRoot = Join-Path $ModsRoot "CrabRuntimeProbe"
$ModsTxt = Join-Path $ModsRoot "mods.txt"

function Copy-CleanDirectory {
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
    if ($segments -contains "objectdump") { return }
    if ($segments -contains "results") { return }
    if ($segments -contains "node_modules") { return }
    if ($segments -contains ".git") { return }
    if ($segments -contains "dist") { return }
    if ($name -match '\.(jsonl|log|dmp|dump)$') { return }
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

if (-not (Test-Path -LiteralPath $GameBinFull -PathType Container)) {
  throw "GameBinPath does not exist: $GameBinFull"
}

New-Item -ItemType Directory -Force -Path $ModsRoot | Out-Null
Copy-CleanDirectory -Source $SourceModRoot -Destination $InstallModRoot

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

Write-Host "Installed CrabRuntimeProbe to $InstallModRoot"
Write-Host "Ensured Mods\mods.txt contains: CrabRuntimeProbe : 1"
Write-Host "Reminder: disable CrabInventorySync during CrabRuntimeProbe probe testing."
