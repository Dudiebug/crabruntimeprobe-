[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$DefaultGameBin = "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $DefaultGameBin -PrepareSafeScalarWatch

Write-Host ""
Write-Host "humanAction = Launch Crab Champions and play normally for 5 to 20 minutes. This records only proven-safe scalar values every ~5 seconds or when changed. Do not use this for testing unproven inventory internals."
