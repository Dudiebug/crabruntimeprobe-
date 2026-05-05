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

function Assert-CommandFails {
  param([scriptblock]$Command)

  & $Command
  if ($LASTEXITCODE -eq 0) {
    throw "Expected command to fail."
  }
}

function Assert-UnsafeGatesFalse {
  param([string]$ConfigPath)

  foreach ($key in @(
    "allowHudTickHook",
    "allowUnknownRoleProbes",
    "allowJoinedClientDeepProbes",
    "allowDeepArrayProbes",
    "allowInventoryInfoProbes",
    "allowHealthProbes",
    "allowResourceVisibilityProbes",
    "allowWriteProbes",
    "allowRpcProbes"
  )) {
    $value = Get-CrabRuntimeProbeConfigValue -ConfigPath $ConfigPath -Key $key
    if ($value -ne "false") {
      throw "$ConfigPath expected $key = false, got '$value'"
    }
  }
}

$RepoRoot = Resolve-CrabRuntimeProbeRepoRoot -StartPath $PSScriptRoot -RequireGit
$SourceModRoot = Join-Path $RepoRoot "client\Mods\CrabRuntimeProbe"
$SourceConfigPath = Join-Path $SourceModRoot "Scripts\config.txt"
$EvidenceWriterPath = Join-Path $SourceModRoot "Scripts\evidence_writer.lua"

Assert-CrabRuntimeProbeModLayout -ModRoot $SourceModRoot -Label "source CrabRuntimeProbe mod"
if (-not (Test-Path -LiteralPath $EvidenceWriterPath -PathType Leaf)) {
  throw "evidence_writer.lua must exist."
}
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "tickDriver") -ne "none") {
  throw "source default tickDriver must remain none."
}
if ((Get-CrabRuntimeProbeConfigValue -ConfigPath $SourceConfigPath -Key "probeSet") -ne "shallow-core") {
  throw "source default probeSet must remain shallow-core."
}
Assert-UnsafeGatesFalse -ConfigPath $SourceConfigPath

