#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const root = process.cwd();
const objectdumpDir = path.join(root, 'objectdump');
const docsDir = path.join(root, 'docs');
const outJson = path.join(objectdumpDir, 'objectdump_index.json');
const outMd = path.join(docsDir, 'OBJECTDUMP_INDEX.md');

const IGNORED_INPUTS = new Set(['README.md', 'objectdump_index.json']);
const PROPERTY_TOKENS = new Set([
  'Property',
  'ObjectProperty',
  'StructProperty',
  'ArrayProperty',
  'ByteProperty',
  'UInt32Property',
  'UInt64Property',
  'UInt16Property',
  'FloatProperty',
  'DoubleProperty',
  'IntProperty',
  'Int64Property',
  'Int16Property',
  'Int8Property',
  'BoolProperty',
  'EnumProperty',
  'NameProperty',
  'StrProperty',
  'TextProperty',
  'ClassProperty',
  'SoftObjectProperty',
  'SoftClassProperty',
  'WeakObjectProperty',
  'InterfaceProperty',
  'MapProperty',
  'SetProperty',
  'MulticastInlineDelegateProperty',
  'MulticastSparseDelegateProperty',
  'DelegateProperty'
]);

const IMPORTANT_CLASSES = [
  'CrabPC',
  'CrabPS',
  'CrabGS',
  'CrabHC',
  'CrabWeaponDA',
  'CrabAbilityDA',
  'CrabMeleeDA',
  'CrabInteractPickup',
  'CrabInventorySlotUI'
];

const IMPORTANT_STRUCTS = [
  'CrabHealthInfo',
  'CrabInventoryInfo',
  'CrabAutoSave',
  'CrabWeaponMod',
  'CrabAbilityMod',
  'CrabMeleeMod',
  'CrabPerk',
  'CrabRelic',
  'CrabPickupInfo'
];

const IMPORTANT_FIELDS = [
  'CrabPC.PlayerState',
  'CrabPS.WeaponDA',
  'CrabPS.AbilityDA',
  'CrabPS.MeleeDA',
  'CrabPS.WeaponMods',
  'CrabPS.AbilityMods',
  'CrabPS.MeleeMods',
  'CrabPS.Perks',
  'CrabPS.Relics',
  'CrabPS.Crystals',
  'CrabPS.NumWeaponModSlots',
  'CrabPS.NumAbilityModSlots',
  'CrabPS.NumMeleeModSlots',
  'CrabPS.NumPerkSlots',
  'CrabPS.PawnPrivate',
  'CrabPS.HealthInfo',
  'CrabHC.HealthInfo',
  'CrabHC.OwningC',
  'CrabInventoryInfo.Level',
  'CrabInventoryInfo.AccumulatedBuff',
  'CrabInventoryInfo.Enhancements',
  'CrabWeaponMod.WeaponModDA',
  'CrabAbilityMod.AbilityModDA',
  'CrabMeleeMod.MeleeModDA',
  'CrabPerk.PerkDA',
  'CrabRelic.RelicDA',
  '*.InventoryInfo'
];

const IMPORTANT_FUNCTIONS = [
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

function isSupportedInput(name) {
  if (IGNORED_INPUTS.has(name)) return false;
  return /\.txt$/i.test(name) || /\.md$/i.test(name) || /\.part/i.test(name);
}

function lineRef(file, lineNumber, rawLine) {
  return { sourceFile: file, lineNumber, rawLine };
}

function symbolFromPath(text) {
  const match = text.match(/\/Script\/[^\s\]]+/);
  if (!match) return null;
  const symbolPath = match[0].replace(/[,\]]+$/, '');
  const cleanPath = symbolPath.replace(/^[^/]*(?=\/Script\/)/, '');
  const lastDot = cleanPath.lastIndexOf('.');
  const colon = cleanPath.indexOf(':', lastDot);
  const scriptPath = lastDot >= 0 ? cleanPath.slice(0, lastDot) : cleanPath;
  const moduleName = scriptPath.split('/').pop();
  const ownerAndMember = lastDot >= 0 ? cleanPath.slice(lastDot + 1) : cleanPath.split('/').pop();

  if (colon >= 0) {
    const owner = cleanPath.slice(lastDot + 1, colon);
    const member = cleanPath.slice(colon + 1);
    return {
      symbolPath: cleanPath,
      moduleName,
      owner,
      ownerName: owner.split('.').pop(),
      name: member.split('.').pop(),
      member
    };
  }

  return {
    symbolPath: cleanPath,
    moduleName,
    owner: null,
    ownerName: null,
    name: ownerAndMember.split('.').pop(),
    member: null
  };
}

