import fs from 'fs';
import path from 'path';

const root = path.join(process.cwd(), 'node_modules');
const files = [
  'node_modules/@livekit/agents-plugin-openai/dist/realtime/realtime_model.js',
  'node_modules/@livekit/agents-plugin-openai/dist/realtime/realtime_model_beta.js',
  'node_modules/@livekit/agents-plugin-openai/src/realtime/realtime_model.ts',
  'node_modules/@livekit/agents-plugin-openai/src/realtime/realtime_model_beta.ts',
  'node_modules/@livekit/agents/dist/voice/testing/index.d.ts',
  'node_modules/@livekit/agents/src/voice/testing/index.ts'
];

for (const relative of files) {
  const file = path.join(process.cwd(), relative);
  if (!fs.existsSync(file)) continue;
  const txt = fs.readFileSync(file, 'utf8');
  const lines = txt.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/from\s+['\"]@livekit\/agents['\"]/.test(line) || line.includes('require("@livekit/agents")') || line.includes("require('@livekit/agents')")) {
      if (/\bAgent\b/.test(line)) {
        console.log(`${relative}:${i+1}:${line}`);
      }
    }
    if (/\bAgent\b/.test(line) && line.includes('from')) {
      if (line.includes('@livekit/agents')) {
        console.log(`${relative}:${i+1}:${line}`);
      }
    }
  }
}
