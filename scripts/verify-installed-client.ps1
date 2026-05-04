[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$GameBinPath
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$GameBinFull = [System.IO.Path]::GetFullPath($GameBinPath)
$ModsRoot = Join-Path $GameBinFull "Mods"
$ModRoot = Join-Path $ModsRoot "CrabRuntimeProbe"
$ModsTxt = Join-Path $ModsRoot "mods.txt"
$ConfigPath = Join-Path $ModRoot "Scripts\config.txt"
$BuildInfoPath = Join-Path $ModRoot "Scripts\build_info.txt"
$errors = New-Object System.Collections.Generic.List[string]

function Add-VerifyError {
  param([string]$Message)
  $errors.Add($Message) | Out-Null
}

if (-not (Test-Path -LiteralPath $GameBinFull -PathType Container)) {
  Add-VerifyError "Game bin path does not exist: $GameBinFull"
}

if ($errors.Count -eq 0) {
  try {
    Assert-CrabRuntimeProbeModLayout -ModRoot $ModRoot -Label "installed CrabRuntimeProbe mod"
  } catch {
    Add-VerifyError $_.Exception.Message
  }

  try {
    Assert-CrabRuntimeProbeConfig -ConfigPath $ConfigPath -Label "installed config"
  } catch {
    Add-VerifyError $_.Exception.Message
  }

  if (Test-Path -LiteralPath $ModsTxt -PathType Leaf) {
    $modsText = Get-Content -Raw -LiteralPath $ModsTxt
    if ($modsText -notmatch '(?m)^\s*CrabRuntimeProbe\s*:\s*1\s*$') {
      Add-VerifyError "Mods\mods.txt must contain: CrabRuntimeProbe : 1"
    }
    if ($modsText -match "CrabInventorySync") {
      Write-Host "Warning: Mods\mods.txt mentions CrabInventorySync. Disable it during CrabRuntimeProbe testing for clean diagnostics." -ForegroundColor Yellow
    }
  } else {
    Add-VerifyError "Missing required file: Mods\mods.txt"
  }
}

if ($errors.Count -gt 0) {
  Write-Host "Installed CrabRuntimeProbe verification failed:" -ForegroundColor Red
  foreach ($err in $errors) {
    Write-Host " - $err" -ForegroundColor Red
  }
  Write-Host ""
  Write-Host "Remediation:" -ForegroundColor Yellow
  Write-Host " 1. Open the real Dudiebug/crabruntimeprobe- Git checkout on branch main."
  Write-Host " 2. Pull the latest main branch."
  Write-Host " 3. Run: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install-client-to-game.ps1 `"$GameBinFull`""
  Write-Host " 4. Re-run this verifier from the same real checkout."
  exit 1
}

$allowHudTickHook = Get-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key "allowHudTickHook"

Write-Host "Installed CrabRuntimeProbe verification passed."
Write-Host "Source repo path: $RepoRoot"
Write-Host "Game bin path: $GameBinFull"
Write-Host "Installed mod path: $ModRoot"
Write-Host "Installed config path: $ConfigPath"
Write-Host "allowHudTickHook = $allowHudTickHook"
if (Test-Path -LiteralPath $BuildInfoPath -PathType Leaf) {
  Write-Host "Build info path: $BuildInfoPath"
} else {
  Write-Host "Warning: build_info.txt is missing. Reinstall with scripts\install-client-to-game.ps1 to stamp the install." -ForegroundColor Yellow
}
