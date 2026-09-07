import fs from 'fs';
import path from 'path';

const root = path.join(process.cwd(), 'node_modules');
const matches = [];
const pattern = /import\s*\{[^}]*\bAgent\b[^}]*\}\s*from\s*['\"]@livekit\/agents['\"]/;
const pattern2 = /from\s*['\"]@livekit\/agents['\"]/;

function walk(dir) {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    let stat;
    try {
      stat = fs.statSync(p);
    } catch {
      continue;
    }
    if (stat.isDirectory()) {
      walk(p);
      continue;
    }
    if (!/\.(js|mjs|ts)$/.test(p)) continue;
    let txt;
    try {
      txt = fs.readFileSync(p, 'utf8');
    } catch {
      continue;
    }
    const lines = txt.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (pattern.test(line)) {
        matches.push(`${p}:${i+1}: ${line}`);
      } else if (pattern2.test(line) && /\bAgent\b/.test(line)) {
        matches.push(`${p}:${i+1}: ${line}`);
      }
    }
  }
}

walk(root);
for (const m of matches) console.log(m);
console.error(`Found ${matches.length} matches`);
