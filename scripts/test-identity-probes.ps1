[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Assert-CrabRuntimeProbeConfig.ps1")

function Assert-Contains {
  param(
    [string]$Path,
    [string]$Expected
  )

  $text = Get-Content -Raw -LiteralPath $Path
  if ($text -notmatch [regex]::Escape($Expected)) {
    throw "$Path missing expected content: $Expected"
  }
}

function Assert-NotContains {
  param(
    [string]$Path,
    [string]$Unexpected
  )

  $text = Get-Content -Raw -LiteralPath $Path
  if ($text -match [regex]::Escape($Unexpected)) {
    throw "$Path unexpectedly contains: $Unexpected"
  }
}

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$SourceConfigPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\config.txt"

foreach ($key in @("allowIdentityProbes", "allowRawIdentityEvidence")) {
  $value = Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key $key
  if ($value -ne "false") {
    throw "default config expected $key = false, got '$value'"
  }
}

$ProbeRegistryPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\probe_registry.lua"
$ProbeRunnerPath = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe\Scripts\probe_runner.lua"
$probeRegistry = Get-Content -Raw -LiteralPath $ProbeRegistryPath
$probeRunner = Get-Content -Raw -LiteralPath $ProbeRunnerPath
foreach ($required in @(
  "Identity.GameState.SourceCandidate",
  "Identity.CrabGS.SourceCandidate",
  "Identity.PlayerArray.Shape",
  "Identity.FindAll.PlayerStateCandidates",
  "Identity.PlayerControllerCandidates",
  "Identity.VisiblePlayers.SourceCandidate"
)) {
  if ($probeRegistry -notmatch [regex]::Escape($required)) {
    throw "probe_registry.lua missing roster candidate probe: $required"
  }
}
if ($probeRunner -notmatch [regex]::Escape("probe.set == 'multiplayer-roster-read' and not config.allowIdentityProbes")) {
  throw "multiplayer-roster-read probes must remain gated by allowIdentityProbes."
}
foreach ($forbidden in @("allowWriteProbes = true", "allowRpcProbes = true", "allowHudTickHook = true", "allowDeepArrayProbes = true", "allowInventoryInfoProbes = true", "allowHealthProbes = true")) {
  if ($probeRegistry -match [regex]::Escape($forbidden)) {
    throw "identity roster probes must not enable or touch forbidden path: $forbidden"
  }
}

$WorkRoot = Join-Path $RepoRoot "dist\test-identity-probes-work"
if (Test-Path -LiteralPath $WorkRoot) {
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $WorkRoot "evidence\runtime\identitysession") | Out-Null
Copy-Item -LiteralPath (Join-Path $RepoRoot "wiki-src") -Destination (Join-Path $WorkRoot "wiki-src") -Recurse
Copy-Item -LiteralPath (Join-Path $RepoRoot "campaign") -Destination (Join-Path $WorkRoot "campaign") -Recurse

$SessionDir = Join-Path $WorkRoot "evidence\runtime\identitysession"
$safeGates = '"allowHudTickHook":false,"allowUnknownRoleProbes":false,"allowJoinedClientDeepProbes":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowIdentityProbes":true,"allowRawIdentityEvidence":false,"allowWriteProbes":false,"allowRpcProbes":false'
Set-Content -LiteralPath (Join-Path $SessionDir "access_evidence.jsonl") -Encoding ASCII -Value @(
  ('{"timestamp":"2026-05-05T00:00:01Z","sessionId":"identitysession","probeId":"Identity.LocalPlayer.Sample","probeName":"Identity.LocalPlayer.Sample","probeSet":"multiplayer-roster-read","category":"identity","symbol":"CrabPC.PlayerState","owner":"CrabPC","member":"PlayerState","accessMethod":"GetPropertyValue","accessKind":"identity","mode":"active","tickDriver":"executeDelay","tick":100,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"identity_sample","valueSummary":"localPlayerPresent=true displayFingerprints=abc12345:len7 idFingerprints=def67890:len17 rawIdentityEvidence=false","sourcePath":"CrabPC.PlayerState","localPlayerPresent":true,"visiblePlayerCount":1,"visiblePlayerCap":1,"displayNameFingerprints":["abc12345:len7"],"stableIdFingerprints":["def67890:len17"],"identityRawRedacted":true,"rawIdentityEvidence":false,"safetyGates":{' + $safeGates + '}}'),
  ('{"timestamp":"2026-05-05T00:00:02Z","sessionId":"identitysession","probeId":"Identity.VisiblePlayers.Sample","probeName":"Identity.VisiblePlayers.Sample","probeSet":"multiplayer-roster-read","category":"identity","symbol":"GameState.PlayerArray","owner":"GameState","member":"PlayerArray","accessMethod":"GetPropertyValue","accessKind":"identityRoster","mode":"active","tickDriver":"executeDelay","tick":110,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"identity_roster","valueSummary":"visiblePlayerCount=2 cap=8 sourcePath=GameStateBase.PlayerArray displayFingerprints=abc12345:len7,feedcafe:len5 idFingerprints=def67890:len17,0123abcd:len17 rawIdentityEvidence=false","sourcePath":"GameStateBase.PlayerArray","localPlayerPresent":true,"visiblePlayerCount":2,"visiblePlayerCap":8,"displayNameFingerprints":["abc12345:len7","feedcafe:len5"],"stableIdFingerprints":["def67890:len17","0123abcd:len17"],"identityRawRedacted":true,"rawIdentityEvidence":false,"safetyGates":{' + $safeGates + '}}')
)
Set-Content -LiteralPath (Join-Path $SessionDir "probe_results.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-05T00:00:01Z","sessionId":"identitysession","event":"Identity.LocalPlayer.Sample","probeName":"Identity.LocalPlayer.Sample","probeSet":"multiplayer-roster-read","result":"ok","valueSummary":"localPlayerPresent=true displayFingerprints=abc12345:len7 idFingerprints=def67890:len17 rawIdentityEvidence=false"}',
  '{"timestamp":"2026-05-05T00:00:02Z","sessionId":"identitysession","event":"Identity.VisiblePlayers.Sample","probeName":"Identity.VisiblePlayers.Sample","probeSet":"multiplayer-roster-read","result":"ok","valueSummary":"visiblePlayerCount=2 cap=8 sourcePath=GameStateBase.PlayerArray displayFingerprints=abc12345:len7,feedcafe:len5 idFingerprints=def67890:len17,0123abcd:len17 rawIdentityEvidence=false"}'
)
Set-Content -LiteralPath (Join-Path $SessionDir "session_manifest.json") -Encoding ASCII -Value ('{"sessionId":"identitysession","probeSet":"multiplayer-roster-read","tickDriver":"executeDelay","config":{"mode":"active","probeSet":"multiplayer-roster-read","tickDriver":"executeDelay",' + $safeGates + '},"safetyGates":{' + $safeGates + '},"activeResearchGates":["allowIdentityProbes"],"warning":"research gates enabled: allowIdentityProbes"}')
Set-Content -LiteralPath (Join-Path $SessionDir "diagnostic_summary.txt") -Encoding ASCII -Value @(
  "CrabRuntimeProbe diagnostic summary",
  "collection_mode = Collect",
  "latest_manifest_sessionId = identitysession",
  "latest_manifest_probeSet = multiplayer-roster-read",
  "latest_manifest_tickDriver = executeDelay",
  "allowIdentityProbes = true",
  "allowRawIdentityEvidence = false",
  "allowWriteProbes = false",
  "allowRpcProbes = false",
  "failures:",
  " - none"
)

Push-Location $WorkRoot
try {
  node (Join-Path $RepoRoot "tools\generate_access_docs.js")
  node (Join-Path $RepoRoot "tools\generate_campaign_docs.js") --state (Join-Path $WorkRoot "evidence\campaign_state.json") --out (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") --write-state --quiet
} finally {
  Pop-Location
}

Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Identity/roster samples: 2"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Raw IDs/names emitted: no; redacted/fingerprinted by default"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "Visible roster source resolved: yes"
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected "auto-room grouping still requires matched host and joined-client runs"
Assert-Contains -Path (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") -Expected "Raw IDs/names emitted: no, redacted/fingerprinted by default"
Assert-NotContains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Unexpected "765611"
Assert-NotContains -Path (Join-Path $WorkRoot "docs\CAMPAIGN_STATUS.md") -Unexpected "765611"

Write-Host "CrabRuntimeProbe identity probe checks passed."
