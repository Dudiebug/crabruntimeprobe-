[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$DefaultGameBin = "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $DefaultGameBin -PrepareTickDriver executeDelay

Write-Host ""
Write-Host "Launch Crab Champions, start a solo run or host lobby, stay alive/in world for 30-60 seconds, quit, then run quick-gameplay-observe-collect.ps1."