function parseLine(rawLine, sourceFile, lineNumber) {
  const line = rawLine.trim();
  if (!line) return null;

  const tokenMatch = line.match(/^\[[^\]]+\]\s+([A-Za-z0-9_]+)/) || line.match(/^([A-Za-z0-9_]+)/);
  if (!tokenMatch) return null;
  const token = tokenMatch[1];
  const symbol = symbolFromPath(line);

  if (token === 'Class' && symbol) {
    return {
      kind: 'class',
      name: symbol.name,
      scriptPath: symbol.symbolPath,
      sourceFile,
      lineNumber,
      rawLine
    };
  }

  if ((token === 'ScriptStruct' || token === 'Struct') && symbol) {
    return {
      kind: 'struct',
      name: symbol.name,
      scriptPath: symbol.symbolPath,
      sourceFile,
      lineNumber,
      rawLine
    };
  }

  if (token === 'Enum' && symbol) {
    return {
      kind: 'enum',
      name: symbol.name,
      scriptPath: symbol.symbolPath,
      sourceFile,
      lineNumber,
      rawLine
    };
  }

  if (token === 'Function' && symbol) {
    return {
      kind: 'function',
      name: symbol.name,
      owner: symbol.ownerName,
      scriptPath: symbol.symbolPath,
      sourceFile,
      lineNumber,
      rawLine
    };
  }

  if (PROPERTY_TOKENS.has(token) && symbol) {
    return {
      kind: 'property',
      name: symbol.name,
      owner: symbol.ownerName,
      propertyType: token,
      scriptPath: symbol.symbolPath,
      sourceFile,
      lineNumber,
      rawLine
    };
  }

  if (/\/Script\//.test(line) && /\b(Class|ScriptStruct|Struct|Enum|Function|Property)\b/.test(line)) {
    return {
      kind: 'raw',
      name: symbol ? symbol.name : '',
      owner: symbol ? symbol.ownerName : null,
      scriptPath: symbol ? symbol.symbolPath : null,
      sourceFile,
      lineNumber,
      rawLine
    };
  }

  return null;
}

function incrementFileCount(fileRecord, kind) {
  fileRecord.matchCounts[kind] = (fileRecord.matchCounts[kind] || 0) + 1;
  fileRecord.matchCounts.rawMatches += 1;
}

function addEntry(index, fileRecord, entry) {
  const raw = {
    kind: entry.kind,
    name: entry.name || '',
    owner: entry.owner || null,
    type: entry.propertyType || null,
    sourceFile: entry.sourceFile,
    lineNumber: entry.lineNumber,
    rawLine: entry.rawLine
  };
  index.rawMatches.push(raw);
  incrementFileCount(fileRecord, entry.kind);

  if (entry.kind === 'class') index.classes.push(entry);
  else if (entry.kind === 'struct') index.structs.push(entry);
  else if (entry.kind === 'enum') index.enums.push(entry);
  else if (entry.kind === 'function') index.functions.push(entry);
  else if (entry.kind === 'property') index.properties.push(entry);
}

