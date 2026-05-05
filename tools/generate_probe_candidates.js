#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const root = process.cwd();
const idxPath = path.join(root, 'objectdump', 'objectdump_index.json');
const outMd = path.join(root, 'docs', 'PROBE_CANDIDATES.md');

if (!fs.existsSync(idxPath)) {
  console.log('No object dump index found. Skipping probe candidate generation.');
  process.exit(0);
}

const index = JSON.parse(fs.readFileSync(idxPath, 'utf8'));

const INVENTORY_AREAS = [
  {
    label: 'WeaponMods / WeaponModDA',
    arrayName: 'WeaponMods',
    slotStruct: 'CrabWeaponMod',
    daField: 'WeaponModDA'
  },
  {
    label: 'AbilityMods / AbilityModDA',
    arrayName: 'AbilityMods',
    slotStruct: 'CrabAbilityMod',
    daField: 'AbilityModDA'
  },
  {
    label: 'MeleeMods / MeleeModDA',
    arrayName: 'MeleeMods',
    slotStruct: 'CrabMeleeMod',
    daField: 'MeleeModDA'
  },
  {
    label: 'Perks / PerkDA',
    arrayName: 'Perks',
    slotStruct: 'CrabPerk',
    daField: 'PerkDA'
  },
  {
    label: 'Relics / RelicDA',
    arrayName: 'Relics',
    slotStruct: 'CrabRelic',
    daField: 'RelicDA'
  }
];

const KNOWN_RPC_FUNCTIONS = [
  'ServerEquipInventory',
  'ServerSetWeaponDA',
  'ServerSetAbilityDA',
  'ServerSetMeleeDA',
  'ServerIncrementNumInventorySlots',
  'ServerRemoveWeaponMod',
  'ServerRemoveAbilityMod',
  'ServerRemoveMeleeMod',
  'ServerRemovePerk',
  'ServerRemoveRelic',
  'OnRep_Inventory',
  'OnRep_Crystals',
  'OnRep_WeaponDA',
  'OnRep_AbilityDA',
  'OnRep_MeleeDA',
  'ClientRefreshPSUI',
  'ClientOnPickedUpPickup'
];

function hasClass(name) {
  return (index.classes || []).some((entry) => entry.name === name);
}

function hasStruct(name) {
  return (index.structs || []).some((entry) => entry.name === name);
}

function hasType(name) {
  return hasClass(name) || hasStruct(name);
}

function hasField(owner, name) {
  return (index.properties || []).some((entry) => entry.owner === owner && entry.name === name);
}

function hasFunction(name) {
  return (index.functions || []).some((entry) => entry.name === name);
}

function symbolStatus(symbol, discovered) {
  return `${symbol} (${discovered ? 'objectdump discovered' : 'not discovered in objectdump'})`;
}

function candidate(category, id, symbol, discovered, gate, notes) {
  return {
    category,
    id,
    symbol: symbolStatus(symbol, discovered),
    source: 'objectdump',
    runtimeStatus: 'unverified',
    gate,
    notes
  };
}

const groups = {
  core: [],
  equipment: [],
  'inventory-array-shallow': [],
  'inventory-array-deep': [],
  'inventory-info': [],
  roster: [],
  'resource-visibility': [],
  health: [],
  'rpc-dryrun': [],
  'write-unsafe': [],
  unknown: []
};

groups.core.push(candidate('core', 'FindFirstOf.CrabPC', 'CrabPC', hasClass('CrabPC'), 'mode = active', 'Find the player controller class instance. Observe mode has its own passive context row and does not run this candidate.'));
groups.core.push(candidate('core', 'CrabPC.IsValid', 'CrabPC', hasClass('CrabPC'), 'mode = active', 'Validate the cached CrabPC object before other reads.'));
groups.core.push(candidate('core', 'CrabPC.GetPropertyValue.PlayerState', 'CrabPC.PlayerState', hasField('CrabPC', 'PlayerState'), 'mode = active', 'Read PlayerState through GetPropertyValue only.'));
groups.core.push(candidate('core', 'CrabPS.IsValid', 'CrabPS', hasClass('CrabPS'), 'mode = active', 'Validate the cached PlayerState object.'));

