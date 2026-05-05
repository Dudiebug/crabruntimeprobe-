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
  '{"timestamp":"2026-05-04T00:00:02Z","sessionId":"testsession","game":"Crab Champions","mod":"CrabRuntimeProbe","schemaVersion":1,"probeId":"CrabPS.DirectField.WeaponDA","probeName":"CrabPS.DirectField.WeaponDA","probeSet":"equipment-direct-field-read","category":"equipment","symbol":"CrabPS.WeaponDA","owner":"CrabPS","member":"WeaponDA","accessMethod":"DirectField","accessKind":"directField","mode":"active","tickDriver":"executeDelay","tick":110,"context":"solo","role":"solo-or-host","lifecycleState":"stable","result":"unsafe_disabled","runtimeStatus":"UNSAFE_DISABLED","valueKind":"","valueSummary":"","error":"","safetyGates":{"allowHudTickHook":false,"allowDeepArrayProbes":false,"allowInventoryInfoProbes":false,"allowHealthProbes":false,"allowWriteProbes":false,"allowRpcProbes":false,"allowJoinedClientDeepProbes":false,"allowUnknownRoleProbes":false}}'
)
Set-Content -LiteralPath (Join-Path $GameResults "probe_results_$SessionId.jsonl") -Encoding ASCII -Value @(
  '{"timestamp":"2026-05-04T00:00:01Z","sessionId":"testsession","probeId":"CrabPS.GetPropertyValue.WeaponDA","probeName":"CrabPS.GetPropertyValue.WeaponDA","result":"ok"}'
)
Set-Content -LiteralPath (Join-Path $GameResults "session_manifest_$SessionId.json") -Encoding ASCII -Value '{"sessionId":"testsession","tickDriver":"executeDelay","probeSet":"equipment-property-read"}'

Push-Location $WorkRoot
try {
  node (Join-Path $RepoRoot "tools\import_runtime_evidence.js") --from $GameResults
  node (Join-Path $RepoRoot "tools\generate_access_docs.js")
  node (Join-Path $RepoRoot "tools\build_wiki_docs.js")
} finally {
  Pop-Location
}

$MatrixPath = Join-Path $WorkRoot "docs\SAFE_ACCESS_MATRIX.md"
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.WeaponDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | testsession | shortName=DA_Weapon_Minigun nameSource=fullNameFallback objectClass=CrabWeaponDA |'
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.AbilityDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | testsession | shortName=DA_Ability_BlackHole nameSource=fullNameFallback objectClass=CrabAbilityDA |'
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.MeleeDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | testsession | shortName=DA_Melee_Hammer nameSource=fullNameFallback objectClass=CrabMeleeDA |'
Assert-Contains -Path $MatrixPath -Expected '| `CrabPS.WeaponDA` | DirectField | solo | solo-or-host | UNSAFE_DISABLED | unsafe_disabled | testsession |  |'
Assert-Contains -Path (Join-Path $WorkRoot "docs\RUNTIME_EVIDENCE_INDEX.md") -Expected '| `CrabPS.WeaponDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | testsession | shortName=DA_Weapon_Minigun nameSource=fullNameFallback objectClass=CrabWeaponDA |'
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
