// Simple test: request companion TTS then POST it to companion STT
// Usage: node test_stt_roundtrip.js

const base = 'http://localhost:5000';

async function wait(ms){ return new Promise(r=>setTimeout(r,ms)); }

async function getTts(){
  for(let i=0;i<10;i++){
    try{
      console.log('Requesting TTS (attempt', i+1, ')');
      const resp = await fetch(base+'/api/companion/tts',{method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({text:'Hello from test_stt_roundtrip', voiceId:''})});
      if(!resp.ok){
        console.log('TTS responded', resp.status);
        const txt = await resp.text();
        console.log(txt);
        await wait(1000);
        continue;
      }
      const contentType = resp.headers.get('content-type')||'audio/wav';
      const ab = await resp.arrayBuffer();
      const buf = Buffer.from(ab);
      return {buf, contentType};
    }catch(e){
      console.warn('TTS request error', e.message||e);
      await wait(1000);
    }
  }
  throw new Error('TTS failed after retries');
}

async function postStt(base64, contentType){
  const body = { audioBase64: base64, contentType };
  const resp = await fetch(base+'/api/companion/stt', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body) });
  const txt = await resp.text();
  console.log('STT status', resp.status);
  try{ console.log('STT json:', JSON.parse(txt)); } catch(e){ console.log('STT raw:', txt); }
}

(async ()=>{
  try{
    const {buf, contentType} = await getTts();
    console.log('Got TTS bytes length', buf.length, 'content-type', contentType);
    const b64 = buf.toString('base64');
    await postStt(b64, contentType);
  }catch(e){
    console.error('Test failed', e.message||e);
  }
})();
