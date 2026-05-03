#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const root = process.cwd();
const dir = path.join(root, 'objectdump');
const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => /\.(txt|md)$/.test(f) || f.includes('.part')) : [];
const idx = { classes: {}, structs: {}, functions: {}, properties: {}, raw: [] };
for (const f of files) {
  const content = fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/);
  for (const line of content) {
    if (!line.trim()) continue;
    idx.raw.push({ file: f, line });
    let m = line.match(/\bclass\s+([A-Za-z0-9_]+)/i); if (m) idx.classes[m[1]] = true;
    m = line.match(/\bstruct\s+([A-Za-z0-9_]+)/i); if (m) idx.structs[m[1]] = true;
    m = line.match(/\b([A-Za-z0-9_]+)\s*\(/); if (m) idx.functions[m[1]] = true;
    m = line.match(/\b([A-Za-z0-9_]+)\s*:\s*([A-Za-z0-9_<>]+)/); if (m) idx.properties[m[1]] = m[2];
  }
}
const out = {
  classes: Object.keys(idx.classes).sort(), structs: Object.keys(idx.structs).sort(),
  functions: Object.keys(idx.functions).sort(), properties: idx.properties, raw: idx.raw
};
fs.writeFileSync(path.join(dir, 'objectdump_index.json'), JSON.stringify(out, null, 2));
fs.writeFileSync(path.join(root, 'docs/OBJECTDUMP_INDEX.md'), `# Objectdump Index\n\nClasses: ${out.classes.length}\nStructs: ${out.structs.length}\nFunctions: ${out.functions.length}\nProperties: ${Object.keys(out.properties).length}\n`);
