param(
  [Parameter(Mandatory = $true)]
  [string]$GameBinPath
)

$ErrorActionPreference = "Stop"

$GameBinFull = [System.IO.Path]::GetFullPath($GameBinPath)
$ModsRoot = Join-Path $GameBinFull "Mods"
$ModRoot = Join-Path $ModsRoot "CrabRuntimeProbe"
$ModsTxt = Join-Path $ModsRoot "mods.txt"
$ConfigPath = Join-Path $ModRoot "Scripts\config.txt"
$errors = New-Object System.Collections.Generic.List[string]

function Add-Error {
  param([string]$Message)
  $errors.Add($Message) | Out-Null
}

function Require-File {
  param([string]$RelativePath)
  $full = Join-Path $GameBinFull $RelativePath
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
    Add-Error "Missing required file: $RelativePath"
  }
}

function Read-ConfigValue {
  param(
    [string]$ConfigPath,
    [string]$Key
  )
  $line = Get-Content -LiteralPath $ConfigPath | Where-Object {
    $_ -match "^\s*$([regex]::Escape($Key))\s*="
  } | Select-Object -First 1
  if ($null -eq $line) { return $null }
  return ($line -replace '^\s*[^=]+\s*=\s*', '').Trim()
}

if (-not (Test-Path -LiteralPath $GameBinFull -PathType Container)) {
  Write-Error "GameBinPath does not exist: $GameBinFull"
  exit 1
}

foreach ($file in @(
  "Mods\CrabRuntimeProbe\enabled.txt",
  "Mods\CrabRuntimeProbe\Scripts\main.lua",
  "Mods\CrabRuntimeProbe\Scripts\config.txt",
  "Mods\CrabRuntimeProbe\Scripts\probe_runner.lua",
  "Mods\CrabRuntimeProbe\Scripts\result_writer.lua",
  "Mods\CrabRuntimeProbe\Scripts\runtime_context.lua",
  "Mods\CrabRuntimeProbe\Scripts\safe_access.lua"
)) {
  Require-File $file
}

if (Test-Path -LiteralPath $ModsTxt -PathType Leaf) {
  $modsText = Get-Content -Raw -LiteralPath $ModsTxt
  if ($modsText -notmatch '(?m)^\s*CrabRuntimeProbe\s*:\s*1\s*$') {
    Add-Error "Mods\mods.txt must contain: CrabRuntimeProbe : 1"
  }
} else {
  Add-Error "Missing required file: Mods\mods.txt"
}

if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
  $expected = @{
    mode = "observe"
    allowHudTickHook = "false"
    allowDeepArrayProbes = "false"
    allowInventoryInfoProbes = "false"
    allowHealthProbes = "false"
    allowWriteProbes = "false"
    allowRpcProbes = "false"
  }

  foreach ($key in $expected.Keys) {
    $actual = Read-ConfigValue -ConfigPath $ConfigPath -Key $key
    if ($actual -ne $expected[$key]) {
      Add-Error "Unsafe config default: $key expected '$($expected[$key])' got '$actual'"
    }
  }
}

if ($errors.Count -gt 0) {
  Write-Host "Installed CrabRuntimeProbe verification failed:" -ForegroundColor Red
  foreach ($err in $errors) {
    Write-Host " - $err" -ForegroundColor Red
  }
  exit 1
}

Write-Host "Installed CrabRuntimeProbe verification passed: $ModRoot"
Write-Host "Mods\mods.txt enables CrabRuntimeProbe."