function createImportantSummary(index) {
  const classNames = new Set(index.classes.map((entry) => entry.name));
  const structNames = new Set(index.structs.map((entry) => entry.name));
  const propertiesByKey = new Map();
  const functionsByName = new Map();

  for (const prop of index.properties) {
    const key = `${prop.owner || ''}.${prop.name}`;
    if (!propertiesByKey.has(key)) propertiesByKey.set(key, []);
    propertiesByKey.get(key).push(lineRef(prop.sourceFile, prop.lineNumber, prop.rawLine));
    if (prop.name === 'InventoryInfo') {
      const wildcard = '*.InventoryInfo';
      if (!propertiesByKey.has(wildcard)) propertiesByKey.set(wildcard, []);
      propertiesByKey.get(wildcard).push(lineRef(prop.sourceFile, prop.lineNumber, prop.rawLine));
    }
  }

  for (const fn of index.functions) {
    if (!functionsByName.has(fn.name)) functionsByName.set(fn.name, []);
    functionsByName.get(fn.name).push(lineRef(fn.sourceFile, fn.lineNumber, fn.rawLine));
  }

  return {
    classes: IMPORTANT_CLASSES.map((name) => ({
      name,
      discovered: classNames.has(name),
      runtimeConfirmed: false,
      status: classNames.has(name) ? 'unverified' : 'not_found',
      locations: index.classes.filter((entry) => entry.name === name).map((entry) => lineRef(entry.sourceFile, entry.lineNumber, entry.rawLine))
    })),
    structs: IMPORTANT_STRUCTS.map((name) => ({
      name,
      discovered: structNames.has(name),
      runtimeConfirmed: false,
      status: structNames.has(name) ? 'unverified' : 'not_found',
      locations: index.structs.filter((entry) => entry.name === name).map((entry) => lineRef(entry.sourceFile, entry.lineNumber, entry.rawLine))
    })),
    fields: IMPORTANT_FIELDS.map((key) => ({
      name: key,
      discovered: propertiesByKey.has(key),
      runtimeConfirmed: false,
      status: propertiesByKey.has(key) ? 'unverified' : 'not_found',
      locations: propertiesByKey.get(key) || []
    })),
    functions: IMPORTANT_FUNCTIONS.map((name) => ({
      name,
      discovered: functionsByName.has(name),
      runtimeConfirmed: false,
      status: functionsByName.has(name) ? 'unverified' : 'not_found',
      locations: functionsByName.get(name) || []
    }))
  };
}

function mdBool(value) {
  return value ? 'yes' : 'no';
}

function mdStatus(entry) {
  return entry.discovered ? 'objectdump discovered; runtime unverified' : 'not discovered; runtime unverified';
}

function firstLocations(locations, max = 3) {
  if (!locations || locations.length === 0) return '';
  return locations.slice(0, max).map((loc) => `${loc.sourceFile}:${loc.lineNumber}`).join('<br>');
}

function tableRows(entries, nameLabel = 'Symbol') {
  return entries.map((entry) => `| \`${entry.name}\` | ${mdBool(entry.discovered)} | no | ${entry.status} | ${firstLocations(entry.locations)} |`).join('\n');
}

function inventoryRows(index) {
  const important = index.important.fields;
  const field = (name) => important.find((entry) => entry.name === name);
  const rows = [
    ['Weapon mods', 'CrabPS.WeaponMods', 'CrabWeaponMod.WeaponModDA', 'CrabInventoryInfo'],
    ['Ability mods', 'CrabPS.AbilityMods', 'CrabAbilityMod.AbilityModDA', 'CrabInventoryInfo'],
    ['Melee mods', 'CrabPS.MeleeMods', 'CrabMeleeMod.MeleeModDA', 'CrabInventoryInfo'],
    ['Perks', 'CrabPS.Perks', 'CrabPerk.PerkDA', 'CrabInventoryInfo'],
    ['Relics', 'CrabPS.Relics', 'CrabRelic.RelicDA', 'CrabInventoryInfo']
  ];
  return rows.map(([label, arrayField, daField, info]) => {
    const arrayEntry = field(arrayField) || { discovered: false };
    const daEntry = field(daField) || { discovered: false };
    const infoType = index.important.structs.find((entry) => entry.name === info)
      || index.important.classes.find((entry) => entry.name === info)
      || { discovered: false };
    return `| ${label} | \`${arrayField}\` | ${mdBool(arrayEntry.discovered)} | \`${daField}\` | ${mdBool(daEntry.discovered)} | \`${info}\` | ${mdBool(infoType.discovered)} | unverified |`;
  }).join('\n');
}