$WorkRoot = Join-Path $RepoRoot "dist\test-evidence-docs-work"
if (Test-Path -LiteralPath $WorkRoot) {
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$IdentityTestPath = Join-Path $WorkRoot "identity-parser-test.js"
Set-Content -LiteralPath $IdentityTestPath -Encoding ASCII -Value @'
const { parseIdentityFromFullName } = require(process.argv[2]);
const cases = [
  ["CrabWeaponDA /Game/Blueprint/Weapon/Minigun/DA_Weapon_Minigun.DA_Weapon_Minigun", "DA_Weapon_Minigun"],
  ["CrabAbilityDA /Game/Blueprint/Ability/DA_Ability_BlackHole.DA_Ability_BlackHole", "DA_Ability_BlackHole"],
  ["CrabMeleeDA /Game/Blueprint/Melee/DA_Melee_Hammer.DA_Melee_Hammer", "DA_Melee_Hammer"]
];
for (const [fullName, expected] of cases) {
  const actual = parseIdentityFromFullName(fullName).shortName;
  if (actual !== expected) {
    throw new Error(`${fullName} expected ${expected}, got ${actual}`);
  }
}
'@
node $IdentityTestPath (Join-Path $RepoRoot "tools\identity_helpers.js")
if ($LASTEXITCODE -ne 0) { throw "identity parser test failed." }
Copy-Item -LiteralPath (Join-Path $RepoRoot "wiki-src") -Destination (Join-Path $WorkRoot "wiki-src") -Recurse

$GameResults = Join-Path $WorkRoot "game-results"
New-Item -ItemType Directory -Force -Path $GameResults | Out-Null
$SessionId = "testsession"
Set-Content -LiteralPath (Join-Path $GameResults "access_evidence_$SessionId.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-04T00:00:01Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"CrabPS.GetPropertyValue.WeaponDA","probeName":"CrabPS.GetPropertyValue.WeaponDA","probeSet":"equipment-property-read","category":"equipment","symbol":"CrabPS.WeaponDA","owner":"CrabPS","member":"WeaponDA","accessMethod":"GetPropertyValue","accessKind":"getProperty","mode":"active","tickDriver":"executeDelay","tick":100,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"object","valueSummary":"exists=true isValid=true fullName=CrabWeaponDA /Game/Blueprint/Weapon/Minigun/DA_Weapon_Minigun.DA_Weapon_Minigun name=error","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:01Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"CrabPS.GetPropertyValue.AbilityDA","probeName":"CrabPS.GetPropertyValue.AbilityDA","probeSet":"equipment-property-read","category":"equipment","symbol":"CrabPS.AbilityDA","owner":"CrabPS","member":"AbilityDA","accessMethod":"GetPropertyValue","accessKind":"getProperty","mode":"active","tickDriver":"executeDelay","tick":101,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"object","valueSummary":"exists=true isValid=true fullName=CrabAbilityDA /Game/Blueprint/Ability/DA_Ability_BlackHole.DA_Ability_BlackHole name=error","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:01Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"CrabPS.GetPropertyValue.MeleeDA","probeName":"CrabPS.GetPropertyValue.MeleeDA","probeSet":"equipment-property-read","category":"equipment","symbol":"CrabPS.MeleeDA","owner":"CrabPS","member":"MeleeDA","accessMethod":"GetPropertyValue","accessKind":"getProperty","mode":"active","tickDriver":"executeDelay","tick":102,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"object","valueSummary":"exists=true isValid=true fullName=CrabMeleeDA /Game/Blueprint/Melee/DA_Melee_Hammer.DA_Melee_Hammer name=error","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:02Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"CrabPS.DirectField.WeaponDA","probeName":"CrabPS.DirectField.WeaponDA","probeSet":"equipment-direct-field-read","category":"equipment","symbol":"CrabPS.WeaponDA","owner":"CrabPS","member":"WeaponDA","accessMethod":"DirectField","accessKind":"directField","mode":"active","tickDriver":"executeDelay","tick":110,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"unsafe_disabled","runtimeStatus":"UNSAFE_DISABLED","valueKind":"","valueSummary":"","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:03Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"FindFirstOf.CrabHC","probeName":"FindFirstOf.CrabHC","probeSet":"health-baseline-read","category":"health","symbol":"CrabHC","owner":"Runtime","member":"CrabHC","accessMethod":"FindFirstOf","accessKind":"findFirst","mode":"active","tickDriver":"executeDelay","tick":120,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"object","valueSummary":"CrabHC found","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":true,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:04Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"CrabHC.GetFullName","probeName":"CrabHC.GetFullName","probeSet":"health-baseline-read","category":"health","symbol":"CrabHC","owner":"CrabHC","member":"GetFullName","accessMethod":"GetFullName","accessKind":"getFullName","mode":"active","tickDriver":"executeDelay","tick":130,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"string","valueSummary":"CrabHC /Game/Island/Lobby.Lobby:PersistentLevel.BP_Destructible_ChaoticBarrel10.HC","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":true,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:05Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"CrabPS.HealthInfo.CurrentHealth","probeName":"CrabPS.HealthInfo.CurrentHealth","probeSet":"health-baseline-read","category":"health","symbol":"CrabPS.HealthInfo.CurrentHealth","owner":"CrabPS.HealthInfo","member":"CurrentHealth","accessMethod":"HealthInfoStructField","accessKind":"health","mode":"active","tickDriver":"executeDelay","tick":140,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"number","valueSummary":"250.0","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":true,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:06Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"CrabPS.HealthInfo.CurrentMaxHealth","probeName":"CrabPS.HealthInfo.CurrentMaxHealth","probeSet":"health-baseline-read","category":"health","symbol":"CrabPS.HealthInfo.CurrentMaxHealth","owner":"CrabPS.HealthInfo","member":"CurrentMaxHealth","accessMethod":"HealthInfoStructField","accessKind":"health","mode":"active","tickDriver":"executeDelay","tick":150,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"number","valueSummary":"250.0","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":true,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:07Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"CrabPS.GetPropertyValue.BaseMaxHealth","probeName":"CrabPS.GetPropertyValue.BaseMaxHealth","probeSet":"health-baseline-read","category":"health","symbol":"CrabPS.BaseMaxHealth","owner":"CrabPS","member":"BaseMaxHealth","accessMethod":"GetPropertyValue","accessKind":"health","mode":"active","tickDriver":"executeDelay","tick":160,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"number","valueSummary":"250.0","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":true,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:08Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"CrabPS.GetPropertyValue.MaxHealthMultiplier","probeName":"CrabPS.GetPropertyValue.MaxHealthMultiplier","probeSet":"health-baseline-read","category":"health","symbol":"CrabPS.MaxHealthMultiplier","owner":"CrabPS","member":"MaxHealthMultiplier","accessMethod":"GetPropertyValue","accessKind":"health","mode":"active","tickDriver":"executeDelay","tick":170,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"number","valueSummary":"1.0","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":true,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:09Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"Health.PlayerState.Sample","probeName":"Health.PlayerState.Sample","probeSet":"health-playerstate-watch","category":"health","symbol":"CrabPS.HealthInfo","owner":"CrabPS","member":"HealthInfo","accessMethod":"PlayerStateHealthSample","accessKind":"health","mode":"active","tickDriver":"executeDelay","tick":180,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"health_sample","valueSummary":"currentHealth=250 currentMaxHealth=250 baseMaxHealth=250 maxHealthMultiplier=1","currentHealth":250,"currentMaxHealth":250,"baseMaxHealth":250,"maxHealthMultiplier":1,"sampleIndex":1,"sourceScope":"player_state_scoped","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":true,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:10Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"Identity.LocalPlayer.Sample","probeName":"Identity.LocalPlayer.Sample","probeSet":"multiplayer-roster-read","category":"identity","symbol":"CrabPC.PlayerState","owner":"CrabPC","member":"PlayerState","accessMethod":"GetPropertyValue","accessKind":"identity","mode":"active","tickDriver":"executeDelay","tick":190,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"identity_sample","valueSummary":"localPlayerPresent=true displayFingerprints=abc:len3 idFingerprints=def:len4 displaySources=PlayerName idSources=UniqueId rawIdentityEvidence=false","localPlayerPresent":true,"visiblePlayerCount":1,"sourceScope":"player_state_scoped","sourcePath":"CrabPC.PlayerState","displayNameFingerprints":["abc:len3"],"stableIdFingerprints":["def:len4"],"rawIdentityEvidence":false,"identityRawRedacted":true,"error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowIdentityProbes":true,"allowRawIdentityEvidence":false,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:11Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"Identity.VisiblePlayers.Sample","probeName":"Identity.VisiblePlayers.Sample","probeSet":"multiplayer-roster-read","category":"identity","symbol":"GameState.PlayerArray","owner":"GameState","member":"PlayerArray","accessMethod":"GetPropertyValue","accessKind":"identityRoster","mode":"active","tickDriver":"executeDelay","tick":200,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"nil","runtimeStatus":"RETURNS_NIL","valueKind":"identity_roster","valueSummary":"visiblePlayerCount=0 sourcePath=GameStateBase.PlayerArray rawIdentityEvidence=false","localPlayerPresent":true,"visiblePlayerCount":0,"visiblePlayerCap":8,"sourceScope":"runtime_roster","sourcePath":"GameStateBase.PlayerArray","sourceClass":"GameStateBase","playerArrayValueKind":"nil","playerArrayTableSampleCount":0,"rosterSourceResolved":false,"displayNameFingerprints":{},"stableIdFingerprints":{},"rawIdentityEvidence":false,"identityRawRedacted":true,"error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowIdentityProbes":true,"allowRawIdentityEvidence":false,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:12Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"Identity.GameState.SourceCandidate","probeName":"Identity.GameState.SourceCandidate","probeSet":"multiplayer-roster-read","category":"identity","symbol":"GameStateBase GameState","owner":"Runtime","member":"GameState","accessMethod":"FindFirstOf","accessKind":"identitySourceCandidate","mode":"active","tickDriver":"executeDelay","tick":210,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"ok","runtimeStatus":"SAFE","valueKind":"object","valueSummary":"sourcePath=GameStateBase sourceClass=GameStateBase sourceName=CrabGS_0 objectClass=CrabGS rawIdentityEvidence=false","sourceScope":"runtime_roster_candidate","sourcePath":"GameStateBase","sourceClass":"GameStateBase","sourceName":"CrabGS_0","visiblePlayerCount":0,"visiblePlayerCap":0,"displayNameFingerprints":{},"stableIdFingerprints":{},"rawIdentityEvidence":false,"identityRawRedacted":true,"rosterSourceResolved":false,"localNotes":"FindFirstOf(GameStateBase) with GameState fallback; no roster traversal performed","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowIdentityProbes":true,"allowRawIdentityEvidence":false,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:13Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"Identity.PlayerArray.Shape","probeName":"Identity.PlayerArray.Shape","probeSet":"multiplayer-roster-read","category":"identity","symbol":"GameStateBase.PlayerArray","owner":"GameStateBase","member":"PlayerArray","accessMethod":"GetPropertyValueShapeOnly","accessKind":"identityRosterShape","mode":"active","tickDriver":"executeDelay","tick":220,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"nil","runtimeStatus":"RETURNS_NIL","valueKind":"identity_roster_shape","valueSummary":"sourcePath=GameStateBase.PlayerArray valueKind=nil tableSampleCount=0 cap=16 rawIdentityEvidence=false","sourceScope":"runtime_roster_candidate","sourcePath":"GameStateBase.PlayerArray","sourceClass":"GameStateBase","visiblePlayerCount":0,"visiblePlayerCap":16,"playerArrayValueKind":"nil","playerArrayTableSampleCount":0,"displayNameFingerprints":{},"stableIdFingerprints":{},"rawIdentityEvidence":false,"identityRawRedacted":true,"rosterSourceResolved":false,"localNotes":"Shape-only PlayerArray check; no recursive traversal","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowIdentityProbes":true,"allowRawIdentityEvidence":false,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:14Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"Identity.FindAll.PlayerStateCandidates","probeName":"Identity.FindAll.PlayerStateCandidates","probeSet":"multiplayer-roster-read","category":"identity","symbol":"PlayerState CrabPS","owner":"Runtime","member":"PlayerState","accessMethod":"FindAllOfCapped","accessKind":"identityRosterCandidates","mode":"active","tickDriver":"executeDelay","tick":230,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"nil","runtimeStatus":"RETURNS_NIL","valueKind":"identity_roster_candidates","valueSummary":"visiblePlayerCount=0 cap=16 sourcePath=FindAllOf(PlayerState,CrabPS) rawIdentityEvidence=false","sourceScope":"runtime_roster_candidate","sourcePath":"FindAllOf(PlayerState,CrabPS)","sourceClass":"PlayerState","candidateClasses":["PlayerState","CrabPS"],"visiblePlayerCount":0,"visiblePlayerCap":16,"displayNameFingerprints":[],"stableIdFingerprints":[],"rawIdentityEvidence":false,"identityRawRedacted":true,"rosterSourceResolved":false,"localNotes":"FindAllOf availability checked before capped PlayerState-like candidate traversal","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowIdentityProbes":true,"allowRawIdentityEvidence":false,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}',
  '{"timestamp":"2026-05-04T00:00:15Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"Identity.PlayerControllerCandidates","probeName":"Identity.PlayerControllerCandidates","probeSet":"multiplayer-roster-read","category":"identity","symbol":"PlayerController CrabPC","owner":"Runtime","member":"PlayerController.PlayerState","accessMethod":"FindAllOfCapped","accessKind":"identityControllerCandidates","mode":"active","tickDriver":"executeDelay","tick":240,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"nil","runtimeStatus":"RETURNS_NIL","valueKind":"identity_controller_candidates","valueSummary":"visiblePlayerCount=0 cap=8 sourcePath=FindAllOf(PlayerController,CrabPC).PlayerState rawIdentityEvidence=false","sourceScope":"runtime_roster_candidate","sourcePath":"FindAllOf(PlayerController,CrabPC).PlayerState","sourceClass":"PlayerController","candidateClasses":["PlayerController","CrabPC"],"visiblePlayerCount":0,"visiblePlayerCap":8,"displayNameFingerprints":[],"stableIdFingerprints":[],"rawIdentityEvidence":false,"identityRawRedacted":true,"rosterSourceResolved":false,"localNotes":"FindAllOf availability checked before capped PlayerController/CrabPC traversal","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowIdentityProbes":true,"allowRawIdentityEvidence":false,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}'
)
Set-Content -LiteralPath (Join-Path $GameResults "probe_results_$SessionId.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-04T00:00:01Z","sessionId":"testsession","probeId":"CrabPS.GetPropertyValue.WeaponDA","probeName":"CrabPS.GetPropertyValue.WeaponDA","result":"ok"}'
)
Set-Content -LiteralPath (Join-Path $GameResults "session_manifest_$SessionId.json") -Encoding ASCII -Value '{"sessionId":"testsession","tickDriver":"executeDelay","probeSet":"health-baseline-read","warning":"one or more unsafe gates are true","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":true,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}'
Set-Content -LiteralPath (Join-Path $GameResults "diagnostic_summary.txt") -Encoding ASCII -Value @(
  "CrabRuntimeProbe diagnostic summary",
  "collection_mode = CollectHealthPlayerStateWatch",
  "playerstate_health_watch_probe_ran = True",
  "ambiguous_crabhc_detected = False",
  "crab_hc_touched = False",
  "health_playerstate_watch_sample_count = 1",
  "health_playerstate_watch_currentHealth_first = 250",
  "health_playerstate_watch_currentHealth_last = 250",
  "health_playerstate_watch_currentHealth_min = 250",
  "health_playerstate_watch_currentHealth_max = 250",
  "health_playerstate_watch_currentMaxHealth_first = 250",
  "health_playerstate_watch_currentMaxHealth_last = 250",
  "health_playerstate_watch_currentMaxHealth_min = 250",
  "health_playerstate_watch_currentMaxHealth_max = 250",
  "health_playerstate_watch_baseMaxHealth_first = 250",
  "health_playerstate_watch_baseMaxHealth_last = 250",
  "health_playerstate_watch_baseMaxHealth_min = 250",
  "health_playerstate_watch_baseMaxHealth_max = 250",
  "health_playerstate_watch_maxHealthMultiplier_first = 1",
  "health_playerstate_watch_maxHealthMultiplier_last = 1",
  "health_playerstate_watch_maxHealthMultiplier_min = 1",
  "health_playerstate_watch_maxHealthMultiplier_max = 1",
  "possible_base_health_model = local PlayerState base appears 250",
  "allowHudTickHook = false",
  "allowUnknownRoleProbes = false",
  "allowJoinedClientDeepProbes = false",
  "allowDeepArrayProbes = false",
  "allowInventoryInfoProbes = false",
  "allowWriteProbes = false",
  "allowRpcProbes = false",
  "failures:",
  " - none"
)

