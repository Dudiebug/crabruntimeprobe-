param(
  [string]$OutputDir = "dist",
  [switch]$Zip
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
  [System.IO.Path]::GetFullPath($OutputDir)
} else {
  [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDir))
}

$ModOnlyExportRoot = Join-Path $ResolvedOutputDir "CrabRuntimeProbe-mod-only"
$ModOnlyZipPath = Join-Path $ResolvedOutputDir "CrabRuntimeProbe-mod-only.zip"

function Assert-InsidePath {
  param(
    [Parameter(Mandatory = $true)][string]$Parent,
    [Parameter(Mandatory = $true)][string]$Child
  )
  $parentExact = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\')
  $parentFull = $parentExact + '\'
  $childFull = [System.IO.Path]::GetFullPath($Child)
  $childExact = $childFull.TrimEnd('\')
  if (($childExact -ne $parentExact) -and (-not $childFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase))) {
    throw "Refusing to operate outside $Parent`: $Child"
  }
}

function Copy-CleanDirectory {
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

function Add-VerifyError {
  param([string]$Message)
  $script:VerifyErrors.Add($Message) | Out-Null
}

function Require-File {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$RelativePath
  )
  if (-not (Test-Path -LiteralPath (Join-Path $Root $RelativePath) -PathType Leaf)) {
    Add-VerifyError "Missing required file: $RelativePath"
  }
}

function Require-DirectoryAbsent {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$RelativePath
  )
  if (Test-Path -LiteralPath (Join-Path $Root $RelativePath) -PathType Container) {
    Add-VerifyError "Forbidden directory present: $RelativePath"
  }
}

function Read-ConfigValue {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$Key
  )
  $line = Get-Content -LiteralPath $ConfigPath | Where-Object {
    $_ -match "^\s*$([regex]::Escape($Key))\s*="
  } | Select-Object -First 1
  if ($null -eq $line) { return $null }
  return ($line -replace '^\s*[^=]+\s*=\s*', '').Trim()
}

function Verify-Export {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$ModRelativeRoot
  )

  foreach ($file in @(
    (Join-Path $ModRelativeRoot "enabled.txt"),
    (Join-Path $ModRelativeRoot "Scripts\config.txt"),
    (Join-Path $ModRelativeRoot "Scripts\main.lua"),
    (Join-Path $ModRelativeRoot "Scripts\json.lua"),
    (Join-Path $ModRelativeRoot "Scripts\runtime_context.lua"),
    (Join-Path $ModRelativeRoot "Scripts\safe_access.lua"),
    (Join-Path $ModRelativeRoot "Scripts\probe_registry.lua"),
    (Join-Path $ModRelativeRoot "Scripts\probe_runner.lua"),
    (Join-Path $ModRelativeRoot "Scripts\result_writer.lua")
  )) {
    Require-File -Root $Root -RelativePath $file
  }

  foreach ($dir in @("objectdump", "results", "node_modules", ".git", "dist")) {
    Require-DirectoryAbsent -Root $Root -RelativePath $dir
  }

  $forbiddenDirs = Get-ChildItem -LiteralPath $Root -Recurse -Force -Directory | Where-Object {
    $_.Name -in @("objectdump", "results", "node_modules", ".git", "dist")
  }
  foreach ($dir in $forbiddenDirs) {
    Add-VerifyError "Forbidden directory present: $($dir.FullName.Substring($Root.Length).TrimStart('\'))"
  }

  $forbiddenFiles = Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Where-Object {
    $_.Name -match '\.(jsonl|log|dmp|dump)$' -or
    $_.Name -match '^(push|recv).*\.json$'
  }
  foreach ($file in $forbiddenFiles) {
    Add-VerifyError "Forbidden runtime file present: $($file.FullName.Substring($Root.Length).TrimStart('\'))"
  }

  $configPath = Join-Path $Root (Join-Path $ModRelativeRoot "Scripts\config.txt")
  if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $expected = @{
      mode = "observe"
      allowDeepArrayProbes = "false"
      allowInventoryInfoProbes = "false"
      allowHealthProbes = "false"
      allowWriteProbes = "false"
      allowRpcProbes = "false"
    }
    foreach ($key in $expected.Keys) {
      $actual = Read-ConfigValue -ConfigPath $configPath -Key $key
      if ($actual -ne $expected[$key]) {
        Add-VerifyError "Unsafe config default in $configPath`: $key expected '$($expected[$key])' got '$actual'"
      }
    }
  }
}

Assert-InsidePath -Parent $RepoRoot -Child $ResolvedOutputDir
New-Item -ItemType Directory -Force -Path $ResolvedOutputDir | Out-Null

foreach ($path in @($ModOnlyExportRoot)) {
  Assert-InsidePath -Parent $ResolvedOutputDir -Child $path
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Recurse -Force
  }
}

$SourceModRoot = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe"
$ModOnlyDest = Join-Path $ModOnlyExportRoot "CrabRuntimeProbe"

Copy-CleanDirectory -Source $SourceModRoot -Destination $ModOnlyDest

$script:VerifyErrors = New-Object System.Collections.Generic.List[string]
Verify-Export -Root $ModOnlyExportRoot -ModRelativeRoot "CrabRuntimeProbe"

if ($script:VerifyErrors.Count -gt 0) {
  Write-Host "Client export verification failed:" -ForegroundColor Red
  foreach ($err in $script:VerifyErrors) {
    Write-Host " - $err" -ForegroundColor Red
  }
  exit 1
}

if ($Zip) {
  foreach ($zipPath in @($ModOnlyZipPath)) {
    Assert-InsidePath -Parent $ResolvedOutputDir -Child $zipPath
    if (Test-Path -LiteralPath $zipPath) {
      Remove-Item -LiteralPath $zipPath -Force
    }
  }

  Compress-Archive -Path (Join-Path $ModOnlyExportRoot "*") -DestinationPath $ModOnlyZipPath -Force
  Write-Host "Wrote $ModOnlyZipPath"
}

Write-Host "Exported $ModOnlyExportRoot"
Write-Host "Client export verification passed."
