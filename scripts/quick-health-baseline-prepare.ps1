[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$DefaultGameBin = "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $DefaultGameBin -PrepareHealthBaseline

Write-Host ""
Write-Host "Launch Crab Champions, start a solo run, note current/max health if visible, stay alive/in world 30-60 seconds, quit, then run quick-health-baseline-collect.ps1."
