[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("none", "registerTick", "executeDelay", "loopAsync", "hud")]
  [string]$TickDriver
)

$ErrorActionPreference = "Stop"
$DefaultGameBin = "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"

& (Join-Path $PSScriptRoot "run-local-diagnostic-cycle.ps1") -GameBin $DefaultGameBin -PrepareTickDriver $TickDriver
