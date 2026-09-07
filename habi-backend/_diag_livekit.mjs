import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { RoomServiceClient, AgentDispatchClient } from 'livekit-server-sdk';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '.env') });

const livekitUrl = process.env.LIVEKIT_URL || '';
const key = process.env.LIVEKIT_API_KEY || '';
const secret = process.env.LIVEKIT_API_SECRET || '';
const host = livekitUrl.startsWith('wss://') ? `https://${livekitUrl.slice('wss://'.length)}` : livekitUrl;

console.log('=== Room state: habi-debug-1 ===');
try {
  const roomClient = new RoomServiceClient(host, key, secret);
  const rooms = await roomClient.listRooms();
  console.log('rooms:', rooms.map((r) => ({ name: r.name, numParticipants: r.numParticipants })));
} catch (e) {
  console.log('listRooms failed:', e.message);
}

try {
  const dispatchClient = new AgentDispatchClient(host, key, secret);
  for (const roomName of ['habi-debug-1', 'habi-voice-room']) {
    try {
      const dispatches = await dispatchClient.listDispatch(roomName);
      console.log(`dispatches in ${roomName}:`, dispatches.map((d) => ({
        id: d.dispatchId,
        agentName: d.agentName,
        state: d.state,
        roomName: d.roomName
      })));
    } catch (e) {
      console.log(`listDispatch ${roomName} failed:`, e.message);
    }
  }
} catch (e) {
  console.log('AgentDispatchClient failed:', e.message);
}

console.log('\n=== Provider key validation ===');

async function checkDeepgram() {
  try {
    const r = await fetch('https://api.deepgram.com/v1/projects', {
      headers: { Authorization: `Token ${process.env.DEEPGRAM_API_KEY || ''}` }
    });
    const t = await r.text();
    console.log('Deepgram projects:', r.status, t.slice(0, 200));
  } catch (e) {
    console.log('Deepgram check failed:', e.message);
  }
}

async function checkElevenLabs() {
  try {
    const r = await fetch('https://api.elevenlabs.io/v1/user', {
      headers: { 'xi-api-key': process.env.ELEVENLABS_API_KEY || '' }
    });
    const t = await r.text();
    console.log('ElevenLabs user:', r.status, t.slice(0, 300));
  } catch (e) {
    console.log('ElevenLabs check failed:', e.message);
  }
}

async function checkOpenRouter() {
  try {
    const r = await fetch('https://openrouter.ai/api/v1/models', {
      headers: { Authorization: `Bearer ${process.env.OPENROUTER_API_KEY || ''}` }
    });
    const t = await r.text();
    console.log('OpenRouter models:', r.status, t.slice(0, 300));
  } catch (e) {
    console.log('OpenRouter check failed:', e.message);
  }
}

await checkDeepgram();
await checkElevenLabs();
await checkOpenRouter();
