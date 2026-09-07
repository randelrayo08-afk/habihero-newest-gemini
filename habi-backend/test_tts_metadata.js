// Simple test client for /api/companion/tts-metadata
const fetch = global.fetch || require('node-fetch');

async function run(){
  const url = 'http://localhost:5000/api/companion/tts-metadata';
  const resp = await fetch(url, {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({ text: 'Hello, this is a TTS metadata test', includeAudio: false })
  });
  const j = await resp.json();
  console.log('Status', resp.status);
  console.log(JSON.stringify(j, null, 2));
}

run().catch(e=>{ console.error(e); process.exit(1); });
