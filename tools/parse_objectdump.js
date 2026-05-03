#!/usr/bin/env node
const fs = require('fs'); const path = require('path');
const dir = path.join(process.cwd(), 'objectdump');
const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => /\.(txt|md|part\d*)$/.test(f) || f.includes('.part')) : [];
const index = { classes:{}, structs:{}, functions:{}, rawMatches:[] };
for (const file of files) {
  const content = fs.readFileSync(path.join(dir,file),'utf8');
  for (const line of content.split(/\r?\n/)) {
    const c = line.match(/\bclass\s+([A-Za-z0-9_]+)/i); if (c) index.classes[c[1]] = index.classes[c[1]] || {properties:[],functions:[]};
    const s = line.match(/\bstruct\s+([A-Za-z0-9_]+)/i); if (s) index.structs[s[1]] = true;
    const fn = line.match(/\b([A-Za-z0-9_]+)\s*\(/); if (fn && line.includes('Function')) index.functions[fn[1]] = true;
    if (c||s||fn) index.rawMatches.push({file,line});
  }
}
fs.writeFileSync(path.join(dir,'objectdump_index.json'), JSON.stringify(index,null,2));
fs.writeFileSync(path.join(process.cwd(),'docs/OBJECTDUMP_INDEX.md'), `# OBJECTDUMP INDEX\n\n- Classes: ${Object.keys(index.classes).length}\n- Structs: ${Object.keys(index.structs).length}\n- Functions: ${Object.keys(index.functions).length}\n`);