function healthRows(index) {
  const fields = index.important.fields;
  const classes = index.important.classes;
  const structs = index.important.structs;
  const field = (name) => fields.find((entry) => entry.name === name) || { discovered: false };
  const cls = (name) => classes.find((entry) => entry.name === name) || { discovered: false };
  const struct = (name) => structs.find((entry) => entry.name === name) || { discovered: false };
  return [
    `| \`CrabPS.HealthInfo\` | ${mdBool(field('CrabPS.HealthInfo').discovered)} | no | unverified |`,
    `| \`CrabHC.HealthInfo\` | ${mdBool(field('CrabHC.HealthInfo').discovered)} | no | unverified |`,
    `| \`CrabHC.OwningC\` | ${mdBool(field('CrabHC.OwningC').discovered)} | no | unverified |`,
    `| \`CrabHealthInfo\` | ${mdBool(cls('CrabHealthInfo').discovered || struct('CrabHealthInfo').discovered)} | no | unverified |`
  ].join('\n');
}

function renderMarkdown(index) {
  const allScanned = index.summary.filesDiscovered === index.summary.filesScanned && index.summary.filesSkippedOrFailed === 0;
  let md = '# Object Dump Index\n\n';
  md += 'Object dump presence is not runtime confirmation. All entries in this document are unverified until confirmed by CrabRuntimeProbe runtime results.\n\n';

  md += '## Summary\n\n';
  md += `- Generated at: ${index.generatedAt}\n`;
  md += `- Files discovered: ${index.summary.filesDiscovered}\n`;
  md += `- Files scanned: ${index.summary.filesScanned}\n`;
  md += `- Files skipped/failed: ${index.summary.filesSkippedOrFailed}\n`;
  md += `- All discovered dump parts scanned: ${allScanned ? 'yes' : 'no'}\n`;
  md += `- Raw matches: ${index.summary.rawMatches}\n`;
  md += `- Classes: ${index.summary.classes}\n`;
  md += `- Structs: ${index.summary.structs}\n`;
  md += `- Enums: ${index.summary.enums}\n`;
  md += `- Properties: ${index.summary.properties}\n`;
  md += `- Functions: ${index.summary.functions}\n\n`;

  md += '## Files Discovered/Scanned/Skipped\n\n';
  md += '| File | Size bytes | Scanned | Warning/Error | Raw | Classes | Structs | Enums | Properties | Functions |\n';
  md += '|---|---:|---|---|---:|---:|---:|---:|---:|---:|\n';
  for (const file of index.files.discovered) {
    md += `| \`${file.name}\` | ${file.size ?? ''} | ${mdBool(file.scanned)} | ${file.warning || file.error || ''} | ${file.matchCounts.rawMatches || 0} | ${file.matchCounts.class || 0} | ${file.matchCounts.struct || 0} | ${file.matchCounts.enum || 0} | ${file.matchCounts.property || 0} | ${file.matchCounts.function || 0} |\n`;
  }
  md += '\n';

  md += '## Warnings\n\n';
  if (index.warnings.length === 0) md += '- None.\n\n';
  else md += index.warnings.map((warning) => `- ${warning}`).join('\n') + '\n\n';

  md += '## Important Classes\n\n';
  md += '| Class | Objectdump discovered | Runtime confirmed | Status | Locations |\n|---|---|---|---|---|\n';
  md += tableRows(index.important.classes, 'Class') + '\n\n';

  md += '## Important Structs\n\n';
  md += '| Struct | Objectdump discovered | Runtime confirmed | Status | Locations |\n|---|---|---|---|---|\n';
  md += tableRows(index.important.structs, 'Struct') + '\n\n';

  md += '## Important Fields\n\n';
  md += '| Field | Objectdump discovered | Runtime confirmed | Status | Locations |\n|---|---|---|---|---|\n';
  md += tableRows(index.important.fields, 'Field') + '\n\n';

  md += '## Important Functions/RPCs\n\n';
  md += '| Function/RPC | Objectdump discovered | Runtime confirmed | Status | Locations |\n|---|---|---|---|---|\n';
  md += tableRows(index.important.functions, 'Function') + '\n\n';

  md += '## Inventory Object Map\n\n';
  md += '| Area | Array field | Array discovered | DA field | DA discovered | Inventory info type | Info discovered | Runtime status |\n';
  md += '|---|---|---|---|---|---|---|---|\n';
  md += inventoryRows(index) + '\n\n';

  md += '## Health Object Map\n\n';
  md += '| Symbol | Objectdump discovered | Runtime confirmed | Status |\n|---|---|---|---|\n';
  md += healthRows(index) + '\n\n';

  md += '## Notes and Limitations\n\n';
  md += '- The parser scans every supported input file in `objectdump/` and records failures instead of silently skipping parts.\n';
  md += '- `README.md` and `objectdump_index.json` are generated/non-input files and are intentionally ignored.\n';
  md += '- Object dump lines can be oddly formatted; raw matched lines are preserved in `objectdump/objectdump_index.json` when classification is uncertain.\n';
  md += '- Objectdump discovered means the symbol exists in static dump data. Runtime confirmed remains `no` until a ProbeRunner result proves the access path is safe.\n';

  return md;
}