for (const field of ['WeaponDA', 'AbilityDA', 'MeleeDA']) {
  const discovered = hasField('CrabPS', field);
  groups.equipment.push(candidate('equipment', `CrabPS.GetPropertyValue.${field}`, `CrabPS.${field}`, discovered, 'mode = active; probeSet includes equipment-read', 'Property read candidate only.'));
  groups.equipment.push(candidate('equipment', `CrabPS.DirectField.${field}`, `CrabPS.${field}`, discovered, 'mode = active; probeSet includes equipment-read', 'Direct field candidate must stay separate from GetPropertyValue.'));
}

for (const area of INVENTORY_AREAS) {
  const arrayDiscovered = hasField('CrabPS', area.arrayName);
  const daDiscovered = hasField(area.slotStruct, area.daField);
  const inventoryInfoDiscovered = hasField(area.slotStruct, 'InventoryInfo') || hasType('CrabInventoryInfo');

  groups['inventory-array-shallow'].push(candidate('inventory-array-shallow', `CrabPS.GetPropertyValue.${area.arrayName}`, `CrabPS.${area.arrayName}`, arrayDiscovered, 'mode = active; explicit shallow inventory research config', `${area.label}; reads the array property only.`));
  groups['inventory-array-shallow'].push(candidate('inventory-array-shallow', `${area.arrayName}.ForEach.CountOnly`, `CrabPS.${area.arrayName}`, arrayDiscovered, 'mode = active; explicit shallow inventory research config', `${area.label}; count elements without dereferencing slot objects.`));
  groups['inventory-array-shallow'].push(candidate('inventory-array-shallow', `${area.arrayName}.ForEach.FirstElementSeen`, `CrabPS.${area.arrayName}`, arrayDiscovered, 'mode = active; explicit shallow inventory research config', `${area.label}; record that a first array element wrapper exists without calling get().`));

  groups['inventory-array-deep'].push(candidate('inventory-array-deep', `${area.arrayName}.FirstElement.Get`, `${area.slotStruct}`, hasStruct(area.slotStruct), 'allowDeepArrayProbes = true', `${area.label}; risky TArray element dereference.`));
  groups['inventory-array-deep'].push(candidate('inventory-array-deep', `${area.arrayName}.FirstElement.IsValid`, `${area.slotStruct}`, hasStruct(area.slotStruct), 'allowDeepArrayProbes = true', `${area.label}; validate dereferenced first slot.`));
  groups['inventory-array-deep'].push(candidate('inventory-array-deep', `${area.arrayName}.FirstSlot.GetPropertyValue.${area.daField}`, `${area.slotStruct}.${area.daField}`, daDiscovered, 'allowDeepArrayProbes = true', 'Property read from dereferenced slot.'));
  groups['inventory-array-deep'].push(candidate('inventory-array-deep', `${area.arrayName}.FirstSlot.DirectField.${area.daField}`, `${area.slotStruct}.${area.daField}`, daDiscovered, 'allowDeepArrayProbes = true', 'Direct field read from dereferenced slot; keep separate from GetPropertyValue.'));
  groups['inventory-array-deep'].push(candidate('inventory-array-deep', `${area.arrayName}.FirstDA.GetName`, `${area.slotStruct}.${area.daField}`, daDiscovered, 'allowDeepArrayProbes = true', 'Name read on first DA object after slot/DA validation.'));
  groups['inventory-array-deep'].push(candidate('inventory-array-deep', `${area.arrayName}.FirstDA.GetFullName`, `${area.slotStruct}.${area.daField}`, daDiscovered, 'allowDeepArrayProbes = true', 'FullName read on first DA object after slot/DA validation.'));

  groups['inventory-info'].push(candidate('inventory-info', `${area.arrayName}.FirstSlot.InventoryInfo.DirectField`, `${area.slotStruct}.InventoryInfo`, inventoryInfoDiscovered, 'allowInventoryInfoProbes = true', 'InventoryInfo direct field candidate from dereferenced slot.'));
  groups['inventory-info'].push(candidate('inventory-info', `${area.arrayName}.InventoryInfo.Level`, 'CrabInventoryInfo.Level', hasField('CrabInventoryInfo', 'Level'), 'allowInventoryInfoProbes = true', 'InventoryInfo scalar field candidate.'));
  groups['inventory-info'].push(candidate('inventory-info', `${area.arrayName}.InventoryInfo.AccumulatedBuff`, 'CrabInventoryInfo.AccumulatedBuff', hasField('CrabInventoryInfo', 'AccumulatedBuff'), 'allowInventoryInfoProbes = true', 'InventoryInfo scalar field candidate.'));
  groups['inventory-info'].push(candidate('inventory-info', `${area.arrayName}.InventoryInfo.Enhancements`, 'CrabInventoryInfo.Enhancements', hasField('CrabInventoryInfo', 'Enhancements'), 'allowInventoryInfoProbes = true', 'InventoryInfo enhancements array candidate.'));
  groups['inventory-info'].push(candidate('inventory-info', `${area.arrayName}.Enhancements.ForEach.CountOnly`, 'CrabInventoryInfo.Enhancements', hasField('CrabInventoryInfo', 'Enhancements'), 'allowInventoryInfoProbes = true', 'Count enhancements without deep dereference.'));
}

