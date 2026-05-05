[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$DefaultGameBin = "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"

$PowerShellExe = (Get-Process -Id $PID).Path

& $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $DefaultGameBin -CollectHealthPlayerState
$collectExit = $LASTEXITCODE

& $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "validate-latest-crash-bundle.ps1") -GameBin $DefaultGameBin -ExpectedProbeSet "health-playerstate-read" -ExpectedTickDriver "executeDelay" -ExpectedMode "active" -RequirePreparedRun
$validatorExit = $LASTEXITCODE

if ($collectExit -ne 0 -or $validatorExit -ne 0) {
  exit 1
}

exit 0
