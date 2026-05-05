[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$DefaultGameBin = "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $DefaultGameBin -PrepareHealthPlayerStateWatch

Write-Host ""
Write-Host "Launch Crab Champions, start a solo run, stay in-world 60 to 120 seconds, pick up a max-health-changing pickup/perk only if one naturally appears, quit, then run quick-health-playerstate-watch-collect.ps1."