groups.health.push(candidate('health', 'CrabPS.GetPropertyValue.HealthInfo', 'CrabPS.HealthInfo', hasField('CrabPS', 'HealthInfo'), 'allowHealthProbes = true', 'HealthInfo candidate; disabled until explicit health probe phase.'));
groups.health.push(candidate('health', 'CrabHC.GetPropertyValue.HealthInfo', 'CrabHC.HealthInfo', hasField('CrabHC', 'HealthInfo'), 'allowHealthProbes = true', 'Health component HealthInfo candidate.'));
groups.health.push(candidate('health', 'CrabHC.GetPropertyValue.OwningC', 'CrabHC.OwningC', hasField('CrabHC', 'OwningC'), 'allowHealthProbes = true', 'Health owner candidate.'));

groups.roster.push(candidate('roster', 'Identity.GameState.SourceCandidate', 'GameStateBase / GameState', hasClass('GameStateBase') || hasClass('GameState'), 'allowIdentityProbes = true', 'FindFirstOf source identity only: GetFullName/GetName/GetClass, no roster traversal.'));
groups.roster.push(candidate('roster', 'Identity.CrabGS.SourceCandidate', 'CrabGS', hasClass('CrabGS'), 'allowIdentityProbes = true', 'FindFirstOf CrabGS source identity only. Objectdump shows CrabGS extends GameStateBase; no CrabGS-specific PlayerArray field was found.'));
groups.roster.push(candidate('roster', 'Identity.PlayerArray.Shape', 'GameStateBase.PlayerArray', hasField('GameStateBase', 'PlayerArray'), 'allowIdentityProbes = true', 'Shape-only PlayerArray probe records nil/userdata/table/unsupported and samples table length up to cap without recursive traversal.'));
groups.roster.push(candidate('roster', 'Identity.VisiblePlayers.SourceCandidate', 'GameStateBase.PlayerArray', hasField('GameStateBase', 'PlayerArray'), 'allowIdentityProbes = true', 'Capped read-only PlayerArray identity candidate. Emits only fingerprints/redacted identity values; raw identity remains disabled by default.'));
groups.roster.push(candidate('roster', 'Identity.FindAll.PlayerStateCandidates', 'PlayerState / CrabPS', hasClass('PlayerState') || hasClass('CrabPS'), 'allowIdentityProbes = true', 'FindAllOf availability checked first, then capped PlayerState-like candidates only; no arbitrary property dumping.'));
groups.roster.push(candidate('roster', 'Identity.PlayerControllerCandidates', 'PlayerController / CrabPC', hasClass('PlayerController') || hasClass('CrabPC'), 'allowIdentityProbes = true', 'FindAllOf availability checked first, then capped controller candidates; reads only PlayerState from valid controllers.'));

for (const field of ['Crystals', 'Keys', 'NumWeaponModSlots', 'NumAbilityModSlots', 'NumMeleeModSlots', 'NumPerkSlots', 'WeaponDA', 'AbilityDA', 'MeleeDA', 'WeaponMods', 'AbilityMods', 'MeleeMods', 'Perks', 'Relics']) {
  const isArray = /Mods$|^Perks$|^Relics$/.test(field);
  groups['resource-visibility'].push(candidate(
    'resource-visibility',
    `ResourceVisibility.CrabPS.${field}`,
    `CrabPS.${field}`,
    hasField('CrabPS', field),
    'allowResourceVisibilityProbes = true',
    isArray
      ? 'Count-only resource visibility check; no element dereference, InventoryInfo, or Enhancements.'
      : 'Explicit read-only resource visibility field check across capped visible PlayerState candidates.'
  ));
}