Push-Location $WorkRoot
try {
  node (Join-Path $RepoRoot "tools\import_runtime_evidence.js") --from $GameResults
  node (Join-Path $RepoRoot "tools\generate_access_docs.js")
  node (Join-Path $RepoRoot "tools\build_wiki_docs.js")
} finally {
  Pop-Location
}

$MatrixPath = Join-Path $WorkRoot "docs\SAFE_ACCESS_MATRIX.md"
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.WeaponDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | testsession | sourceScope=player_state_scoped; shortName=DA_Weapon_Minigun nameSource=fullNameFallback objectClass=CrabWeaponDA |'
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.AbilityDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | testsession | sourceScope=player_state_scoped; shortName=DA_Ability_BlackHole nameSource=fullNameFallback objectClass=CrabAbilityDA |'
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.MeleeDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | testsession | sourceScope=player_state_scoped; shortName=DA_Melee_Hammer nameSource=fullNameFallback objectClass=CrabMeleeDA |'
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.WeaponDA` | DirectField | solo | solo-or-host | UNSAFE_DISABLED | unsafe_disabled | testsession | sourceScope=player_state_scoped |'
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.HealthInfo.CurrentHealth` | HealthInfoStructField | solo | solo-or-host | SAFE | ok | testsession | sourceScope=player_state_scoped; value=250.0 |'
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.HealthInfo.CurrentMaxHealth` | HealthInfoStructField | solo | solo-or-host | SAFE | ok | testsession | sourceScope=player_state_scoped; value=250.0 |'
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.BaseMaxHealth` | GetPropertyValue | solo | solo-or-host | SAFE | ok | testsession | sourceScope=player_state_scoped; value=250.0 |'
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.MaxHealthMultiplier` | GetPropertyValue | solo | solo-or-host | SAFE | ok | testsession | sourceScope=player_state_scoped; value=1.0 |'
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.HealthInfo` | PlayerStateHealthSample | solo | solo-or-host | SAFE | ok | testsession | sourceScope=player_state_scoped; value=currentHealth=250 currentMaxHealth=250 baseMaxHealth=250 maxHealthMultiplier=1 |'
Assert-Contains -Path $MatrixPath -Expected 'FindFirstOf.CrabHC` is ambiguous'
Assert-Contains -Path $MatrixPath -Expected 'health-playerstate-watch` is read-only local PlayerState time-series evidence for vanilla visibility'
Assert-Contains -Path $MatrixPath -Expected 'BP_Destructible_ChaoticBarrel10.HC'
Assert-Contains -Path $MatrixPath -Expected '| `CrabHC` | FindFirstOf | solo | solo-or-host | SAFE | ok | testsession | sourceScope=non_player_candidate; value=CrabHC found |'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected '| `CrabPS.WeaponDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | testsession | sourceScope=player_state_scoped; shortName=DA_Weapon_Minigun nameSource=fullNameFallback objectClass=CrabWeaponDA |'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected 'Health playerstate watch samples: 1'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected 'CrabHC touched: False'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected 'Unsafe gates: HUD=false, deepArrays=false, InventoryInfo=false, writes=false, RPCs=false, unknownRole=false, joinedClientDeep=false'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected 'Possible base health model: local PlayerState base appears 250'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected 'RuntimeProbe documents what vanilla exposes.'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected 'PlayerState identity reads are safe and redacted'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected 'cannot distinguish true solo from multiplayer host-like local context'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected 'Any candidate exposed more than one player: no'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected 'Roster source candidates attempted: Identity.FindAll.PlayerStateCandidates, Identity.GameState.SourceCandidate, Identity.PlayerArray.Shape, Identity.PlayerControllerCandidates'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected 'GameStateBase.PlayerArray returned nil / was not exposed as a Lua table'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected 'Visible player roster is still unresolved; auto-room grouping is not ready yet.'
Assert-Contains -Path (Join-Path $WorkRoot "docs\KNOWN_UNSAFE_PATHS.md") -Expected '`FindFirstOf.CrabHC` is not a safe player-health source.'
Assert-Contains -Path (Join-Path $WorkRoot "docs\UNTESTED_ACCESS_PATHS.md") -Expected 'Vanilla multiplayer evidence is local PlayerState health visibility only; it does not define shared/pooled health behavior.'
Assert-Contains -Path (Join-Path $WorkRoot "docs\UNTESTED_ACCESS_PATHS.md") -Expected 'Capped PlayerState-like discovery is gated by allowIdentityProbes'
Assert-Contains -Path (Join-Path $WorkRoot "evidence\runtime\testsession\session_manifest.json") -Expected '"warning":"research gates enabled: allowHealthProbes"'
Assert-Contains -Path (Join-Path $WorkRoot "evidence\runtime\testsession\session_manifest.json") -Expected '"activeResearchGates":["allowHealthProbes"]'
Assert-Contains -Path (Join-Path $WorkRoot "dist\wiki\Home.md") -Expected "Generated from repo docs"
Assert-Contains -Path (Join-Path $WorkRoot "dist\wiki\Safe-Access-Matrix.md") -Expected "CrabPS.WeaponDA"

$BadPathRoot = Join-Path $WorkRoot "bad-path"
New-Item -ItemType Directory -Force -Path $BadPathRoot | Out-Null
Set-Content -LiteralPath (Join-Path $BadPathRoot "access_evidence_bad.jsonl") -Encoding ASCII -Value '{"sessionId":"bad","symbol":"CrabPS.Bad","valueSummary":"C:\\Users\\dudie\\secret"}'
Push-Location $WorkRoot
try {
  Assert-CommandFails { node (Join-Path $RepoRoot "tools\import_runtime_evidence.js") --from $BadPathRoot }
} finally {
  Pop-Location
}

$CrashRoot = Join-Path $WorkRoot "crash"
New-Item -ItemType Directory -Force -Path $CrashRoot | Out-Null
Set-Content -LiteralPath (Join-Path $CrashRoot "UE4Minidump.dmp") -Encoding ASCII -Value "not importable"
Push-Location $WorkRoot
try {
  Assert-CommandFails { node (Join-Path $RepoRoot "tools\import_runtime_evidence.js") --from $CrashRoot }
} finally {
  Pop-Location
}

Write-Host "CrabRuntimeProbe evidence docs checks passed."
