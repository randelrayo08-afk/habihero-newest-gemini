import fs from 'fs';
import path from 'path';

const root = path.join(process.cwd(), 'node_modules');
const searchDirs = [
  path.join(root, '@livekit', 'agents', 'dist'),
  path.join(root, '@livekit', 'agents', 'src'),
  path.join(root, '@livekit', 'agents-plugin-openai', 'dist'),
  path.join(root, '@livekit', 'agents-plugin-openai', 'src')
];
const results = [];

function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const stat = fs.statSync(p);
    if (stat.isDirectory()) {
      walk(p);
    } else if (/\.(js|mjs|ts)$/.test(p)) {
      const txt = fs.readFileSync(p, 'utf8');
      const lines = txt.split(/\r?\n/);
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.includes("from '@livekit/agents'") || line.includes('from \"@livekit/agents\"') || line.includes("require('@livekit/agents')") || line.includes('require(\"@livekit/agents\")')) {
          if (line.includes('Agent')) {
            results.push(`${p}:${i + 1}: ${line}`);
          }
        }
      }
    }
  }
}

for (const dir of searchDirs) {
  walk(dir);
}
for (const file of results) {
  console.log(file);
}
console.error(`Found ${results.length} matches`);