for (const fn of KNOWN_RPC_FUNCTIONS) {
  const discovered = hasFunction(fn);
  const isMutatingServer = /^Server/.test(fn);
  groups['rpc-dryrun'].push(candidate('rpc-dryrun', `FunctionPresence.${fn}`, fn, discovered, 'allowRpcProbes = true', 'Documentation-only function presence candidate. Do not call mutating RPCs.'));
  if (isMutatingServer) {
    groups['write-unsafe'].push(candidate('write-unsafe', `DoNotCall.${fn}`, fn, discovered, 'not allowed', 'Mutating server/write path. Document only; do not implement as a runtime probe.'));
  }
}

for (const name of ['CrabGS', 'CrabAutoSave', 'CrabInteractPickup', 'CrabPickupInfo', 'CrabInventorySlotUI']) {
  groups.unknown.push(candidate('unknown', `FindFirstOf.${name}`, name, hasType(name), 'none; documentation only', 'Objectdump symbol of interest with no runtime access plan yet.'));
}

function sectionTitle(category) {
  return {
    core: 'Core Probes',
    equipment: 'Equipment Probes',
    'inventory-array-shallow': 'Inventory Array Shallow Probes',
    'inventory-array-deep': 'Inventory Array Deep Probes',
    'inventory-info': 'InventoryInfo Probes',
    roster: 'Roster Identity Probes',
    'resource-visibility': 'Multiplayer Resource Visibility Probes',
    health: 'Health Probes',
    'rpc-dryrun': 'RPC Dry-Run Candidates',
    'write-unsafe': 'Write-Unsafe Candidates',
    unknown: 'Unknown'
  }[category];
}

function renderGroup(category, candidates) {
  let md = `## ${sectionTitle(category)}\n\n`;
  if (candidates.length === 0) return md + '- None.\n\n';
  md += '| Probe id | Related objectdump symbol | Source | Runtime status | Required safety gate | Notes |\n';
  md += '|---|---|---|---|---|---|\n';
  for (const item of candidates) {
    md += `| \`${item.id}\` | \`${item.symbol}\` | ${item.source} | ${item.runtimeStatus} | \`${item.gate}\` | ${item.notes} |\n`;
  }
  return md + '\n';
}

let md = '# Probe Candidates\n\n';
md += '## Important Warning\n\n';
md += 'Object dump presence does not mean runtime-safe. Candidates are documentation only until confirmed by ProbeRunner results.\n\n';
md += `Generated from \`objectdump/objectdump_index.json\` at ${new Date().toISOString()}.\n\n`;

for (const category of ['core', 'equipment', 'inventory-array-shallow', 'inventory-array-deep', 'inventory-info', 'roster', 'health', 'rpc-dryrun', 'write-unsafe', 'unknown']) {
  md += renderGroup(category, groups[category]);
}

md += '## How to Enable Later\n\n';
md += '- Keep default `mode = observe` for first in-game tests.\n';
md += '- Switch to `mode = active` only after observe rows are stable and reviewed.\n';
md += '- Enable deep inventory candidates only with `allowDeepArrayProbes = true`.\n';
md += '- Enable InventoryInfo candidates only with `allowInventoryInfoProbes = true`.\n';
md += '- Enable health candidates only with `allowHealthProbes = true`.\n';
md += '- Enable roster identity candidates only with `allowIdentityProbes = true`; keep `allowRawIdentityEvidence = false` unless private evidence capture is explicitly requested.\n';
md += '- Enable multiplayer resource visibility candidates only with `allowResourceVisibilityProbes = true`; keep reads capped, count-only for arrays, and keep writes/RPCs/HUD/deep arrays/InventoryInfo disabled.\n';
md += '- Do not implement or call write-unsafe or mutating RPC candidates in CrabRuntimeProbe.\n';

fs.mkdirSync(path.dirname(outMd), { recursive: true });
fs.writeFileSync(outMd, md);
console.log('Wrote', outMd);
