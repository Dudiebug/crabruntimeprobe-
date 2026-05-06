[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$DefaultGameBin = "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $DefaultGameBin -PrepareMaxSafePlayRecorder

Write-Host ""
Write-Host "humanAction = Launch Crab Champions and play normally for up to 60 minutes. This records all currently proven-safe scalar values and capped perk DataAsset catalog snapshots. Do not use this for testing unproven inventory internals."