function discoverFiles() {
  if (!fs.existsSync(objectdumpDir)) return [];
  return fs.readdirSync(objectdumpDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && isSupportedInput(entry.name))
    .map((entry) => {
      const full = path.join(objectdumpDir, entry.name);
      let size = null;
      try {
        size = fs.statSync(full).size;
      } catch (_) {
        size = null;
      }
      return {
        name: entry.name,
        path: full,
        size,
        scanned: false,
        warning: '',
        error: '',
        matchCounts: {
          rawMatches: 0,
          class: 0,
          struct: 0,
          enum: 0,
          function: 0,
          property: 0,
          raw: 0
        }
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: 'base' }));
}

async function scanFile(index, fileRecord) {
  let lineNumber = 0;
  try {
    await fs.promises.access(fileRecord.path, fs.constants.R_OK);
    const stream = fs.createReadStream(fileRecord.path, { encoding: 'utf8' });
    stream.on('error', (err) => {
      throw err;
    });

    const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });
    for await (const line of rl) {
      lineNumber += 1;
      const entry = parseLine(line, fileRecord.name, lineNumber);
      if (entry) addEntry(index, fileRecord, entry);
    }

    fileRecord.scanned = true;
    if (fileRecord.matchCounts.rawMatches === 0) {
      fileRecord.warning = 'scanned with zero objectdump matches';
      index.warnings.push(`${fileRecord.name}: ${fileRecord.warning}`);
    }
  } catch (err) {
    fileRecord.scanned = false;
    fileRecord.error = err && err.message ? err.message : String(err);
    index.warnings.push(`${fileRecord.name}: ${fileRecord.error}`);
  }
}

async function main() {
  const discovered = discoverFiles();

  if (discovered.length === 0) {
    console.log('No object dump files found. Skipping object dump index generation.');
    process.exit(0);
  }

  fs.mkdirSync(docsDir, { recursive: true });
  fs.mkdirSync(objectdumpDir, { recursive: true });

  const index = {
    generatedAt: new Date().toISOString(),
    files: {
      discovered: discovered.map(({ path: _path, ...file }) => file),
      scanned: [],
      skippedFailed: []
    },
    classes: [],
    structs: [],
    enums: [],
    functions: [],
    properties: [],
    rawMatches: [],
    warnings: []
  };

  for (let i = 0; i < discovered.length; i += 1) {
    const fileRecord = discovered[i];
    await scanFile(index, fileRecord);
    const publicRecord = index.files.discovered[i];
    Object.assign(publicRecord, {
      scanned: fileRecord.scanned,
      warning: fileRecord.warning,
      error: fileRecord.error,
      matchCounts: fileRecord.matchCounts
    });
    if (fileRecord.scanned) index.files.scanned.push(publicRecord);
    else index.files.skippedFailed.push(publicRecord);
  }

  index.summary = {
    filesDiscovered: index.files.discovered.length,
    filesScanned: index.files.scanned.length,
    filesSkippedOrFailed: index.files.skippedFailed.length,
    rawMatches: index.rawMatches.length,
    classes: index.classes.length,
    structs: index.structs.length,
    enums: index.enums.length,
    properties: index.properties.length,
    functions: index.functions.length
  };
  index.important = createImportantSummary(index);

  fs.writeFileSync(outJson, JSON.stringify(index, null, 2));
  fs.writeFileSync(outMd, renderMarkdown(index));
  console.log(`Scanned ${index.summary.filesScanned}/${index.summary.filesDiscovered} object dump file(s).`);
  if (index.summary.filesSkippedOrFailed > 0) {
    console.log(`Recorded ${index.summary.filesSkippedOrFailed} skipped/failed object dump file(s).`);
  }
  console.log('Wrote', outJson, 'and', outMd);
}

main().catch((err) => {
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
